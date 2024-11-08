# The Metrics Server is a prerequisite for the vertical pod autoscaler operator, but it is already deployed as part of kube-prometheus.

resource "terraform_data" "vpa" {
  input = {
    kubernetes_client_certificate     = var.kubernetes_client_certificate
    kubernetes_client_key             = var.kubernetes_client_key
    kubernetes_cluster_ca_certificate = var.kubernetes_cluster_ca_certificate
    kubernetes_server                 = var.kubernetes_server
    operator_version                  = var.operator_version
  }
  triggers_replace = [
    var.kubernetes_server,
    var.operator_version,
  ]
  provisioner "local-exec" {
    command = <<-EOF
      vpa_repo_dir=$(mktemp -d)
      git clone https://github.com/kubernetes/autoscaler.git "$${vpa_repo_dir}" \
          --branch "vertical-pod-autoscaler-${var.operator_version}" \
          --depth 1
      trap 'rm -rf "$${vpa_repo_dir}"' EXIT

      kube_config_path=$(mktemp)
      cat <<CONFIG >"$${kube_config_path}"
      apiVersion: v1
      clusters:
        - cluster:
            certificate-authority-data: ${base64encode(var.kubernetes_cluster_ca_certificate)}
            server: ${var.kubernetes_server}
          name: default
      contexts:
        - context:
            cluster: default
            user: default
          name: default
      current-context: default
      kind: Config
      users:
        - name: default
          user:
            client-certificate-data: ${base64encode(var.kubernetes_client_certificate)}
            client-key-data: ${base64encode(var.kubernetes_client_key)}
      CONFIG
      export KUBECONFIG="$${kube_config_path}"

      pushd "$${vpa_repo_dir}/vertical-pod-autoscaler"
      TAG='${var.operator_version}' ./hack/vpa-up.sh
      rm "$${kube_config_path}"
    EOF
    interpreter = [
      "/usr/bin/env",
      "bash",
      "-eu",
      "-o",
      "pipefail",
      "-c",
    ]
    # quiet = true
  }

  provisioner "local-exec" {
    command = <<-EOF
      vpa_repo_dir=$(mktemp -d)
      git clone https://github.com/kubernetes/autoscaler.git "$${vpa_repo_dir}" \
          --branch "vertical-pod-autoscaler-${self.input.operator_version}" \
          --depth 1
      trap 'rm -rf "$${vpa_repo_dir}"' EXIT

      kube_config_path=$(mktemp)
      cat <<CONFIG >"$${kube_config_path}"
      apiVersion: v1
      clusters:
        - cluster:
            certificate-authority-data: ${base64encode(self.input.kubernetes_cluster_ca_certificate)}
            server: ${self.input.kubernetes_server}
          name: default
      contexts:
        - context:
            cluster: default
            user: default
          name: default
      current-context: default
      kind: Config
      users:
        - name: default
          user:
            client-certificate-data: ${base64encode(self.input.kubernetes_client_certificate)}
            client-key-data: ${base64encode(self.input.kubernetes_client_key)}
      CONFIG
      export KUBECONFIG="$${kube_config_path}"

      pushd "$${vpa_repo_dir}/vertical-pod-autoscaler"
      TAG='${self.input.operator_version}' ./hack/vpa-down.sh
      rm "$${kube_config_path}"
    EOF
    interpreter = [
      "/usr/bin/env",
      "bash",
      "-eu",
      "-o",
      "pipefail",
      "-c",
    ]
    # quiet = true
    when = destroy
  }
}
