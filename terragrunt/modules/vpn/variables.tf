variable "allowed_source_ranges_ipv4" {
  description = "List of IPv4 CIDR blocks allowed to access the VPN"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "allowed_source_ranges_ipv6" {
  description = "List of IPv6 CIDR blocks allowed to access the VPN"
  type        = list(string)
  default     = ["::/0"]
}

variable "vpc_id" {
  description = "The ID of the VPC"
  type        = string
}

variable "private_subnet_ipv6_cidr" {
  description = "The IPv6 CIDR of the private subnet"
  type        = string
}

variable "private_subnet_id" {
  description = "The ID of the private subnet"
  type        = string
}

variable "vpn_clients_ipv6_prefix_length" {
  description = "The IPv6 prefix length to use for the VPN clients"
  type        = number
}

variable "wireguard_version" {
  description = "The version of the WireGuard container image to use"
  type        = string
}
