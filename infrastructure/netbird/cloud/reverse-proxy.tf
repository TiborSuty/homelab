resource "netbird_reverse_proxy_service" "homepage" {
  name              = "homepage"
  domain            = "tiborsuty-homepage.${data.netbird_reverse_proxy_domain.free.domain}"
  enabled           = true
  pass_host_header  = true
  rewrite_redirects = true

  targets = [{
    target_id   = data.netbird_network_resource.homepage.id
    target_type = "host"
    port        = 3000
    protocol    = "http"
    path        = "/"
    enabled     = true
  }]

  # The Cloud shared proxy is public at the network edge. Bearer auth enables
  # NetBird account SSO, so only authenticated organization users are admitted.
  auth = {
    bearer_auth = {
      enabled = true
    }
  }
}
