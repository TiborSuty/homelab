data "netbird_dns_zone" "homelab" {
  name = "homelab.internal"
}

# Coder places every workspace application on a unique hostname below this
# wildcard. The CNAME follows the operator-managed Coder Service record, so it
# remains valid if Kubernetes allocates a different ClusterIP in the future.
resource "netbird_dns_record" "coder_apps_wildcard" {
  zone_id = data.netbird_dns_zone.homelab.id
  name    = "*.apps.coder.homelab.internal"
  type    = "CNAME"
  content = "coder.coder-system.homelab.internal"
  ttl     = 300
}
