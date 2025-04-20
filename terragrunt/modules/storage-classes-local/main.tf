resource "kubernetes_storage_class" "local" {
  metadata {
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
    name = var.storage_class_name
  }
  storage_provisioner = "kubernetes.io/no-provisioner"
  volume_binding_mode = "WaitForFirstConsumer"
}
