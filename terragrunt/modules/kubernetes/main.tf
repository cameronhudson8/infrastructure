resource "google_service_account" "nodes" {
  account_id   = "cluster-${var.kubernetes_cluster_name}-nodes"
  display_name = "For the nodes of cluster '${var.kubernetes_cluster_name}'"
}

resource "google_project_iam_member" "nodes" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
    "roles/storage.objectViewer",
  ])
  member  = "serviceAccount:${google_service_account.nodes.email}"
  project = var.gcp_project_id
  role    = each.value
}

data "google_compute_zones" "available" {}

resource "google_container_cluster" "main" {
  control_plane_endpoints_config {
    dns_endpoint_config {
      allow_external_traffic    = true
      enable_k8s_certs_via_dns  = true
      enable_k8s_tokens_via_dns = true
    }
    ip_endpoints_config {
      enabled = false
    }
  }
  datapath_provider   = "ADVANCED_DATAPATH"
  deletion_protection = false
  depends_on = [
    google_project_iam_member.nodes,
  ]
  enable_cilium_clusterwide_network_policy = true
  enable_l4_ilb_subsetting                 = true
  initial_node_count                       = 1
  ip_allocation_policy {
    cluster_secondary_range_name  = var.kubernetes_pods_subnet_secondary_range_name
    services_secondary_range_name = var.kubernetes_services_subnet_secondary_range_name
    stack_type                    = "IPV4_IPV6"
  }
  lifecycle {
    ignore_changes = [node_config]
  }
  location = var.kubernetes_cluster_location
  master_authorized_networks_config {
    cidr_blocks {
      display_name = "All IPv4 addresses"
      cidr_block   = "0.0.0.0/0"
    }
    gcp_public_cidrs_access_enabled = true
  }
  monitoring_config {
    advanced_datapath_observability_config {
      enable_metrics = false
      enable_relay   = true
    }
  }
  name            = var.kubernetes_cluster_name
  network         = var.vpc_name
  networking_mode = "VPC_NATIVE"
  node_config {
    service_account = google_service_account.nodes.email
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }
  private_cluster_config {
    enable_private_nodes   = true
    master_ipv4_cidr_block = var.kubernetes_control_plane_ipv4_cidr
  }
  resource_labels = {
    env = var.env_name
  }
  # Enabling this results in the absurd error "Error: googleapi: Error 400:
  # Setting stack_type IPV4_IPV6 is not supported when private ipv6 google
  # access is enabled."
  # private_ipv6_google_access = "PRIVATE_IPV6_GOOGLE_ACCESS_BIDIRECTIONAL"
  remove_default_node_pool = true
  subnetwork               = var.kubernetes_cluster_subnet_name
  workload_identity_config {
    workload_pool = "${var.gcp_project_id}.svc.id.goog"
  }
}

data "google_compute_machine_types" "available" {
  for_each = toset(data.google_compute_zones.available.names)
  zone     = each.value
}

locals {
  node_pools = flatten([
    for node_pool in [
      {
        machine_type     = var.node_pool_main_machine_type
        node_pool_name   = "main"
        total_node_count = var.node_pool_main_node_count
      },
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

resource "google_container_node_pool" "main" {
  for_each = {
    for node_pool in local.node_pools :
    node_pool.zone_name => node_pool
    if node_pool.node_pool_name == "main" && node_pool.zone_node_count > 0
  }
  cluster = google_container_cluster.main.id
  name    = "main-${each.value.zone_name}"
  network_config {
    enable_private_nodes = true
  }
  node_config {
    machine_type    = each.value.machine_type
    preemptible     = true
    service_account = google_service_account.nodes.email
  }
  node_count     = each.value.zone_node_count
  node_locations = [each.value.zone_name]
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
  cluster = google_container_cluster.main.id
  name    = "vpn-${each.value.zone_name}"
  network_config {
    enable_private_nodes = true
  }
  node_config {
    image_type      = "ubuntu_containerd"
    machine_type    = each.value.machine_type
    preemptible     = true
    service_account = google_service_account.nodes.email
  }
  node_count     = each.value.zone_node_count
  node_locations = [each.value.zone_name]
}
