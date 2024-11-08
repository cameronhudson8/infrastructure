# The Metrics Server is a prerequisite for the vertical pod autoscaler operator.
data "http" "metrics_server" {
  url = "https://github.com/kubernetes-sigs/metrics-server/releases/download/${var.metrics_server_version}/high-availability-1.21+.yaml"
}

# Default namespace == "kube-system"
resource "kubernetes_manifest" "metrics_server" {
  for_each = {
    for manifest in provider::kubernetes::manifest_decode_multi(data.http.metrics_server.response_body)
    : join(",", compact([
      "apiVersion=${manifest.apiVersion}",
      "kind=${manifest.kind}",
      try("namespace=${manifest.metadata.namespace}", ""),
      try("name=${manifest.metadata.name}", ""),
    ]))
    => manifest
  }
  manifest = each.value
}
