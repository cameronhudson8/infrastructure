locals {
  node_class_api_version = {
    group = "karpenter.k8s.gcp"
    kind  = "v1alpha1"
  }
}

resource "kubernetes_manifest" "node_class_main" {
  manifest = {
    apiVersion = "${local.node_class_api_version.group}/${local.node_class_api_version.kind}"
    kind       = "GCENodeClass"
    metadata = {
      name = "main"
    }
    spec = {
      imageSelectorTerms = [
        { alias = "ContainerOptimizedOS@latest" },
      ]
    }
  }
}

resource "kubernetes_manifest" "node_pool_main" {
  manifest = {
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata = {
      name = "main"
    }
    spec = {
      limits = {
        cpu    = "16"
        memory = "32Gi"
      }
      template = {
        spec = {
          nodeClassRef = {
            group = local.node_class_api_version.group
            kind  = local.node_class_api_version.kind
            name  = kubernetes_manifest.node_class_main.manifest.metadata.name
          }
          requirements = [
            {
              key      = "topology.kubernetes.io/zone"
              operator = "In"
              # For now, only use 3 availability zones, to limit cost.
              values = [
                "us-central1-a",
                "us-central1-b",
                "us-central1-c",
              ]
            },
            {
              key      = "karpenter.sh/capacity-type"
              operator = "In"
              values   = ["spot"]
            },
            {
              key      = "karpenter.k8s.gcp/instance-family"
              operator = "In"
              values = [
                "c2d",
                "c3",
                "c3d",
                "e2",
                "m1",
                "m2",
                "n1",
                "n2d",
                "t2a",
                "t2d",
              ]
            },
            {
              key      = "kubernetes.io/arch"
              operator = "In"
              values = [
                "arm64",
                "amd64",
              ]
            }
          ]
        }
      }
    }
  }
}
