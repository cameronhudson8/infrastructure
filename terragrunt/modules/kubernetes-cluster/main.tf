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
    # stack_type                    = "IPV4_IPV6"
  }
  location = sort(data.google_compute_zones.available.names)[0]
  master_authorized_networks_config {}
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
    pod_range            = var.kubernetes_pods_subnet_secondary_range_name
  }
  node_config {
    labels          = { preemptible = "false" }
    machine_type    = var.on_demand_node_machine_type
    service_account = google_service_account.nodes.email
  }
  node_count     = 1
  node_locations = slice(sort(data.google_compute_zones.available.names), 0, 3)
  management {
    auto_repair  = true
    auto_upgrade = true
  }
}
