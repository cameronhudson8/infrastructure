variable "gcp_project_id" {
  description = "The ID of the GCP project"
  type        = string
}

variable "gcp_region" {
  description = "The GCP region to use."
  type        = string
}

variable "kubernetes_cluster_subnet_name" {
  description = "The name of the subnet to use for the Kubernetes nodes"
  type        = string
}

variable "kubernetes_control_plane_ipv4_cidr" {
  description = "The IPv4 CIDR to use for the Kubernetes control plane"
  type        = string
}

variable "kubernetes_pods_subnet_secondary_range_name" {
  description = "The name of the secondary range (of the private subnet for the Kubernetes nodes) to use for the Pod IPs"
  type        = string
}

variable "kubernetes_services_subnet_secondary_range_name" {
  description = "The name of the secondary range (of the private subnet for the Kubernetes nodes) to use for the Service IPs"
  type        = string
}

variable "on_demand_node_machine_type" {
  description = "The machine type for the on-demand nodes"
  type        = string
  default     = "e2-medium"
}

variable "vpc_name" {
  description = "The VPC network to use"
  type        = string
}
