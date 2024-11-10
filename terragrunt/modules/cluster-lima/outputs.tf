output "kubectl_context_test" {
  description = "An example command to test cluster access"
  value       = <<EOF
    Test the access to your cluster:
        kubectl --context '${var.kubectl_context_name}' get namespaces
  EOF
}
