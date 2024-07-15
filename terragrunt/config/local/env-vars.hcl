locals {
  alertmanager_replicas = 1
  kube_context          = "local"
  kube_prometheus_alerts_to_disable = [
    // Refer to https://github.com/prometheus-operator/kube-prometheus/tree/v0.14.0.
    // Requires prometheus-adapter to be installed.
    "KubeAggregatedAPIDown",
    // Requires kube-controller-manager to have been exposed (visible within the cluster).
    "KubeControllerManagerDown",
    // Requires node-exporter to be installed.
    "KubeletDown",
    "KubeSchedulerDown"
  ]
  prometheus_replicas = 1
}
