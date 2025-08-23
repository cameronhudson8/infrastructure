output "kubernetes_cluster_subnet_name" {
  description = "The name of the subnet to use for the Kubernetes cluster (Nodes, Pods, and Services)"
  value       = google_compute_subnetwork.private.name
}

output "kubernetes_pods_subnet_secondary_range_name" {
  description = "The name of the secondary range of the Kubernetes cluster subnet to use for the Pod IPs"
  value = [
    for ip_range in google_compute_subnetwork.private.secondary_ip_range :
    ip_range if ip_range.range_name == "kubernetes-pods"
  ][0].range_name
}

output "kubernetes_services_subnet_secondary_range_name" {
  description = "The name of the secondary range of the Kubernetes cluster subnet to use for the Service IPs"
  value = [
    for ip_range in google_compute_subnetwork.private.secondary_ip_range :
    ip_range if ip_range.range_name == "kubernetes-services"
  ][0].range_name
}

output "private_subnet_id" {
  description = "The ID of the private subnet"
  value       = google_compute_subnetwork.private.id
}

output "private_subnet_ipv6_cidr" {
  description = "The IPv6 CIDR of the public subnet"
  value       = google_compute_subnetwork.private.ipv6_cidr_range
}

output "vpc_id" {
  description = "The ID of the VPC"
  value       = google_compute_network.main.id
}

output "vpc_name" {
  description = "The name of the VPC"
  value       = google_compute_network.main.name
}
