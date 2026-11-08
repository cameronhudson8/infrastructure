variable "email_recipient_email_address" {
  description = "The email address to which to send alerts"
  type        = string
}

variable "email_sender_email_address" {
  description = "The email address from which to send alerts"
  type        = string
}

variable "email_sender_password" {
  description = "The password with which to authenticate with the email server"
  sensitive   = true
  type        = string
}

variable "email_sender_transport" {
  description = "The hostname:port of the email server"
  type        = string
}

variable "env_name" {
  description = "The name of the environment."
  type        = string
}

variable "fluentd_version" {
  description = "The version of Fluentd to use."
  type        = string
}

variable "grafana_helm_chart_version" {
  description = "The version of the grafana helm chart to use"
  type        = string
}

variable "kube_prometheus_version" {
  description = "The version of kube-prometheus to use (for PrometheusRules only)"
  type        = string
}

variable "loki_helm_chart_version" {
  description = "The version of the loki helm chart to use"
  type        = string
}

variable "mimir_distributed_helm_chart_version" {
  description = "The version of the mimir-distributed helm chart to use"
  type        = string
}

variable "tempo_distributed_helm_chart_version" {
  description = "The version of the tempo-distributed helm chart to use"
  type        = string
}
