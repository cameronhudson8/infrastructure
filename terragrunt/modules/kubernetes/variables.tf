variable "env_name" {
  description = "The name of the environment in which the Kubernetes cluster exists"
  type        = string
}

variable "gcp_project_id" {
  description = "The ID of the GCP project"
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

variable "node_count" {
  default     = 3
  description = "The number of nodes to create"
  type        = number
}

variable "node_machine_type" {
  default     = "e2-small"
  description = "The machine type of the nodes"
  type        = string
}

variable "vpc_name" {
  description = "The VPC network to use"
  type        = string
}
