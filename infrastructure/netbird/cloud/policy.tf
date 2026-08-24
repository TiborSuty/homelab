resource "netbird_policy" "dashboard_access" {
  name                  = "dashboard-access"
  description           = "Allow approved NetBird clients to access dashboard services"
  enabled               = true
  source_posture_checks = []

  rule {
    name          = "dashboard-access"
    description   = "Allow approved NetBird clients to access dashboard services"
    enabled       = true
    bidirectional = true
    protocol      = "tcp"
    ports         = ["80", "3000", "9001", "9090", "9093"]
    sources       = [data.netbird_group.dashboard_clients.id]
    destinations  = [data.netbird_group.dashboard_services.id]
    action        = "accept"
  }
}
