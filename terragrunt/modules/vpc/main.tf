resource "google_compute_network" "main" {
  auto_create_subnetworks = false
  name                    = "main"
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "private" {
  ip_cidr_range = var.kubernetes_nodes_ipv4_cidr
  # Use external IPv6 addresses, not ULA IPv6 addresses. The external IPv6
  # addresses will not be publicly routable unless a firewall rule is created
  # to allow ingress. Using external IPv6 addresses eliminates the need for
  # NAT66 for egress, which would otherwise be required to translate internal
  # IPv6 addresses to public IPv6 addresses.
  ipv6_access_type           = "EXTERNAL"
  name                       = "private"
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

resource "google_compute_subnetwork" "public" {
  ip_cidr_range              = var.load_balancers_ipv4_cidr
  ipv6_access_type           = "EXTERNAL"
  name                       = "public"
  network                    = google_compute_network.main.id
  private_ip_google_access   = true
  private_ipv6_google_access = "ENABLE_OUTBOUND_VM_ACCESS_TO_GOOGLE"
  region                     = var.gcp_region
  stack_type                 = "IPV4_IPV6"
}

data "external" "internet_ipv4_cidrs" {
  program = [
    "/usr/bin/env",
    "python",
    "${path.module}/setsubtract_cidrs.py",
  ]
  query = {
    ipVersion = "IPV4"
    cidrSetA = jsonencode([
      "0.0.0.0/0",
    ])
    cidrSetB = jsonencode([
      # Private CIDRs
      "10.0.0.0/8",
      "172.16.0.0/12",
      "192.168.0.0/16",
    ])
  }
}

resource "google_compute_firewall" "private_ipv4" {
  deny {
    protocol = "all"
  }
  description        = "Deny all IPv4 ingress from the internet"
  destination_ranges = [google_compute_subnetwork.private.ip_cidr_range]
  direction          = "INGRESS"
  name               = "deny-ipv4-ingress-from-internet-to-private-subnet"
  network            = google_compute_network.main.name
  priority           = 0
  source_ranges      = jsondecode(data.external.internet_ipv4_cidrs.result.cidrs_json)
}

data "external" "internet_ipv6_cidrs" {
  program = [
    "/usr/bin/env",
    "python",
    "${path.module}/setsubtract_cidrs.py",
  ]
  query = {
    ipVersion = "IPV6"
    cidrSetA = jsonencode([
      "::/0",
    ])
    cidrSetB = jsonencode([
      # Addresses in our subnets
      google_compute_subnetwork.private.ipv6_cidr_range,
      google_compute_subnetwork.public.ipv6_cidr_range,
    ])
  }
}

resource "google_compute_firewall" "private_ipv6" {
  deny {
    protocol = "all"
  }
  description        = "Deny all IPv6 ingress from the internet"
  destination_ranges = [google_compute_subnetwork.private.ipv6_cidr_range]
  direction          = "INGRESS"
  name               = "deny-ipv6-ingress-from-internet-to-private-subnet"
  network            = google_compute_network.main.name
  priority           = 0
  source_ranges      = jsondecode(data.external.internet_ipv6_cidrs.result.cidrs_json)
}

resource "google_compute_router" "main" {
  name    = "main"
  network = google_compute_network.main.id
  region  = var.gcp_region
}

# This is for IPv4 egress only. The IPv6 addresses in the VPC are not private,
# so no NAT is needed for egress.
resource "google_compute_router_nat" "main" {
  name                               = "main"
  nat_ip_allocate_option             = "AUTO_ONLY"
  router                             = google_compute_router.main.name
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}
