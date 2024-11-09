variable "kubectl_context_name" {
  description = "The name of the context corresponding to the local cluster"
  type        = string
}

variable "kubernetes_version" {
  description = "The version of Kubernetes to use"
  type        = string
}

variable "lima_version" {
  description = "The version (git tag) of lima from which to fetch the template"
  type        = string
}

variable "vm_name" {
  description = "The name of the VM to create for the local cluster"
  type        = string
}
