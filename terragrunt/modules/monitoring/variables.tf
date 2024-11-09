variable "emails" {
  description = "The configuration for alert emails"
  type = object({
    recipient = object({
      email_address = string
    })
    sender = object({
      email_address = string
      password      = sensitive(string)
      transport     = string
    })
  })
}

variable "kube_prometheus_alerts_to_disable" {
  default     = []
  description = "Alerts that kube-prometheus includes, but which we want to disable."
  type        = list(string)
}

variable "kube_prometheus_version" {
  description = "The version of kube-prometheus to use (for PrometheusRules only)"
  type        = string
}

variable "namespace_name" {
  description = "The name of the namespace to use."
  type        = string
}

variable "prometheus_replicas" {
  description = "The number of Prometheus replicas"
  type        = number
}
