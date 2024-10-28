data "external" "kube_prometheus_config" {
  program = [
    "/usr/bin/env",
    "bash",
    "-eu",
    "-o",
    "pipefail",
    "-c",
    <<-EOF
      path="$(mktemp)"
      cat <<CONFIG >"$${path}"
      local kp =
        (import 'kube-prometheus/main.libsonnet') +
        // Uncomment the following imports to enable its patches
        // (import 'kube-prometheus/addons/anti-affinity.libsonnet') +
        // (import 'kube-prometheus/addons/managed-cluster.libsonnet') +
        // (import 'kube-prometheus/addons/node-ports.libsonnet') +
        // (import 'kube-prometheus/addons/static-etcd.libsonnet') +
        // (import 'kube-prometheus/addons/custom-metrics.libsonnet') +
        // (import 'kube-prometheus/addons/external-metrics.libsonnet') +
        // (import 'kube-prometheus/addons/pyrra.libsonnet') +
        {
          values+:: {
            common+: {
              namespace: '${var.namespace_name}',
            },
          },
        };

      { 'setup/0namespace-namespace': kp.kubePrometheus.namespace } +
      {
        ['setup/prometheus-operator-' + name]: kp.prometheusOperator[name]
        for name in std.filter((function(name) name != 'serviceMonitor' && name != 'prometheusRule'), std.objectFields(kp.prometheusOperator))
      } +
      // { 'setup/pyrra-slo-CustomResourceDefinition': kp.pyrra.crd } +
      // serviceMonitor and prometheusRule are separated so that they can be created after the CRDs are ready
      { 'prometheus-operator-serviceMonitor': kp.prometheusOperator.serviceMonitor } +
      { 'prometheus-operator-prometheusRule': kp.prometheusOperator.prometheusRule } +
      { 'kube-prometheus-prometheusRule': kp.kubePrometheus.prometheusRule } +
      { ['alertmanager-' + name]: kp.alertmanager[name] for name in std.objectFields(kp.alertmanager) } +
      { ['blackbox-exporter-' + name]: kp.blackboxExporter[name] for name in std.objectFields(kp.blackboxExporter) } +
      { ['grafana-' + name]: kp.grafana[name] for name in std.objectFields(kp.grafana) } +
      // { ['pyrra-' + name]: kp.pyrra[name] for name in std.objectFields(kp.pyrra) if name != 'crd' } +
      { ['kube-state-metrics-' + name]: kp.kubeStateMetrics[name] for name in std.objectFields(kp.kubeStateMetrics) } +
      { ['kubernetes-' + name]: kp.kubernetesControlPlane[name] for name in std.objectFields(kp.kubernetesControlPlane) }
      { ['node-exporter-' + name]: kp.nodeExporter[name] for name in std.objectFields(kp.nodeExporter) } +
      { ['prometheus-' + name]: kp.prometheus[name] for name in std.objectFields(kp.prometheus) } +
      { ['prometheus-adapter-' + name]: kp.prometheusAdapter[name] for name in std.objectFields(kp.prometheusAdapter) }
      CONFIG
      echo "{\"path\": \"$${path}\"}"
  EOF
  ]
}

data "external" "kube_prometheus_prepare_manifests" {
  program = [
    "/usr/bin/env",
    "bash",
    "-eu",
    "-o",
    "pipefail",
    "-c",
    # This script is based on the kube-prometheus installation docs.
    # https://github.com/prometheus-operator/kube-prometheus/blob/main/docs/customizing.md
    <<-EOF
      mkdir -p "${path.module}/kube-prometheus"
      pushd "${path.module}/kube-prometheus" >/dev/null
      # Create the initial/empty `jsonnetfile.json'.
      rm -f jsonnetfile.json jsonnetfile.lock.json
      if ! [ -f jsonnetfile.json ]; then
        jb init
      fi
      # Install the kube-prometheus dependency.
      # Creates `vendor/` and `jsonnetfile.lock.json`, and fills in `jsonnetfile.json`.
      jb -q install 'github.com/prometheus-operator/kube-prometheus/jsonnet/kube-prometheus@${var.kube_prometheus_version}'
      curl 'https://raw.githubusercontent.com/prometheus-operator/kube-prometheus/${var.kube_prometheus_version}/build.sh' \
          --fail-with-body \
          -LsS \
          | sh -s "${data.external.kube_prometheus_config.result.path}"
      echo '{}'
    EOF
  ]
}

resource "kubernetes_manifest" "kube_prometheus_setup_crds" {
  depends_on = [
    data.external.kube_prometheus_prepare_manifests,
  ]
  for_each = {
    for manifest in [
      for _manifest in [
        for file_path in fileset(path.module, "kube-prometheus/manifests/setup/*")
        : yamldecode(file("${path.module}/${file_path}"))
      ]
      : _manifest if contains(["CustomResourceDefinition"], _manifest.kind)
    ]
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
