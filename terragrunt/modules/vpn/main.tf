data "google_compute_zones" "available" {}

data "google_compute_machine_types" "available" {
  for_each = toset(data.google_compute_zones.available.names)
  zone     = each.value
}

locals {
  node_pools = flatten([
    for node_pool in [
      {
        machine_type     = var.node_pool_vpn_machine_type
        node_pool_name   = "vpn"
        total_node_count = var.node_pool_vpn_node_count
      },
    ] :
    [
      for available_zones in [
        sort([
          for zone_name, available_machine_types in data.google_compute_machine_types.available :
          zone_name
          if contains(
            [for machine_types in available_machine_types.machine_types : machine_types.name],
            node_pool.machine_type,
          )
        ])
      ] :
      [
        for i, zone_name in available_zones :
        {
          machine_type   = node_pool.machine_type
          node_pool_name = node_pool.node_pool_name
          zone_name      = zone_name
          zone_node_count = (
            floor(node_pool.total_node_count / length(available_zones))
            + (i < (node_pool.total_node_count % length(available_zones)) ? 1 : 0)
          )
        }
      ]
    ]
  ])
}

# These Ubuntu nodes will be used for VPN pods, which need a particular
# WireGuard kernel module installed for that's not available in the
# default ContainerOS.
resource "google_container_node_pool" "vpn" {
  for_each = {
    for node_pool in local.node_pools :
    node_pool.zone_name => node_pool
    if node_pool.node_pool_name == "vpn" && node_pool.zone_node_count > 0
  }
  cluster  = var.kubernetes_cluster_id
  name     = "vpn-${each.value.zone_name}"
  network_config {
    enable_private_nodes = true
  }
  node_config {
    image_type = "ubuntu_containerd"
    labels = {
      wireguard = "true"
    }
    machine_type    = each.value.machine_type
    preemptible     = true
    service_account = var.kubernetes_nodes_service_account_email
  }
  node_count     = each.value.zone_node_count
  node_locations = [each.value.zone_name]
}

resource "kubernetes_namespace" "vpn" {
  metadata {
    name = "vpn"
  }
}

locals {
  installer_labels = {
    "app.kubernetes.io/component"  = "installer"
    "app.kubernetes.io/instance"   = "staging"
    "app.kubernetes.io/managed-by" = "Terraform"
    "app.kubernetes.io/name"       = "wireguard-kernel-module-installer"
    "app.kubernetes.io/part-of"    = "vpn"
    "app.kubernetes.io/version"    = "main"
  }
}

# Use a DaemonSet to install the WireGuard kernel module on the VPN nodes.
resource "kubernetes_daemonset" "wireguard_kernel_module_installer" {
  metadata {
    labels    = local.installer_labels
    name      = "wireguard-kernel-module-installer"
    namespace = kubernetes_namespace.vpn.metadata[0].name
  }
  spec {
    selector {
      match_labels = local.installer_labels
    }
    template {
      metadata {
        labels = local.installer_labels
      }
      spec {
        container {
          image = "registry.k8s.io/pause:3.9"
          name  = "pause"
          security_context {
            allow_privilege_escalation = false
            capabilities {
              drop = ["ALL"]
            }
            privileged                = false
            read_only_root_filesystem = true
            run_as_group              = 0
            run_as_non_root           = false
            run_as_user               = 0
          }
        }
        init_container {
          command = [
            "/bin/bash",
            "-eu",
            "-o",
            "pipefail",
            "-c",
            <<-BASH
              apt-get update -y
              # kmod includes modprobe
              apt-get install -y kmod wireguard
              # "Load" the kernel module.
              modprobe wireguard
            BASH
            ,
          ]
          # GKE uses the most recent LTS Ubuntu version for Ubuntu nodes.
          # We can use the same Ubuntu version for this container by specifying
          # "ubuntu:latest", because "The ubuntu:latest tag points to the
          # \"latest LTS\"", per https://hub.docker.com/_/ubuntu.
          # Note that there could stillbe issues if the nodes are running an
          # older LTS version than this container. The best way to avoid that
          # would be to have 2 DaemonSets, each with a different Ubuntu LTS
          # version, and to not install wireguard-tools unless the
          # version matches.
          image             = "docker.io/ubuntu:latest"
          image_pull_policy = "Always"
          name              = "wireguard-kernel-module-installer"
          security_context {
            privileged                = true
            read_only_root_filesystem = false
            run_as_group              = 0
            run_as_non_root           = false
            run_as_user               = 0
          }
          volume_mount {
            mount_path = "/lib/modules"
            name       = "host-lib-modules"
          }
          # Gemini says that these host paths need to be mounted to the init
          # container, too, but so far, the init container is working
          # without them.
          volume_mount {
            mount_path = "/usr/lib/modules"
            name       = "host-usr-lib-modules"
          }
          volume_mount {
            mount_path = "/lib/firmware"
            name       = "host-lib-firmware"
          }
          volume_mount {
            mount_path = "/etc/modules"
            name       = "host-etc-modules"
          }
        }
        node_selector = values(google_container_node_pool.vpn)[0].node_config[0].labels
        volume {
          host_path {
            path = "/lib/modules"
          }
          name = "host-lib-modules"
        }
        # Gemini says that these host paths need to be mounted to the init
        # container, too, but so far, the init container is working
        # without them.
        volume {
          host_path {
            path = "/usr/lib/modules"
          }
          name = "host-usr-lib-modules"
        }
        volume {
          host_path {
            path = "/lib/firmware"
          }
          name = "host-lib-firmware"
        }
        volume {
          host_path {
            path = "/etc/modules"
          }
          name = "host-etc-modules"
        }
      }
    }
  }
}

resource "wireguard_asymmetric_key" "keypair" {}

locals {
  # Example: private_subnet_prefix_length = 64
  private_subnet_prefix_length = tonumber(split("/", var.private_subnet_ipv6_cidr)[1])
  # Example: vpn_hosts_ipv6_cidr = 2600:2d00:423a:15c4:0:0:0:0/108
  vpn_hosts_ipv6_cidr = cidrsubnet(
    var.private_subnet_ipv6_cidr,
    var.vpn_clients_ipv6_prefix_length - local.private_subnet_prefix_length,
    0,
  )
  wireguard_server_port = 51820
}

resource "kubernetes_secret" "wireguard_config" {
  data = {
    "wg0.conf" = <<-EOF
      [Interface]
      # The IP address of the VPN server on the *private* VPN network, and the
      # prefix length of the VPN network.
      # Example: 2600:2d00:423a:15c4:0:0:0:1/108
      Address = ${cidrhost(local.vpn_hosts_ipv6_cidr, 1)}/${var.vpn_clients_ipv6_prefix_length}
      # The address(es) of the DNS server(s). For DNS-over-VPN, these must also
      # be in AllowedIPs on the client's side!
      # TODO: Replase these Cloudflare IP addresses with the address(es) of
      # internal DNS server(s).
      DNS = 2606:4700:4700::1001, 2606:4700:4700::1111
      # The port that the WireGuard server listens on for incoming connections.
      ListenPort = ${local.wireguard_server_port}
      # The WireGuard server's private key.
      PrivateKey = ${wireguard_asymmetric_key.keypair.private_key}

      [Peer]
      # The IP addresses assigned to this peer on the *private* VPN network.
      # AllowedIPs = 2600:2d00:423a:15c4:0:0:0:2/128
      AllowedIPs = ${cidrhost(local.vpn_hosts_ipv6_cidr, 2)}/128
      # The publicly reachable hostnames:ports or IP addresses:ports of the VPN server.
      # Endpoint = vpn.example.com:51820
      # Client 1's public key.
      PublicKey =  ${wireguard_asymmetric_key.keypair.public_key}
    EOF
  }
  metadata {
    name      = "wireguard-config"
    namespace = kubernetes_namespace.vpn.metadata[0].name
  }
}

# resource "google_service_account" "vpn" {
#   account_id   = "wireguard-server"
#   display_name = "WireGuard server pods"
# }

# resource "kubernetes_service_account" "vpn" {
#   metadata {
#     annotations = {
#       "iam.gke.io/gcp-service-account" = google_service_account.vpn.email
#     }
#     name      = "wireguard-server"
#     namespace = kubernetes_namespace.vpn.metadata[0].name
#   }
# }

locals {
  wireguard_deployment_labels = {
    "app.kubernetes.io/component"  = "server"
    "app.kubernetes.io/instance"   = "staging"
    "app.kubernetes.io/managed-by" = "terraform"
    "app.kubernetes.io/name"       = "wireguard-server"
    "app.kubernetes.io/version"    = var.wireguard_version
  }
  # The LinuxServer WireGuard container needs to start up as root, and then
  # switches to another user for the main runtime. Suboptimal!
  wireguard_users = {
    initialization = {
      gid = 0
      uid = 0
    }
    # Even if fs_group is set to 911, the volume is still owned by UID 0. After
    # the WireGuard container changes from 0:0 to 911:911, it attempts to chown
    # directories in the /config volume, which it does not have permission to
    # do as UID 911. Therefore, the only workable approach is to run the
    # WireGuard container as UID 0 at all times. Suboptimal!
    runtime = {
      gid = 911
      uid = 0
    }
  }
}

resource "kubernetes_deployment" "vpn" {
  metadata {
    labels    = local.wireguard_deployment_labels
    name      = "wireguard-server"
    namespace = kubernetes_namespace.vpn.metadata[0].name
  }
  spec {
    replicas = 3
    selector {
      match_labels = local.wireguard_deployment_labels
    }
    template {
      metadata {
        labels = local.wireguard_deployment_labels
      }
      spec {
        container {
          # Don't print each client's QR code on container startup.
          env {
            name  = "LOG_CONFS"
            value = "false"
          }
          # "If the environment variable PEERS is set to a number or a list of
          # strings separated by comma, the container will run in server mode
          # and the necessary server and peer/client confs will be generated."
          # Reference: https://hub.docker.com/r/linuxserver/wireguard#server-mode
          env {
            name  = "PEERS"
            value = "1"
          }
          # Warning: This user is only used after the container completes its
          # startup procedure, so the container still needs root access.
          env {
            name  = "PGID"
            value = local.wireguard_users.runtime.gid
          }
          env {
            name  = "PUID"
            value = local.wireguard_users.runtime.uid
          }
          env {
            name  = "SERVERPORT"
            value = local.wireguard_server_port
          }
          env {
            name  = "TZ"
            value = "Etc/UTC"
          }
          image = "docker.io/linuxserver/wireguard:1.0.20250521"
          name  = "wireguard-server"
          # Add readiness probe for load balancer health checks
          readiness_probe {
            exec {
              command = [
                "/bin/sh",
                "-c",
                "ip link show wg0",
              ]
            }
          }
          security_context {
            allow_privilege_escalation = true
            capabilities {
              add = [
                # Capability chown is required by this container, even though
                # it shouldn't be needed. Bad!
                "CHOWN",
                # Net Admin allows the container to create a network interface
                # on the host node.
                "NET_ADMIN",
              ]
              drop = ["ALL"]
            }
            # The WireGuard container needs to write to the root filesystem for runtime data. :(
            read_only_root_filesystem = false
            run_as_group              = local.wireguard_users.initialization.gid
            run_as_non_root           = false
            run_as_user               = local.wireguard_users.initialization.uid
          }
          volume_mount {
            mount_path = "/config"
            name       = "config"
            # The WireGuard container needs to write to /config for runtime data.
            # Since volumes created from Kubernetes secrets are always read-only,
            # even if the setting below is set to false, a separate initContainer
            # is needed to copy the secret into this writable volume *sigh*.
            read_only = false
          }
          volume_mount {
            mount_path = "/run"
            name       = "run"
            read_only  = false
          }
        }
        init_container {
          command = [
            "/bin/sh",
            "-eu",
            "-o",
            "pipefail",
            "-c",
            <<-BASH
              cp -R /run/secrets/wireguard-config/* /config/
            BASH
            ,
          ]
          image = "docker.io/busybox:1"
          name  = "copy-config"
          security_context {
            allow_privilege_escalation = false
            capabilities {
              drop = ["ALL"]
            }
            read_only_root_filesystem = true
            run_as_group              = local.wireguard_users.runtime.gid
            run_as_non_root           = false
            run_as_user               = local.wireguard_users.runtime.uid
          }
          volume_mount {
            mount_path = "/config"
            name       = "config"
            read_only  = false
          }
          volume_mount {
            mount_path = "/run/secrets/wireguard-config"
            name       = "secret-wireguard-config"
            read_only  = true
          }
        }
        node_selector = values(google_container_node_pool.vpn)[0].node_config[0].labels
        security_context {
          fs_group        = local.wireguard_users.runtime.gid
          run_as_group    = local.wireguard_users.runtime.gid
          run_as_non_root = false
          run_as_user     = local.wireguard_users.runtime.uid
        }
        topology_spread_constraint {
          label_selector {
            match_labels = local.wireguard_deployment_labels
          }
          max_skew           = 1
          min_domains        = 3
          node_taints_policy = "Honor"
          topology_key       = "topology.kubernetes.io/zone"
        }
        volume {
          empty_dir {
            medium = "Memory"
          }
          name = "config"
        }
        volume {
          empty_dir {
            medium = "Memory"
          }
          name = "run"
        }
        volume {
          name = "secret-wireguard-config"
          secret {
            secret_name = "wireguard-config"
          }
        }
      }
    }
  }
}

# resource "kubernetes_pod_disruption_budget" "vpn" {
#   metadata {
#     name      = "wireguard-server"
#     namespace = kubernetes_namespace.vpn.metadata[0].name
#   }
#   spec {
#     min_available = 1
#     selector {
#       match_labels = local.wireguard_deployment_labels
#     }
#   }
# }

# resource "kubernetes_service" "vpn" {
#   metadata {
#     name      = "wireguard-server"
#     namespace = kubernetes_namespace.vpn.metadata[0].name
#     annotations = {
#       "cloud.google.com/neg" = jsonencode({
#         ingress = true
#       })
#     }
#   }
#   spec {
#     ip_families = [
#       "IPv4",
#       "IPv6",
#     ]
#     ip_family_policy = "PreferDualStack"
#     port {
#       name        = "wireguard"
#       port        = local.wireguard_server_port
#       protocol    = "UDP"
#       target_port = local.wireguard_server_port
#     }
#     selector = local.wireguard_deployment_labels
#     type     = "ClusterIP"
#   }
# }

# data "google_netblock_ip_ranges" "health_checkers" {
#   range_type = "health-checkers"
# }

# data "google_netblock_ip_ranges" "legacy_health_checkers" {
#   range_type = "legacy-health-checkers"
# }

# locals {
#   source_ip_ranges = {
#     ipv4 = concat(
#       data.google_netblock_ip_ranges.health_checkers.cidr_blocks_ipv4 != null ? data.google_netblock_ip_ranges.health_checkers.cidr_blocks_ipv4 : [],
#       data.google_netblock_ip_ranges.legacy_health_checkers.cidr_blocks_ipv4 != null ? data.google_netblock_ip_ranges.legacy_health_checkers.cidr_blocks_ipv4 : [],
#       var.allowed_source_ranges_ipv4,
#     )
#     ipv6 = concat(
#       data.google_netblock_ip_ranges.health_checkers.cidr_blocks_ipv6 != null ? data.google_netblock_ip_ranges.health_checkers.cidr_blocks_ipv6 : [],
#       data.google_netblock_ip_ranges.legacy_health_checkers.cidr_blocks_ipv6 != null ? data.google_netblock_ip_ranges.legacy_health_checkers.cidr_blocks_ipv6 : [],
#       var.allowed_source_ranges_ipv6,
#     )
#   }
# }

# resource "kubernetes_network_policy" "vpn" {
#   metadata {
#     name      = "wireguard-server"
#     namespace = kubernetes_namespace.vpn.metadata[0].name
#   }
#   spec {
#     egress {}
#     ingress {
#       dynamic "from" {
#         for_each = concat(
#           local.source_ip_ranges.ipv4,
#           local.source_ip_ranges.ipv6,
#         )
#         content {
#           ip_block {
#             cidr = from.value
#           }
#         }
#       }
#       ports {
#         port     = local.wireguard_server_port
#         protocol = "UDP"
#       }
#     }
#     pod_selector {
#       match_labels = local.wireguard_deployment_labels
#     }
#     policy_types = [
#       "Egress",
#       "Ingress",
#     ]
#   }
# }

# # Health check for UDP service
# resource "google_compute_health_check" "vpn" {
#   # check_interval_sec  = 10
#   # healthy_threshold   = 2
#   name = "wireguard-server-health-check"
#   # For UDP services, we use TCP health check on a different port or HTTP health check
#   # Since WireGuard doesn't expose HTTP, we'll use a basic TCP check
#   tcp_health_check {
#     port = local.wireguard_server_port
#   }
#   # timeout_sec         = 5
#   # unhealthy_threshold = 3
# }

# data "google_compute_zones" "available" {}

# resource "google_compute_network_endpoint_group" "vpn" {
#   for_each     = toset(data.google_compute_zones.available.names)
#   default_port = local.wireguard_server_port
#   description  = "WireGuard server"
#   name         = "wireguard-server"
#   network      = var.vpc_id
#   subnetwork   = var.private_subnet_id
#   zone         = each.value
# }

# resource "google_compute_backend_service" "vpn" {
#   dynamic "backend" {
#     for_each = google_compute_network_endpoint_group.vpn
#     content {
#       # balancing_mode = "CONNECTION"
#       group = backend.value.id
#       # max_connections = 1000
#     }
#   }
#   health_checks         = [google_compute_health_check.vpn.id]
#   load_balancing_scheme = "EXTERNAL"
#   name                  = "wireguard-server"
#   port_name             = "wireguard"
#   protocol              = "UDP"
#   # timeout_sec           = 30
# }

# resource "google_compute_global_address" "vpn_ipv4" {
#   address_type = "EXTERNAL"
#   ip_version   = "IPV4"
#   name         = "wireguard-server-ipv4"
# }

# resource "google_compute_global_address" "vpn_ipv6" {
#   address_type = "EXTERNAL"
#   ip_version   = "IPV6"
#   name         = "wireguard-server-ipv6"
# }

# resource "google_compute_global_forwarding_rule" "vpn_ipv4" {
#   ip_address = google_compute_global_address.vpn_ipv4.address
#   ip_version = "IPV4"
#   name       = "wireguard-server-ipv4"
#   port_range = local.wireguard_server_port
#   target     = google_compute_backend_service.vpn.id
# }

# resource "google_compute_global_forwarding_rule" "vpn_ipv6" {
#   ip_address = google_compute_global_address.vpn_ipv6.address
#   ip_version = "IPV6"
#   name       = "wireguard-server-ipv6"
#   port_range = local.wireguard_server_port
#   target     = google_compute_backend_service.vpn.id
# }

# resource "google_compute_firewall" "vpn_allow_ipv4" {
#   allow {
#     protocol = "udp"
#     ports    = [local.wireguard_server_port]
#   }
#   name                    = "allow-wireguard-server-ipv4"
#   network                 = var.vpc_id
#   source_ranges           = local.source_ip_ranges.ipv4
#   target_service_accounts = [google_service_account.vpn.email]
# }

# resource "google_compute_firewall" "vpn_allow_ipv6" {
#   allow {
#     protocol = "udp"
#     ports    = [local.wireguard_server_port]
#   }
#   name                    = "allow-wireguard-server-ipv6"
#   network                 = var.vpc_id
#   source_ranges           = local.source_ip_ranges
#   target_service_accounts = [google_service_account.vpn.email]
# }
