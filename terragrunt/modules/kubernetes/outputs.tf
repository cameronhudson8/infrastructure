output "control_plane_ca_certificate" {
  description = "The certificate of the certificate authority that issued the control plane's TLS certificate."
  value       = base64decode(google_container_cluster.main.master_auth[0].cluster_ca_certificate)
}

output "control_plane_endpoint" {
  description = "The URI at which the cluster's control plane can be reached"
  value       = google_container_cluster.main.endpoint
}
