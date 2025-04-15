locals {
  grafana_helm_chart_version           = "8.11.3"
  ingress_nginx_helm_chart_version     = "4.12.0"
  ingress_nginx_service_type           = "NodePort"
  kube_prometheus_version              = "v0.14.0"
  kubectl_context_name                 = "local"
  kubernetes_version                   = "1.30"
  lima_version                         = "v1.0.1"
  loki_distributed_helm_chart_version  = "0.80.2"
  mimir_distributed_helm_chart_version = "5.6.0"
  mimir_ingester_replicas              = 1
  mimir_querier_replicas               = 1
  mimir_query_scheduler_replicas       = 1
  mimir_zone_aware_replication         = false
  storage_class_name                   = "local"
  tempo_distributed_helm_chart_version = "1.33.0"
  tempo_ingester_replicas              = 1
  vm_name                              = "k8s"
  vpa_operator_version                 = "1.2.0"
}
