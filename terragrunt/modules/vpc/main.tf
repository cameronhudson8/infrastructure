resource "google_compute_network" "main" {
  auto_create_subnetworks = false
  name                    = "main"
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "main" {
  ip_cidr_range = var.kubernetes_nodes_ipv4_cidr
  # Use external IPv6 addresses, not ULA IPv6 addresses. The external IPv6
  # addresses will not be publicly routable unless a firewall rule is created
  # to allow ingress. Using external IPv6 addresses eliminates the need for
  # NAT66 for egress, which would otherwise be required to translate internal
  # IPv6 addresses to public IPv6 addresses.
  ipv6_access_type           = "EXTERNAL"
  name                       = "main"
  network                    = google_compute_network.main.id
  private_ip_google_access   = true
  private_ipv6_google_access = "ENABLE_OUTBOUND_VM_ACCESS_TO_GOOGLE"
  region                     = var.gcp_region
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
