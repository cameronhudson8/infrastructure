locals {
  public_subnet_count  = 3
  private_subnet_count = 3
  max_subnets          = 32
  subnet_mask          = 8 + ceil(log(local.max_subnets, 2))
}

data "google_compute_zones" "available" {
  region = var.region
}

resource "google_compute_network" "vpc" {
  name                     = "main"
  auto_create_subnetworks  = false
  routing_mode             = "REGIONAL"
  enable_ula_internal_ipv6 = true
}

resource "google_compute_subnetwork" "public_subnets" {
  count = min(local.public_subnet_count, length(data.google_compute_zones.available.names))

  name          = "${google_compute_network.vpc.name}-public-${count.index + 1}"
  ip_cidr_range = "10.${count.index * 2}.0.0/${local.subnet_mask}"
  region        = var.region
  network       = google_compute_network.vpc.id

  stack_type       = "IPV4_IPV6"
  ipv6_access_type = "EXTERNAL"

  secondary_ip_range {
    range_name    = "${google_compute_network.vpc.name}-public-${count.index + 1}-secondary"
    ip_cidr_range = "10.${count.index * 2 + 1}.0.0/${local.subnet_mask}"
  }
}

resource "google_compute_subnetwork" "private_subnets" {
  count = min(local.private_subnet_count, length(data.google_compute_zones.available.names))

  name          = "${google_compute_network.vpc.name}-private-${count.index + 1}"
  ip_cidr_range = "10.${count.index * 2 + local.public_subnet_count * 2}.0.0/${local.subnet_mask}"
  region        = var.region
  network       = google_compute_network.vpc.id

  stack_type       = "IPV4_IPV6"
  ipv6_access_type = "INTERNAL"

  secondary_ip_range {
    range_name    = "${google_compute_network.vpc.name}-private-${count.index + 1}-secondary"
    ip_cidr_range = "10.${count.index * 2 + local.public_subnet_count * 2 + 1}.0.0/${local.subnet_mask}"
  }
}
