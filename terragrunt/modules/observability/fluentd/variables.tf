variable "env_name" {
  description = "The name of the environment."
  type        = string
}

variable "fluentd_version" {
  description = "The version of Fluentd to use."
  type        = string
}

variable "loki_distributor_name" {
  description = "The name of the loki distributor service."
  type        = string
}

variable "loki_distributor_namespace" {
  description = "The namespace of the loki distributor service."
  type        = string
}

variable "loki_distributor_port" {
  description = "The port of the loki distributor service."
  type        = number
}

variable "namespace_name" {
  description = "The name of the namespace to use."
  type        = string
}
