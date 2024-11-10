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

variable "kube_prometheus_version" {
  description = "The version of kube-prometheus to use (for PrometheusRules only)"
  type        = string
}

variable "namespace_name" {
  description = "The name of the namespace to use."
  type        = string
}
