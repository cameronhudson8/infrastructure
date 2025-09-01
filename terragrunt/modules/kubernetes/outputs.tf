output "control_plane_endpoint" {
  description = "The URI at which the cluster's control plane can be reached"
  value       = "https://${google_container_cluster.main.control_plane_endpoints_config[0].dns_endpoint_config[0].endpoint}"
}

output "node_service_account_name" {
  description = "The name of the GCP service account assigned to the Kubernetes nodes"
  value       = google_service_account.nodes.name
}
