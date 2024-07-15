# Since the operator is yaml-based and has ClusterRoleBinding(s),
# there is no elegant way to specify the namespace.
# By default, it will use namespace 'default'.
data "kubernetes_namespace" "default" {
  metadata {
    name = "default"
  }
}

resource "kubernetes_network_policy" "deny_ingress_and_egress" {
  metadata {
    name      = "deny-ingress-and-egress"
    namespace = data.kubernetes_namespace.default.metadata[0].name
  }
  spec {
    pod_selector {}
    policy_types = [
      "Egress",
      "Ingress",
    ]
  }
}

data "http" "prometheus_operator" {
  url = "https://github.com/prometheus-operator/prometheus-operator/releases/download/${var.operator_version}/bundle.yaml"
}

data "kubectl_file_documents" "prometheus_operator" {
  content = data.http.prometheus_operator.response_body
}

resource "kubernetes_manifest" "prometheus_operator" {
  for_each = {
    for manifest in [
      for _, manifest_yaml_string in data.kubectl_file_documents.prometheus_operator.manifests : yamldecode(manifest_yaml_string)
      ] : join("|", compact([
        manifest.apiVersion,
        manifest.kind,
        lookup(lookup(manifest, "metadata", {}), "namespace", ""),
        lookup(lookup(manifest, "metadata", {}), "name", ""),
    ])) => manifest
  }
  manifest = each.value
  computed_fields = [
    "spec.template.metadata.annotations",
  ]
}
