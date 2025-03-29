data "external" "vm_state" {
  program = [
    "/usr/bin/env",
    "bash",
    "-eu",
    "-o",
    "pipefail",
    "-c",
    <<-SCRIPT
      function vm_exists {
          limactl list | grep -q '${var.vm_name}'
      }
      if vm_exists; then
          limactl list | awk 'NR>1 && $1 == "${var.vm_name}" { printf "{ \"exists\": \"true\", \"state\": \"%s\" }", tolower($2) }'
      else
          echo '{ "exists": "false" }'
      fi
    SCRIPT
  ]
}

resource "terraform_data" "cluster" {
  input = {
    kubectl_context_name = var.kubectl_context_name
    kubernetes_version   = var.kubernetes_version
    lima_version         = var.lima_version
    vm_name              = var.vm_name
    vm_state             = data.external.vm_state.result
  }
  triggers_replace = [
    data.external.vm_state.result,
    var.kubectl_context_name,
    var.kubernetes_version,
    var.lima_version,
    var.vm_name,
  ]
  provisioner "local-exec" {
    # TODO Download template file and template with k8s version
    command = <<-EOF
      function create_vm {
          limactl create 'https://raw.githubusercontent.com/lima-vm/lima/refs/tags/${self.input.lima_version}/templates/k8s.yaml' \
              --cpus 4 \
              --disk 20 \
              --memory 12 \
              --name '${self.input.vm_name}' \
              --set ".provision = (
                  .provision
                  | map(
                      to_entries
                      | map({
                          \"key\": .key,
                          \"value\": (
                              .value
                              | sub(\"VERSION=.*\"; \"VERSION='${self.input.kubernetes_version}'\")
                          )
                      })
                      | from_entries
                    )
              )" \
              --set '.provision = (
                  .provision
                  | map(
                      to_entries
                      | .[]
                      |= (
                          (.value | match("(?P<before>[\s\S]+?)(?P<clusterConfig>kind: ClusterConfiguration[\s\S]+)(?P<after>---[\s\S]+)")) as $matches
                          | with(
                              select(($matches | length) == 0);
                              .value
                              )
                          | with(
                              select(($matches | length) > 0);
                              .value = (
                                  ($matches.captures[] | select(.name == "before") | .string) as $before
                                  | ($matches.captures[] | select(.name == "clusterConfig") | .string) as $clusterConfig
                                  | ($matches.captures[] | select(.name == "after") | .string) as $after
                                  | $clusterConfig
                                  | fromyaml
                                  | . += {
                                      "controllerManager": {
                                          "extraArgs": {
                                              "bind-address": "0.0.0.0"
                                          }
                                      },
                                      "scheduler": {
                                          "extraArgs": {
                                              "bind-address": "0.0.0.0"
                                          }
                                      }
                                  }
                                  | toyaml
                                  | "\($before)\(.)\($after)"
                              )
                          )
                      )
                      | from_entries
                  )
              )'
      }
      function start_vm {
          limactl start '${self.input.vm_name}'
          yq \
              -i \
              "
                . *= load(\"$${HOME}/.lima/${self.input.vm_name}/copied-from-guest/kubeconfig.yaml\")
                | .contexts[0].name = \"${self.input.kubectl_context_name}\"
              " \
              "$${HOME}/.kube/config"
      }
      if [ '${self.input.vm_state.exists}' == 'false' ]; then
          create_vm
          start_vm
          exit 0
      fi
      case '${self.input.vm_state.state}' in
        'running')
            ;;
        'stopped')
            start_vm
            ;;
        *)
          echo "ERROR: Unknown VM state '${self.input.vm_state.state}'." >&2
          exit 1
      esac
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
}
