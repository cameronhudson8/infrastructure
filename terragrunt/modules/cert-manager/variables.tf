variable "cert_manager_version" {
  description = "The version of cert-manager to install"
  type        = string
}

variable "kubernetes_control_plane_cidr_ipv4" {
  description = "The IPv4 CIDR of the Kubernetes control plane"
  type        = string
}

variable "dns_zones" {
  description = "The DNS zones to manage with cert-manager"
  type        = list(string)
}
