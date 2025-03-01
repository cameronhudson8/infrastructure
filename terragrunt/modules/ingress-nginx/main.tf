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
  set {
    name  = "controller.service.type"
    value = var.service_type
  }
  version    = var.helm_chart_version
}
