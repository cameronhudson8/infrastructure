locals {
  ingress_nginx_helm_chart_version = "4.12.0"
  ingress_nginx_service_type       = "NodePort"
  kube_prometheus_version          = "v0.14.0"
  kubectl_context_name             = "local"
  kubernetes_version               = "1.30"
  lima_version                     = "v1.0.1"
  vm_name                          = "k8s"
  vpa_operator_version             = "1.2.0"
}
