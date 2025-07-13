locals {
  # 2 subnets, each with 2 secondary IP ranges, so 4 CIDR blocks needed.
  # Double to 8 for buffer.
  # Example CIDRs:
  # * 10.0.0.0/11
  # * 10.32.0.0/11
  # * 10.64.0.0/11
  # * ...
  max_subnets = 8
  subnet_mask = 8 + ceil(log(local.max_subnets, 2))
}

resource "google_compute_network" "main" {
  name                     = "main"
  auto_create_subnetworks  = false
  routing_mode             = "REGIONAL"
  enable_ula_internal_ipv6 = true
}

resource "random_id" "private_subnet_name" {
  byte_length = 4
  keepers = {
    vpc_id = google_compute_network.main.id
  }
  prefix = "${google_compute_network.main.name}-private-"
}

resource "random_id" "private_subnet_secondary_ip_range_names" {
  byte_length = 4
  keepers = {
    vpc_id = google_compute_network.main.id
  }
  prefix = "${random_id.private_subnet_name.hex}-"
}

resource "google_compute_subnetwork" "private" {
  ip_cidr_range    = "10.${(256 / local.max_subnets) * (0 + 0)}.0.0/${local.subnet_mask}"
  ipv6_access_type = "INTERNAL"
  name             = random_id.private_subnet_name.hex
  network          = google_compute_network.main.id
  region           = var.region
  secondary_ip_range {
    ip_cidr_range = "10.${(256 / local.max_subnets) * (0 + 1)}.0.0/${local.subnet_mask}"
    range_name    = random_id.private_subnet_secondary_ip_range_names.hex
  }
  stack_type = "IPV4_IPV6"
}

resource "random_id" "public_subnet_name" {
  byte_length = 4
  keepers = {
    vpc_id = google_compute_network.main.id
  }
  prefix = "${google_compute_network.main.name}-public-"
}

resource "random_id" "public_subnet_secondary_ip_range_names" {
  byte_length = 4
  keepers = {
    vpc_id = google_compute_network.main.id
  }
  prefix = "${random_id.public_subnet_name.hex}-"
}

resource "google_compute_subnetwork" "public" {
  ip_cidr_range    = "10.${(256 / local.max_subnets) * (2 + 0)}.0.0/${local.subnet_mask}"
  ipv6_access_type = "EXTERNAL"
  name             = random_id.public_subnet_name.hex
  network          = google_compute_network.main.id
  region           = var.region
  secondary_ip_range {
    ip_cidr_range = "10.${(256 / local.max_subnets) * (2 + 1)}.0.0/${local.subnet_mask}"
    range_name    = random_id.public_subnet_secondary_ip_range_names.hex
  }
  stack_type = "IPV4_IPV6"
}
