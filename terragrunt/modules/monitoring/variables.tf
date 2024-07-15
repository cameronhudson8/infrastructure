variable "alertmanager_replicas" {
  description = "The number of Alertmanager replicas"
  type        = number
}

variable "kube_prometheus_version" {
  description = "The version of kube-prometheus to use (for PrometheusRules only)"
  type        = string
}

variable "kube_state_metrics_version" {
  description = "The version of kube-state-metrics to use"
  type        = string
}

variable "monitoring_emails_from" {
  description = "Details of the email account from which monitoring alerts are sent"
  type = object({
    address       = string
    auth_username = string
    transport     = string
  })
}

variable "monitoring_emails_from_auth_password" {
  description = "The password of the email account from which monitoring alerts are sent"
  sensitive   = true
  type        = string
}

variable "monitoring_emails_to_address" {
  description = "The email address to which monitoring alerts are sent"
  type        = string
}

variable "prometheus_replicas" {
  description = "The number of Prometheus replicas"
  type        = number
}

variable "kube_prometheus_alerts_to_disable" {
  default     = []
  description = "Alerts that kube-prometheus includes, but which we want to disable."
  type        = list(string)
}
