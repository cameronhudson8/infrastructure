resource "kubernetes_storage_class" "local" {
  metadata {
    name = "local"
  }
  storage_provisioner = "kubernetes.io/no-provisioner"
  volume_binding_mode = "WaitForFirstConsumer"
}
