locals {
  cluster_name = "main"
}

resource "google_service_account" "nodes" {
  account_id   = "cluster-${local.cluster_name}-nodes"
  display_name = "For the nodes of cluster '${local.cluster_name}'"
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
  datapath_provider   = "ADVANCED_DATAPATH"
  deletion_protection = false
  depends_on = [
    google_project_iam_member.nodes,
  ]
  enable_l4_ilb_subsetting = true
  lifecycle {
    ignore_changes = [node_config]
  }
  node_config {
    service_account = google_service_account.nodes.email
  }
  initial_node_count = 1
  ip_allocation_policy {
    cluster_secondary_range_name  = var.kubernetes_pods_subnet_secondary_range_name
    services_secondary_range_name = var.kubernetes_services_subnet_secondary_range_name
    stack_type                    = "IPV4_IPV6"
  }
  location = sort(data.google_compute_zones.available.names)[0]
  master_authorized_networks_config {
    cidr_blocks {
      display_name = "All IPv4 addresses"
      cidr_block   = "0.0.0.0/0"
    }
    gcp_public_cidrs_access_enabled = true
  }
  name            = local.cluster_name
  network         = var.vpc_name
  networking_mode = "VPC_NATIVE"
  private_cluster_config {
    enable_private_nodes   = true
    master_ipv4_cidr_block = var.kubernetes_control_plane_ipv4_cidr
  }
  remove_default_node_pool = true
  subnetwork               = var.kubernetes_cluster_subnet_name
}

# Determine which zones have the desired machine type available.
data "google_compute_machine_types" "available_machine_types" {
  for_each = toset(data.google_compute_zones.available.names)
  filter   = "name = \"${var.on_demand_node_machine_type}\""
  zone     = each.value
}

locals {
  zones_with_on_demand_machine_type_available = sort([
    for zone, available_machine_types in data.google_compute_machine_types.available_machine_types :
    zone if contains(
      [for machine_types in available_machine_types.machine_types : machine_types.name],
      var.on_demand_node_machine_type,
    )
  ])

  node_distribution = [
    for i, zone_name in local.zones_with_on_demand_machine_type_available :
    {
      node_count = (
        floor(var.on_demand_node_count / length(local.zones_with_on_demand_machine_type_available))
        + (i < (var.on_demand_node_count % length(local.zones_with_on_demand_machine_type_available)) ? 1 : 0)
      )
      zone_name = zone_name
    }
  ]
}

resource "google_container_node_pool" "on_demand_nodes" {
  for_each = {
    for zone in local.node_distribution :
    zone.zone_name => zone
    if zone.node_count > 0
  }
  cluster = google_container_cluster.main.id
  name    = "on-demand-${each.value.zone_name}"
  network_config {
    enable_private_nodes = true
  }
  node_config {
    # Non-preemptible nodes receive the label "goog-gke-node-pool-provisioning-model: on-demand"
    # labels          = {}
    machine_type    = var.on_demand_node_machine_type
    service_account = google_service_account.nodes.email
  }
  node_count     = each.value.node_count
  node_locations = [each.value.zone_name]
  management {
    auto_repair  = true
    auto_upgrade = true
  }
}
