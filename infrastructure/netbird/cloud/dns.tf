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

# Some frontend applications use the first DNS label as their tenant/workspace
# identifier. Each Coder workspace therefore receives a more-specific wildcard
# that preserves that label and sends traffic through the private app gateway.
# Add one entry here for each frontend workspace that needs tenant subdomains.
locals {
  coder_tenant_workspace_domains = toset([
    "frontend-dev.tiborsuty",
    "frontend-dev-2.tiborsuty",
    "frontend-dev-3.tiborsuty",
    "frontend-dev-4.tiborsuty",
    "frontend-dev-5.tiborsuty",
    "frontend-dev-6.tiborsuty",
    "frontend-dev-7.tiborsuty",
    "frontend-dev-8.tiborsuty",
    "frontend-dev-9.tiborsuty",
    "frontend-dev-10.tiborsuty",
  ])
}

resource "netbird_dns_record" "coder_tenant_workspace_apps" {
  for_each = local.coder_tenant_workspace_domains

  zone_id = data.netbird_dns_zone.homelab.id
  name    = "*.${each.value}.apps.coder.homelab.internal"
  type    = "CNAME"
  content = "coder-workspace-apps.coder-system.homelab.internal"
  ttl     = 300
}
