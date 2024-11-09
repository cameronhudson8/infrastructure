resource "terraform_data" "cluster" {
  input = {
    kubectl_context_name = var.kubectl_context_name
    kubernetes_version   = var.kubernetes_version
    lima_version         = var.lima_version
    vm_name              = var.vm_name
  }
  provisioner "local-exec" {
    # TODO Download template file and template with k8s version
    command = <<-EOF
      limactl create 'https://raw.githubusercontent.com/lima-vm/lima/refs/tags/${var.lima_version}/templates/k8s.yaml' \
          --cpus 2 \
          --disk 20 \
          --memory 8 \
          --name '${var.vm_name}' \
          --set ".provision = (.provision | map(to_entries | map({ \"key\": .key, \"value\": (.value | sub(\"VERSION=.*\"; \"VERSION='${var.kubernetes_version}'\")) }) | from_entries))"
      limactl start "${var.vm_name}"
      yq -i ". *= load(\"$${HOME}/.lima/${var.vm_name}/copied-from-guest/kubeconfig.yaml\") | .contexts[0].name = \"${var.kubectl_context_name}\"" "$${HOME}/.kube/config"
    EOF
    interpreter = [
      "/usr/bin/env",
      "bash",
      "-eu",
      "-o",
      "pipefail",
      "-c",
    ]
  }
  provisioner "local-exec" {
    command = <<-EOF
      kubectl config delete-context '${self.input.kubectl_context_name}'
      limactl stop '${self.input.vm_name}'
      limactl delete '${self.input.vm_name}'
    EOF
    interpreter = [
      "/usr/bin/env",
      "bash",
      "-eu",
      "-o",
      "pipefail",
      "-c",
    ]
    when = destroy
  }
}
