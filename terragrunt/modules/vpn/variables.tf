# variable "allowed_source_ranges_ipv4" {
#   description = "List of IPv4 CIDR blocks allowed to access the VPN"
#   type        = list(string)
#   default     = ["0.0.0.0/0"]
# }

# variable "allowed_source_ranges_ipv6" {
#   description = "List of IPv6 CIDR blocks allowed to access the VPN"
#   type        = list(string)
#   default     = ["::/0"]
# }

variable "kubernetes_cluster_id" {
  description = "The ID of the Kubernetes cluster"
  type        = string
}

variable "kubernetes_nodes_service_account_email" {
  description = "The email address of the GCP service account of the Kubernetes nodes"
  type        = string
}

variable "node_pool_vpn_node_count" {
  description = "The number of nodes in the VPN node pool (which runs only the VPN pods)"
  type        = number
}

variable "node_pool_vpn_machine_type" {
  description = "The machine type of the nodes in the VPN node pool (which runs only the VPN pods)"
  type        = string
}

# variable "private_subnet_id" {
#   description = "The ID of the private subnet"
#   type        = string
# }

variable "private_subnet_ipv6_cidr" {
  description = "The IPv6 CIDR of the private subnet (example: 2600:2d00:423a:15c4:0:0:0:0/64)"
  type        = string
}

variable "vpn_clients_ipv6_prefix_length" {
  description = "The IPv6 prefix length to use for the VPN clients (example: 108, as in /108)"
  type        = number
}

# variable "vpc_id" {
#   description = "The ID of the VPC"
#   type        = string
# }

variable "wireguard_version" {
  description = "The version of the WireGuard container image to use"
  type        = string
}
