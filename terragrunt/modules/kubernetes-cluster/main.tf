locals {
  cluster_name = "main"
}

data "google_compute_subnetwork" "kubernetes_cluster_subnet" {
  name = var.kubernetes_cluster_subnet_name
}

resource "google_compute_firewall" "allow_control_plane_to_nodes_ipv4" {
  allow {
    ports    = ["1-65535"]
    protocol = "tcp"
  }
  description = "Allow control plane to communicate with nodes"
  destination_ranges = concat(
    [
      data.google_compute_subnetwork.kubernetes_cluster_subnet.ip_cidr_range,
      # A combination of IPv4 and IPv6 CIDR ranges is not supported in the
      # source_ranges field. I considered adding a separate firewall rule for
      # IPv6, but there is no IPv6 CIDR for the kubernetes control plane.
      # data.google_compute_subnetwork.kubernetes_cluster_subnet.internal_ipv6_prefix,
    ],
    [
      for secondary_ip_range in data.google_compute_subnetwork.kubernetes_cluster_subnet.secondary_ip_range :
      secondary_ip_range.ip_cidr_range
    ],
  )
  direction     = "INGRESS"
  name          = "allow-control-plane-to-nodes"
  network       = var.vpc_name
  source_ranges = [var.kubernetes_control_plane_ipv4_cidr]
}

resource "google_service_account" "node_service_account" {
  account_id   = "cluster-${local.cluster_name}-nodes"
  display_name = "For the nodes of cluster '${local.cluster_name}'"
}

resource "google_project_iam_member" "node_service_account_roles" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
    "roles/storage.objectViewer"
  ])
  member  = "serviceAccount:${google_service_account.node_service_account.email}"
  project = var.gcp_project_id
  role    = each.value
}

resource "google_container_cluster" "main" {
  datapath_provider   = "ADVANCED_DATAPATH"
  deletion_protection = false
  depends_on = [google_compute_firewall.allow_control_plane_to_nodes_ipv4]
  node_config {
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    service_account = google_service_account.node_service_account.email
  }
  initial_node_count = 1
  ip_allocation_policy {
    cluster_secondary_range_name  = var.kubernetes_pods_subnet_secondary_range_name
    services_secondary_range_name = var.kubernetes_services_subnet_secondary_range_name
    stack_type                    = "IPV4_IPV6"
  }
  location = var.gcp_region
  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }
  name    = local.cluster_name
  network = var.vpc_name
  private_cluster_config {
    enable_private_endpoint = false
    enable_private_nodes    = true
    master_ipv4_cidr_block  = var.kubernetes_control_plane_ipv4_cidr
  }
  remove_default_node_pool = true
  subnetwork               = var.kubernetes_cluster_subnet_name
  workload_identity_config {
    workload_pool = "${var.gcp_project_id}.svc.id.goog"
  }
}

resource "google_container_node_pool" "on_demand_nodes" {
  cluster  = google_container_cluster.main.name
  location = var.gcp_region
  name     = "on-demand"
  node_config {
    # disk_size_gb = var.on_demand_node_disk_size_gb
    # disk_type    = var.on_demand_node_disk_size_gb
    labels          = { "node-role.kubernetes.io/on-demand" = "true" }
    machine_type    = var.on_demand_node_machine_type
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    preemptible     = false
    service_account = google_service_account.node_service_account.email
  }
  node_count = 3
  management {
    auto_repair  = true
    auto_upgrade = true
  }
}
