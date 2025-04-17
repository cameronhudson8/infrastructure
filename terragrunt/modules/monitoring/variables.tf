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

variable "grafana_helm_chart_version" {
  description = "The version of the grafana helm chart to use"
  type        = string
}

variable "kube_prometheus_version" {
  description = "The version of kube-prometheus to use (for PrometheusRules only)"
  type        = string
}

variable "loki_distributed_helm_chart_version" {
  description = "The version of the loki-distributed helm chart to use"
  type        = string
}

variable "mimir_distributed_helm_chart_version" {
  description = "The version of the mimir-distributed helm chart to use"
  type        = string
}

variable "mimir_ingester_replicas" {
  default     = null
  description = "The number of Mimir ingester replicas"
  type        = number
  validation {
    condition     = var.mimir_ingester_replicas != null && var.mimir_ingester_replicas >= 2
    error_message = "There must be at least 2 Mimir ingester replicas."
  }
}

variable "mimir_querier_replicas" {
  default     = null
  description = "The number of Mimir querier replicas"
  type        = number
}

variable "mimir_query_scheduler_replicas" {
  default     = null
  description = "The number of Mimir query scheduler replicas"
  type        = number
}

variable "mimir_zone_aware_replication" {
  default     = null
  description = "Whether to enable Mimir zone-aware replication (1+ pod/zone)"
  type        = bool
}

variable "namespace_name" {
  description = "The name of the namespace to use."
  type        = string
}

variable "storage_class_name" {
  description = "The name of the storage class to use for the LGTM stack."
  type        = string
}

variable "tempo_distributed_helm_chart_version" {
  description = "The version of the tempo-distributed helm chart to use"
  type        = string
}

variable "tempo_ingester_replicas" {
  default     = null
  description = "The number of Tempo ingester replicas"
  type        = number
}

variable "vm_name" {
  description = "The name of the virtual machine running Kubernetes"
  type        = string
}
