resource "kubernetes_namespace" "vpn" {
  metadata {
    name = "vpn"
  }
}

data "external" "wireguard_server_keys" {
  program = [
    "/usr/bin/env",
    "bash",
    "-eu",
    "-o",
    "pipefail",
    "-c",
    <<-BASH
        tempdir=$(mktemp -d)
        trap 'rm -rf $${tempdir}' EXIT
        openssl genpkey \
            -algorithm X25519 \
            -out "$${tempdir}/private-key-with-header-and-footer.pem" \
            -outform PEM \
            -outpubkey "$${tempdir}/public-key-with-header-and-footer.pem"
        private_key=$(grep -v '^-' "$${tempdir}/private-key-with-header-and-footer.pem" | tr -d '\n')
        public_key=$(grep -v '^-' "$${tempdir}/public-key-with-header-and-footer.pem" | tr -d '\n')
        jq \
            --arg private_key "$${private_key}" \
            --arg public_key "$${public_key}" \
            --null-input \
            -cM \
            "$(
                cat <<-JSON
        			{
        			    "private_key": \$private_key,
        			    "public_key": \$public_key
        			}
        		JSON
            )"
    BASH
  ]
}

# TODO: Devise a way for clients to be dynamically created, updated, and deleted.
data "external" "wireguard_keys" {
  program = [
    "/usr/bin/env",
    "bash",
    "-eu",
    "-o",
    "pipefail",
    "-c",
    <<-BASH
        tempdir=$(mktemp -d)
        trap 'rm -rf $${tempdir}' EXIT
        openssl genpkey \
            -algorithm X25519 \
            -out "$${tempdir}/private-key-with-header-and-footer.pem" \
            -outform PEM \
            -outpubkey "$${tempdir}/public-key-with-header-and-footer.pem"
        private_key=$(grep -v '^-' "$${tempdir}/private-key-with-header-and-footer.pem" | tr -d '\n')
        public_key=$(grep -v '^-' "$${tempdir}/public-key-with-header-and-footer.pem" | tr -d '\n')
        jq \
            --arg private_key "$${private_key}" \
            --arg public_key "$${public_key}" \
            --null-input \
            -cM \
            "$(
                cat <<-JSON
        			{
        			    "private_key": \$private_key,
        			    "public_key": \$public_key
        			}
        		JSON
            )"
    BASH
  ]
}

locals {
  private_subnet_prefix_length = tonumber(split("/", var.private_subnet_ipv6_cidr)[1])
  vpn_clients_ipv6_cidr = cidrsubnet(
    var.private_subnet_ipv6_cidr,
    var.vpn_clients_ipv6_prefix_length - local.private_subnet_prefix_length,
    0,
  )
  wireguard_deployment_labels = {
    "app.kubernetes.io/component"  = "server"
    "app.kubernetes.io/instance"   = "staging"
    "app.kubernetes.io/managed-by" = "terraform"
    "app.kubernetes.io/name"       = "wireguard-server"
    "app.kubernetes.io/version"    = var.wireguard_version
  }
  wireguard_server_port = 51820
  wireguard_user = {
    uid = 911
    gid = 1001
  }
}

resource "kubernetes_secret" "wireguard_config" {
  data = {
    "wg0.conf" = <<-EOF
      [Interface]
      PrivateKey = ${data.external.wireguard_server_keys.result.private_key}
      ListenPort = ${local.wireguard_server_port}

      [Peer]
      PublicKey =  ${data.external.wireguard_server_keys.result.public_key}
      AllowedIPs = ${local.vpn_clients_ipv6_cidr}
    EOF
  }
  metadata {
    name      = "wireguard-config"
    namespace = kubernetes_namespace.vpn.metadata[0].name
  }
}

resource "google_service_account" "vpn" {
  account_id   = "wireguard-server"
  display_name = "WireGuard server pods"
}

resource "kubernetes_service_account" "vpn" {
  metadata {
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.vpn.email
    }
    name      = "wireguard-server"
    namespace = kubernetes_namespace.vpn.metadata[0].name
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
          env {
            name  = "PEERS"
            value = 1
          }
          #   # This doesn't work. Instead, use the default of 1001.
          #   env {
          #     name  = "PGID"
          #     value = local.wireguard_user.gid
          #   }
          #   # This doesn't work. Instead, use the default of 911.
          #   env {
          #     name  = "PUID"
          #     value = local.wireguard_user.uid
          #   }
          env {
            name  = "SERVERPORT"
            value = local.wireguard_server_port
          }
          env {
            name  = "TZ"
            value = "Etc/UTC"
          }
          # Enable IPv6 in WireGuard
          env {
            name  = "INTERNAL_SUBNET"
            value = local.vpn_clients_ipv6_cidr
          }
          image = "registry-1.docker.io/linuxserver/wireguard:1.0.20250521"
          name  = "wireguard-server"
          # Add readiness probe for load balancer health checks
          readiness_probe {
            exec {
              command = [
                "/bin/sh",
                "-c",
                "test -f /config/wg0.conf",
              ]
            }
            initial_delay_seconds = 10
            period_seconds        = 10
          }
          security_context {
            allow_privilege_escalation = false
            capabilities {
              add  = ["NET_ADMIN"]
              drop = ["ALL"]
            }
            # The WireGuard container needs to write to the root filesystem for runtime data. :(
            read_only_root_filesystem = false
            run_as_group              = local.wireguard_user.gid
            run_as_non_root           = true
            run_as_user               = local.wireguard_user.uid
          }
          volume_mount {
            mount_path = "/config/wg_confs"
            name       = "wireguard-config"
            read_only  = true
          }
          volume_mount {
            mount_path = "/run"
            name       = "run"
            # The WireGuard container needs to write to /run for runtime data. :(
            read_only = false
          }
        }
        security_context {
          fs_group        = local.wireguard_user.gid
          run_as_group    = local.wireguard_user.gid
          run_as_non_root = true
          run_as_user     = local.wireguard_user.uid
        }
        service_account_name = kubernetes_service_account.vpn.metadata[0].name
        volume {
          name = "wireguard-config"
          secret {
            secret_name = "wireguard-config"
          }
        }
        volume {
          empty_dir {
            medium = "Memory"
          }
          name = "run"
        }
      }
    }
  }
}

resource "kubernetes_pod_disruption_budget" "vpn" {
  metadata {
    name      = "wireguard-server"
    namespace = kubernetes_namespace.vpn.metadata[0].name
  }
  spec {
    min_available = 1
    selector {
      match_labels = local.wireguard_deployment_labels
    }
  }
}

resource "kubernetes_service" "vpn" {
  metadata {
    name      = "wireguard-server"
    namespace = kubernetes_namespace.vpn.metadata[0].name
    annotations = {
      "cloud.google.com/neg" = jsonencode({
        ingress = true
      })
    }
  }
  spec {
    ip_families = [
      "IPv4",
      "IPv6",
    ]
    ip_family_policy = "PreferDualStack"
    port {
      name        = "wireguard"
      port        = local.wireguard_server_port
      protocol    = "UDP"
      target_port = local.wireguard_server_port
    }
    selector = local.wireguard_deployment_labels
    type     = "ClusterIP"
  }
}

data "google_netblock_ip_ranges" "health_checkers" {
  range_type = "health-checkers"
}

data "google_netblock_ip_ranges" "legacy_health_checkers" {
  range_type = "legacy-health-checkers"
}

locals {
  source_ip_ranges = {
    ipv4 = concat(
      data.google_netblock_ip_ranges.health_checkers.cidr_blocks_ipv4 != null ? data.google_netblock_ip_ranges.health_checkers.cidr_blocks_ipv4 : [],
      data.google_netblock_ip_ranges.legacy_health_checkers.cidr_blocks_ipv4 != null ? data.google_netblock_ip_ranges.legacy_health_checkers.cidr_blocks_ipv4 : [],
      var.allowed_source_ranges_ipv4,
    )
    ipv6 = concat(
      data.google_netblock_ip_ranges.health_checkers.cidr_blocks_ipv6 != null ? data.google_netblock_ip_ranges.health_checkers.cidr_blocks_ipv6 : [],
      data.google_netblock_ip_ranges.legacy_health_checkers.cidr_blocks_ipv6 != null ? data.google_netblock_ip_ranges.legacy_health_checkers.cidr_blocks_ipv6 : [],
      var.allowed_source_ranges_ipv6,
    )
  }
}

resource "kubernetes_network_policy" "vpn" {
  metadata {
    name      = "wireguard-server"
    namespace = kubernetes_namespace.vpn.metadata[0].name
  }
  spec {
    egress {}
    ingress {
      dynamic "from" {
        for_each = concat(
          local.source_ip_ranges.ipv4,
          local.source_ip_ranges.ipv6,
        )
        content {
          ip_block {
            cidr = from.value
          }
        }
      }
      ports {
        port     = local.wireguard_server_port
        protocol = "UDP"
      }
    }
    pod_selector {
      match_labels = local.wireguard_deployment_labels
    }
    policy_types = [
      "Egress",
      "Ingress",
    ]
  }
}

# Health check for UDP service
resource "google_compute_health_check" "vpn" {
  # check_interval_sec  = 10
  # healthy_threshold   = 2
  name = "wireguard-server-health-check"
  # For UDP services, we use TCP health check on a different port or HTTP health check
  # Since WireGuard doesn't expose HTTP, we'll use a basic TCP check
  tcp_health_check {
    port = local.wireguard_server_port
  }
  # timeout_sec         = 5
  # unhealthy_threshold = 3
}

data "google_compute_zones" "available" {}

resource "google_compute_network_endpoint_group" "vpn" {
  for_each     = toset(data.google_compute_zones.available.names)
  default_port = local.wireguard_server_port
  description  = "WireGuard server"
  name         = "wireguard-server"
  network      = var.vpc_id
  subnetwork   = var.private_subnet_id
  zone         = each.value
}

resource "google_compute_backend_service" "vpn" {
  dynamic "backend" {
    for_each = google_compute_network_endpoint_group.vpn
    content {
      # balancing_mode = "CONNECTION"
      group = backend.value.id
      # max_connections = 1000
    }
  }
  health_checks         = [google_compute_health_check.vpn.id]
  load_balancing_scheme = "EXTERNAL"
  name                  = "wireguard-server"
  port_name             = "wireguard"
  protocol              = "UDP"
  # timeout_sec           = 30
}

# resource "google_compute_global_address" "vpn_ipv4" {
#   address_type = "EXTERNAL"
#   ip_version   = "IPV4"
#   name         = "wireguard-server-ipv4"
# }

resource "google_compute_global_address" "vpn_ipv6" {
  address_type = "EXTERNAL"
  ip_version   = "IPV6"
  name         = "wireguard-server-ipv6"
}

# resource "google_compute_global_forwarding_rule" "vpn_ipv4" {
#   ip_address = google_compute_global_address.vpn_ipv4.address
#   ip_version = "IPV4"
#   name       = "wireguard-server-ipv4"
#   port_range = local.wireguard_server_port
#   target     = google_compute_backend_service.vpn.id
# }

resource "google_compute_global_forwarding_rule" "vpn_ipv6" {
  ip_address = google_compute_global_address.vpn_ipv6.address
  ip_version = "IPV6"
  name       = "wireguard-server-ipv6"
  port_range = local.wireguard_server_port
  target     = google_compute_backend_service.vpn.id
}

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
