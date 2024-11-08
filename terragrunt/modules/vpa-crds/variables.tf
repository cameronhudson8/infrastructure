variable "metrics_server_version" {
  description = "The version of the Metrics Server to install"
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
