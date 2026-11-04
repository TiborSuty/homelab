resource "netbird_group" "nix_workspaces" {
  name = "nix-workspaces"
}

resource "netbird_policy" "nix_workspaces" {
  name                  = "nix-workspaces"
  description           = "Private SSH and application access to development workspaces"
  enabled               = true
  source_posture_checks = []

  rule {
    name          = "workspace-access"
    description   = "Approved homelab clients may access workspace SSH and HTTP"
    enabled       = true
    bidirectional = false
    protocol      = "tcp"
    ports         = ["80", "2222"]
    sources       = [data.netbird_group.dashboard_clients.id]
    destinations  = [netbird_group.nix_workspaces.id]
    action        = "accept"
  }
}

# DMS derives the tenant from the first hostname label. The Service preserves
# the HTTP Host header, so no Coder proxy or extra nginx gateway is needed.
resource "netbird_dns_record" "nix_frontend_tenants" {
  zone_id = data.netbird_dns_zone.homelab.id
  name    = "*.frontend-dev.nix-workspaces.homelab.internal"
  type    = "CNAME"
  content = "frontend-dev.nix-workspaces.homelab.internal"
  ttl     = 300
}
