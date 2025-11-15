# IPv4 CIDR block calculations
#
# Address Range                     |               CIDR |  Final Address | Address Count
# --------------------------------- | ------------------ | -------------- | -------------
# ++ Secondary Range 1 (Pods)       |         10.0.0.0/9 | 10.127.255.255 | 2 ^ 23
# ++ Kubernetes Pods                |                  - | 10.127.255.253 | 2 ^ 23 - 2
# ++ (Reserved) "For future use"    |  10.127.255.254/32 | 10.127.255.254 | 2 ^ 0
# ++ (Reserved) "Broadcast address" |  10.127.255.255/32 | 10.127.255.255 | 2 ^ 0

# +  Subnet (Nodes)                 |      10.128.0.0/10 | 10.191.255.255 | 2 ^ 22
# ++ (Reserved) "Network address"   |      10.128.0.1/32 | 10.128.  0.  1 | 2 ^ 0
# ++ (Reserved) "Default gateway"   |      10.128.0.2/32 | 10.128.  0.  2 | 2 ^ 0
# ++ Kubernetes Nodes               |                  - | 10.191.255.253 | 2 ^ 22 - 4
# ++ (Reserved) "For future use"    |  10.191.255.254/32 | 10.191.255.254 | 2 ^ 0
# ++ (Reserved) "Broadcast address" |  10.191.255.255/32 | 10.191.255.255 | 2 ^ 0

# + <Unused>                        |      10.224.0.0/12 | 10.239.255.255 | 2 ^ 20
# + <Unused>                        |      10.240.0.0/13 | 10.247.255.255 | 2 ^ 19
# + <Unused>                        |      10.248.0.0/14 | 10.251.255.255 | 2 ^ 18
# + <Unused>                        |      10.252.0.0/15 | 10.253.255.255 | 2 ^ 17

# /16 is the largest possible service range, per https://cloud.google.com/kubernetes-engine/docs/concepts/alias-ips#cluster_sizing_secondary_range_svcs
# +  Secondary Range 2 (Services)   |      10.254.0.0/16 | 10.254.255.255 | 2 ^ 16
# ++ Kubernetes Services            |                  - | 10.254.255.253 | 2 ^ 16 - 2
# ++ (Reserved) "For future use"    |  10.254.255.254/32 | 10.254.255.254 | 2 ^ 0
# ++ (Reserved) "Broadcast address" |  10.254.255.255/32 | 10.254.255.255 | 2 ^ 0

# + <Unused>                        |      10.255.0.0/17 | 10.255.127.255 | 2 ^ 15
# + <Unused>                        |    10.255.128.0/18 | 10.255.191.255 | 2 ^ 14
# + <Unused>                        |    10.255.192.0/19 | 10.255.223.255 | 2 ^ 13
# + <Unused>                        |    10.255.224.0/20 | 10.255.239.255 | 2 ^ 12
# + <Unused>                        |    10.255.240.0/21 | 10.255.247.255 | 2 ^ 11
# + <Unused>                        |    10.255.248.0/22 | 10.255.251.255 | 2 ^ 10
# + <Unused>                        |    10.255.252.0/23 | 10.255.253.255 | 2 ^ 9
# + <Unused>                        |    10.255.254.0/24 | 10.255.254.255 | 2 ^ 8
# + <Unused>                        |    10.255.255.0/25 | 10.255.255.127 | 2 ^ 7
# + <Unused>                        |  10.255.255.128/26 | 10.255.255.191 | 2 ^ 6
# + <Unused>                        |  10.255.255.192/27 | 10.255.255.223 | 2 ^ 5
# + Kubernetes control plane        |  10.255.255.224/28 | 10.255.255.239 | 2 ^ 4
# + <Unused>                        |  10.255.255.240/29 | 10.255.255.247 | 2 ^ 3

# +  Subnet (Public)                |  10.255.255.248/29 | 10.255.255.255 | 2 ^ 3
# ++ (Reserved) "Network address"   |  10.255.255.248/32 | 10.255.255.248 | 2 ^ 0
# ++ (Reserved) "Default gateway"   |  10.255.255.249/32 | 10.255.255.249 | 2 ^ 0
# ++ Load Balancers                 |                  - | 10.255.255.253 | 2 ^ 3 - 4
# ++ (Reserved) "For future use"    |  10.255.255.254/32 | 10.255.255.254 | 2 ^ 0
# ++ (Reserved) "Broadcast address" |  10.255.255.255/32 | 10.255.255.255 | 2 ^ 0

env_name = "staging"
# I currently only have 1 GCP project. Reconsider later.
gcp_project_id                     = "cameronhudson8"
gcp_region                         = "us-central1"
ingress_nginx_helm_chart_version   = "4.12.0"
ingress_nginx_service_type         = "LoadBalancer"
karpenter_version                  = "main"
kube_prometheus_version            = "v0.14.0"
kubernetes_cluster_location        = "us-central1-a"
kubernetes_cluster_name            = "main"
kubernetes_control_plane_ipv4_cidr = "10.255.255.224/28"
kubernetes_nodes_ipv4_cidr         = "10.128.0.0/10"
kubernetes_pods_ipv4_cidr          = "10.0.0.0/9"
kubernetes_services_ipv4_cidr      = "10.254.0.0/16"
kubernetes_version                 = "1.30"
load_balancers_ipv4_cidr           = "10.255.255.248/29"
node_count                         = 3
node_machine_type                  = "e2-standard-2"
tf_state_bucket_name               = "cameronhudson8-staging-tf-state"
vpa_operator_version               = "1.2.0"
