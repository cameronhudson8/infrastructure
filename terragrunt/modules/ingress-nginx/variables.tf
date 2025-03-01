variable "helm_chart_version" {
  description = "The version of the ingress-nginx helm chart to use"
  type        = string
}

variable "service_type" {
  description = "The type of Kubernetes service to create (examples: LoadBalancer, NodePort)"
  type        = string
}
