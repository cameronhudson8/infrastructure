variable "cluster_location" {
  description = "The location (region or zone) of the Kubernetes cluster (its control plane)"
  type        = string
}

variable "cluster_name" {
  description = "The name of the Kubernetes cluster"
  type        = string
}

variable "karpenter_version" {
  description = "A git tag of https://github.com/cloudpilot-ai/karpenter-provider-gcp"
  type        = string
}

variable "node_service_account_name" {
  description = "The name of the GCP service account assigned to the Kubernetes nodes"
  type        = string
}
