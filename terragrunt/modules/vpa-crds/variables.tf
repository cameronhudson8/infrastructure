variable "kubernetes_client_certificate" {
  description = "The client certificate for authentication with the Kubernetes API server"
  type        = string
}

variable "kubernetes_client_key" {
  description = "The client certificate for authentication with the Kubernetes API server"
  type        = string
}

variable "kubernetes_cluster_ca_certificate" {
  description = "The cluster CA certificate for TLS connection to the Kubernetes API server"
  type        = string
}

variable "kubernetes_server" {
  description = "The base URI of the Kubernetes API server"
  type        = string
}

variable "namespace_name" {
  description = "The name of the namespace in which to deploy"
  type        = string
}

variable "operator_version" {
  description = "The version of the operator to use"
  type        = string
}
