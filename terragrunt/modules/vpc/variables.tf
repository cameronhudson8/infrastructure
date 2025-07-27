variable "gcp_region" {
  description = "The GCP region to use."
  type        = string
}

variable "kubernetes_control_plane_ipv4_cidr" {
  description = "The CIDR to use for the Kubernetes control plane."
  type        = string
}

variable "kubernetes_nodes_ipv4_cidr" {
  description = "The IPv4 CIDR to use for the Kubernetes Nodes."
  type        = string
}

variable "kubernetes_pods_ipv4_cidr" {
  description = "The CIDR to use for Kubernetes Pods."
  type        = string
}

variable "kubernetes_services_ipv4_cidr" {
  description = "The CIDR to use for Kubernetes Services."
  type        = string
}
