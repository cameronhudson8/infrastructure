locals {
  kube_prometheus_version                  = "v0.14.0"
  kubernetes_version                       = "1.30"
  monitoring_email_recipient_email_address = "cameronhudson8@gmail.com"
  monitoring_email_sender_transport        = "smtp.zoho.com:587"
  monitoring_namespace_name                = "monitoring"
  vpa_namespace_name                       = "vpa-operator"
  vpa_operator_version                     = "1.2.0"
}
