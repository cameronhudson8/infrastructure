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
      REPO='github.com/prometheus-operator/kube-prometheus'
      SUBDIR='jsonnet/kube-prometheus'
      MANIFESTS_PATH="${path.module}/kube-prometheus/manifests"
      MANIFESTS_SETUP_PATH="${path.module}/kube-prometheus/manifests/setup"

      mkdir -p "${path.module}/kube-prometheus"
      pushd "${path.module}/kube-prometheus" >/dev/null
      # Create the initial/empty `jsonnetfile.json'.
      if ! [ -f jsonnetfile.json ]; then
        jb init
      fi
      installed_version=$(
        jq -r \
          "
            .dependencies[] \
            | select(.source.git.remote == \"https://$${REPO}.git\" and .source.git.subdir == \"$${SUBDIR}\")
            | .version
          " \
          ./jsonnetfile.json
      )
      if [ "$${installed_version}" != '${var.kube_prometheus_version}' ]; then
        # Install the kube-prometheus dependency.
        # Creates `vendor/` and `jsonnetfile.lock.json`, and fills in `jsonnetfile.json`.
        jb -q install "$${REPO}/$${SUBDIR}@${var.kube_prometheus_version}"
      fi

      kube_prometheus_config_path="$(mktemp)"
      cat <<CONFIG >"$${kube_prometheus_config_path}"
      local kp = (import 'kube-prometheus/main.libsonnet');

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

      manifests_checksum=$(cat "$${kube_prometheus_config_path}" $(find -E "$${MANIFESTS_PATH}" -regex '.*\.ya?ml') | md5 -q)
      manifests_setup_checksum=$(cat "$${kube_prometheus_config_path}" $(find -E "$${MANIFESTS_SETUP_PATH}" -regex '.*\.ya?ml') | md5 -q)

      curl 'https://raw.githubusercontent.com/prometheus-operator/kube-prometheus/${var.kube_prometheus_version}/build.sh' \
          --fail-with-body \
          -LsS \
          | sh -s "$${kube_prometheus_config_path}"
      jq -cM '.' <<JSON
          {
              "manifests_checksum": "$${manifests_checksum}",
              "manifests_path": "$${MANIFESTS_PATH}",
              "manifests_setup_checksum": "$${manifests_setup_checksum}",
              "manifests_setup_path": "$${MANIFESTS_SETUP_PATH}"
          }
      JSON
    EOF
  ]
}

resource "kubernetes_manifest" "kube_prometheus_setup_crds" {
  for_each = {
    for manifest in [
      for _manifest in [
        for file_path in fileset(path.module, "${replace(data.external.kube_prometheus_prepare_manifests.result.manifests_setup_path, path.module, "./")}/*")
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
