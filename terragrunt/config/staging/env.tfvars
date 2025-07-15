# IPv4 CIDR block calculations
# 
# Address Range               | CIDR              | Final Address
# --------------------------- | ----------------- | --------------
# + Private subnet            |        10.0.0.0/9 | 10.127.255.255
# ++ Kubernetes pods          |       10.0.0.0/10 |  10.63.255.255
# ++ Kubernetes services      |      10.64.0.0/11 |  10.95.255.255
# ++ Kubernetes nodes         |      10.96.0.0/11 | 10.255.255.255
# + Public subnet             |     10.128.0.0/10 | 10.191.255.255
# ++ Load balancers           |     10.128.0.0/10 | 10.191.255.255
# + <Unused>                  |     10.192.0.0/11 | 10.223.255.255
# + <Unused>                  |     10.224.0.0/12 | 10.239.255.255
# + <Unused>                  |     10.240.0.0/13 | 10.247.255.255
# + <Unused>                  |     10.248.0.0/14 | 10.251.255.255
# + <Unused>                  |     10.252.0.0/15 | 10.253.255.255
# + <Unused>                  |     10.254.0.0/16 | 10.254.255.255
# + <Unused>                  |     10.255.0.0/17 | 10.255.127.255
# + <Unused>                  |   10.255.128.0/18 | 10.255.191.255
# + <Unused>                  |   10.255.192.0/19 | 10.255.223.255
# + <Unused>                  |   10.255.224.0/20 | 10.255.239.255
# + <Unused>                  |   10.255.240.0/21 | 10.255.247.255
# + <Unused>                  |   10.255.248.0/22 | 10.255.251.255
# + <Unused>                  |   10.255.252.0/23 | 10.255.253.255
# + <Unused>                  |   10.255.254.0/24 | 10.255.254.255
# + <Unused>                  |   10.255.255.0/25 | 10.255.255.127
# + <Unused>                  | 10.255.255.128/26 | 10.255.255.191
# + <Unused>                  | 10.255.255.192/27 | 10.255.255.223
# + Kubernetes control plane  | 10.255.255.224/28 | 10.255.255.239
# + <Unused>                  | 10.255.255.240/28 | 10.255.255.255
# VPC                         |        10.0.0.0/8 | 10.255.255.255

# I currently only have 1 GCP project. Reconsider later.
gcp_project_id                     = "cameronhudson8"
gcp_region                         = "us-central1"
ingress_nginx_helm_chart_version   = "4.12.0"
ingress_nginx_service_type         = "LoadBalancer"
kube_prometheus_version            = "v0.14.0"
kubernetes_control_plane_ipv4_cidr = "10.255.255.224/28"
kubernetes_nodes_ipv4_cidr         = "10.96.0.0/11"
kubernetes_pods_ipv4_cidr          = "10.0.0.0/10"
kubernetes_services_ipv4_cidr      = "10.64.0.0/11"
kubernetes_version                 = "1.30"
# "e2-standard-2" costs less per CPU and per GB mem, but the smallest size is twice as large as "t2a-standard-1".
# on_demand_node_machine_type      = "t2a-standard-1"
on_demand_node_machine_type = "e2-small"
public_subnet_ipv4_cidr     = "10.128.0.0/10"
tf_state_bucket_name        = "cameronhudson8-staging-tf-state"
vpa_operator_version        = "1.2.0"
