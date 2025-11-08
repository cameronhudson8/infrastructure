# Based on https://docs.cilium.io/en/latest/network/servicemesh/default-deny-ingress-policy/
resource "kubernetes_manifest" "cilium_network_poilicy_deny_by_default" {
  manifest = {
    "apiVersion" = "cilium.io/v2"
    "kind"       = "CiliumClusterwideNetworkPolicy"
    "metadata" = {
      "name" = "deny-ingress-and-egress"
    }
    "spec" = {
      "description" = "Block all the traffic (except DNS) by default"
      "egress" = [
        {
          "toEndpoints" = [
            {
              "matchLabels" = {
                "io.kubernetes.pod.namespace" = "kube-system"
                "k8s-app"                     = "kube-dns"
              }
            },
          ]
          "toPorts" = [
            {
              "ports" = [
                {
                  "port"     = 53
                  "protocol" = "TCP"
                },
                {
                  "port"     = 53
                  "protocol" = "UDP"
                },
              ]
            },
          ]
        },
      ]
      "endpointSelector" = {
        "matchExpressions" = [
          {
            "key"      = "io.kubernetes.pod.namespace"
            "operator" = "NotIn"
            "values" = [
              "gke-managed-cim",
              "gke-managed-dpv2-observability",
              "gke-managed-system",
              "gke-managed-volumepopulator",
              "gmp-public",
              "gmp-system",
              "kube-node-lease",
              "kube-public",
              "kube-system",
            ]
          }
        ]
      }
      "ingress" = [{}]
    }
  }
}
