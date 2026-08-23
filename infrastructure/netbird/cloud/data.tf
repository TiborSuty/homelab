data "netbird_network" "homelab_services" {
  name = "homelab-services"
}

# The Kubernetes operator owns this network resource. Its NetBird resource ID
# is stable for the lifetime of applications/homepage/network-resource.yaml.
data "netbird_network_resource" "homepage" {
  network_id = data.netbird_network.homelab_services.id
  id         = var.homepage_resource_id
}

data "netbird_reverse_proxy_domain" "free" {
  type = "free"
}
