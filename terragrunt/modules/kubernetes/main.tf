data "google_client_config" "current" {}

resource "google_cloud_quotas_quota_preference" "ssd_total_gb" {
  contact_email = var.gcp_project_owner_email
  dimensions    = { region = data.google_client_config.current.region }
  parent        = "projects/${var.gcp_project_id}"
  quota_config {
    preferred_value = 1000
  }
  quota_id = "SSD-TOTAL-GB-per-project-region"
  service  = "compute.googleapis.com"
}

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

# trivy:ignore:GCP-0050
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
    google_cloud_quotas_quota_preference.ssd_total_gb,
    google_project_iam_member.nodes,
  ]
  enable_cilium_clusterwide_network_policy = true
  enable_fqdn_network_policy               = true
  enable_l4_ilb_subsetting                 = true
  ip_allocation_policy {
    cluster_secondary_range_name  = var.kubernetes_pods_subnet_secondary_range_name
    services_secondary_range_name = var.kubernetes_services_subnet_secondary_range_name
    stack_type                    = "IPV4_IPV6"
  }
  location = var.kubernetes_cluster_location
  monitoring_config {
    advanced_datapath_observability_config {
      enable_metrics = false
      enable_relay   = true
    }
  }
  name            = var.kubernetes_cluster_name
  network         = var.vpc_name
  networking_mode = "VPC_NATIVE"
  private_cluster_config {
    # This property is incorrectly named; if true, it *disables* the public
    # endpoint. If false, then both the public and private endpoints are
    # enabled.
    enable_private_endpoint = false
    enable_private_nodes    = true
    master_ipv4_cidr_block  = var.kubernetes_control_plane_ipv4_cidr
  }
  resource_labels = {
    env = var.env_name
  }
  # Enabling this results in the absurd error "Error: googleapi: Error 400:
  # Setting stack_type IPV4_IPV6 is not supported when private ipv6 google
  # access is enabled."
  # private_ipv6_google_access = "PRIVATE_IPV6_GOOGLE_ACCESS_BIDIRECTIONAL"
  subnetwork = var.kubernetes_cluster_subnet_name
  workload_identity_config {
    workload_pool = "${var.gcp_project_id}.svc.id.goog"
  }
}

data "google_compute_machine_types" "available" {
  for_each = toset(data.google_compute_zones.available.names)
  filter   = "name = \"${var.node_machine_type}\""
  zone     = each.value
}

locals {
  zones_with_node_machine_type_available = sort([
    for zone, available_machine_types in data.google_compute_machine_types.available :
    zone if contains(
      [for machine_types in available_machine_types.machine_types : machine_types.name],
      var.node_machine_type,
    )
  ])

  node_distribution = [
    for i, zone_name in local.zones_with_node_machine_type_available :
    {
      node_count = (
        floor(var.node_count / length(local.zones_with_node_machine_type_available))
        + (i < (var.node_count % length(local.zones_with_node_machine_type_available)) ? 1 : 0)
      )
      zone_name = zone_name
    }
  ]
}

resource "random_id" "node_pool_name_suffix" {
  for_each = {
    for zone in local.node_distribution :
    zone.zone_name => zone
    if zone.node_count > 0
  }
  byte_length = 4
}

resource "google_container_node_pool" "main" {
  for_each = {
    for zone in local.node_distribution :
    zone.zone_name => zone
    if zone.node_count > 0
  }
  cluster = google_container_cluster.main.id
  # Spot provisioning can only be enabled when creating a node pool. Use a new
  # name so Terraform can create the Spot pool before draining the preemptible pool.
  name = "main-${each.value.zone_name}-${random_id.node_pool_name_suffix[each.key].hex}"
  lifecycle {
    create_before_destroy = true
  }
  network_config {
    enable_private_nodes = true
  }
  node_config {
    machine_type = var.node_machine_type
    metadata = {
      "disable-legacy-endpoints" = true
    }
    service_account = google_service_account.nodes.email
    spot            = true
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }
  node_count     = each.value.node_count
  node_locations = [each.value.zone_name]
  management {
    auto_repair  = true
    auto_upgrade = true
  }
}
