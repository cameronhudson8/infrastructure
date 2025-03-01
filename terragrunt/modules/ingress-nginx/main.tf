resource "kubernetes_namespace" "ingress_nginx" {
  metadata {
    name = "ingress-nginx"
  }
}

resource "helm_release" "ingress_nginx" {
  chart      = "ingress-nginx"
  name       = "ingress-nginx"
  namespace  = kubernetes_namespace.ingress_nginx.metadata[0].name
  repository = "https://kubernetes.github.io/ingress-nginx"
  values = [
    yamlencode({
      controller = {
        metrics = {
          enabled = true
        }
        service = {
          type = var.service_type
        }
      }
    })
  ]
  version = var.helm_chart_version
}

# Monitoring

resource "kubernetes_cluster_role" "monitoring_ingress_nginx" {
  metadata {
    name = "monitoring-ingress-nginx"
  }
  rule {
    api_groups = [
      "",
    ]
    resources = [
      "endpoints",
      "pods",
      "services",
    ]
    verbs = [
      "get",
      "list",
      "watch",
    ]
  }
  rule {
    api_groups = [
      "extensions",
    ]
    resources = [
      "ingresses",
    ]
    verbs = [
      "get",
      "list",
      "watch",
    ]
  }
  rule {
    api_groups = [
      "networking.k8s.io",
    ]
    resources = [
      "ingresses",
    ]
    verbs = [
      "get",
      "list",
      "watch",
    ]
  }
}

resource "kubernetes_cluster_role_binding" "prometheus_monitoring_ingress_nginx" {
  metadata {
    name = "prometheus-monitoring-ingress-nginx"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "monitoring-ingress-nginx"
  }
  subject {
    kind      = "ServiceAccount"
    name      = "prometheus-k8s"
    namespace = "monitoring"
  }
}

resource "kubernetes_manifest" "service_monitor" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"
    metadata = {
      name      = "ingress-nginx"
      namespace = kubernetes_namespace.ingress_nginx.metadata[0].name
    }
    spec = {
      jobLabel = "ingress-nginx"
      selector = {
        matchLabels = {
          # Although multiple services have this label, only one (named
          # "ingress-nginx-controller-metrics") also has a port
          # named "metrics".
          "app.kubernetes.io/name" = "ingress-nginx"
        }
      }
      endpoints = [
        {
          port = "metrics"
        }
      ]
    }
  }
}
