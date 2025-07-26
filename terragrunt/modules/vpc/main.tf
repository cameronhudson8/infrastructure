resource "google_compute_network" "main" {
  auto_create_subnetworks  = false
  enable_ula_internal_ipv6 = true
  name                     = "main"
  routing_mode             = "REGIONAL"
}

resource "google_compute_subnetwork" "kubernetes_cluster" {
  ip_cidr_range            = var.kubernetes_nodes_ipv4_cidr
  ipv6_access_type         = "INTERNAL"
  name                     = "kubernetes-cluster"
  network                  = google_compute_network.main.id
  private_ip_google_access = true
  # private_ipv6_google_access = "ENABLE_OUTBOUND_VM_ACCESS_TO_GOOGLE"
  # private_ipv6_google_access = "ENABLE_BIDIRECTIONAL_ACCESS_TO_GOOGLE"
  # private_ipv6_google_access = "DISABLE_GOOGLE_ACCESS"
  region = var.gcp_region
  secondary_ip_range {
    ip_cidr_range = var.kubernetes_pods_ipv4_cidr
    range_name    = "kubernetes-pods"
  }
  secondary_ip_range {
    ip_cidr_range = var.kubernetes_services_ipv4_cidr
    range_name    = "kubernetes-services"
  }
  stack_type = "IPV4_IPV6"
}

resource "google_compute_subnetwork" "public" {
  ip_cidr_range    = var.public_subnet_ipv4_cidr
  ipv6_access_type = "EXTERNAL"
  name             = "public"
  network          = google_compute_network.main.id
  region           = var.gcp_region
  stack_type       = "IPV4_IPV6"
}
