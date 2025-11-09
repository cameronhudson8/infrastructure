output "control_plane_endpoint" {
  description = "The URI at which the cluster's control plane can be reached"
  value       = "https://${google_container_cluster.main.control_plane_endpoints_config[0].dns_endpoint_config[0].endpoint}"
}
