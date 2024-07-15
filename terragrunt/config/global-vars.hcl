locals {
  kube_prometheus_version    = "v0.13.0"
  kube_state_metrics_version = "v2.13.0"
  monitoring_emails_from = {
    address       = "monitoring@cameronhudson8.com"
    auth_username = get_env("MONITORING_EMAIL_FROM_USERNAME")
    transport     = "smtp.zoho.com:587"
  }
  monitoring_emails_from_auth_password = get_env("MONITORING_EMAIL_FROM_PASSWORD")
  monitoring_emails_to_address         = "cameronhudson8@gmail.com"
  prometheus_operator_version = "v0.75.2"
}
