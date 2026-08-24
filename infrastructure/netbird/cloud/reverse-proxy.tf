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
      # SSO distribution groups must come from the identity provider, not from
      # NetBird peer groups. Direct mesh access remains restricted by policy.
      enabled = true
    }
  }
}

resource "netbird_reverse_proxy_service" "grafana" {
  name              = "grafana"
  domain            = "tiborsuty-grafana.${data.netbird_reverse_proxy_domain.free.domain}"
  enabled           = true
  pass_host_header  = true
  rewrite_redirects = true

  targets = [{
    target_id   = data.netbird_network_resource.grafana.id
    target_type = "host"
    port        = 80
    protocol    = "http"
    path        = "/"
    enabled     = true
  }]

  auth = {
    bearer_auth = {
      enabled = true
    }
  }
}

resource "netbird_reverse_proxy_service" "argocd" {
  name              = "argocd"
  domain            = "tiborsuty-argocd.${data.netbird_reverse_proxy_domain.free.domain}"
  enabled           = true
  pass_host_header  = true
  rewrite_redirects = true

  targets = [{
    target_id   = data.netbird_network_resource.argocd.id
    target_type = "host"
    port        = 80
    protocol    = "http"
    path        = "/"
    enabled     = true
  }]

  auth = {
    bearer_auth = {
      enabled = true
    }
  }
}

resource "netbird_reverse_proxy_service" "longhorn" {
  name              = "longhorn"
  domain            = "tiborsuty-longhorn.${data.netbird_reverse_proxy_domain.free.domain}"
  enabled           = true
  pass_host_header  = true
  rewrite_redirects = true

  targets = [{
    target_id   = data.netbird_network_resource.longhorn.id
    target_type = "host"
    port        = 80
    protocol    = "http"
    path        = "/"
    enabled     = true
  }]

  auth = {
    bearer_auth = {
      enabled = true
    }
  }
}

resource "netbird_reverse_proxy_service" "hubble" {
  name              = "hubble"
  domain            = "tiborsuty-hubble.${data.netbird_reverse_proxy_domain.free.domain}"
  enabled           = true
  pass_host_header  = true
  rewrite_redirects = true

  targets = [{
    target_id   = data.netbird_network_resource.hubble.id
    target_type = "host"
    port        = 80
    protocol    = "http"
    path        = "/"
    enabled     = true
  }]

  auth = {
    bearer_auth = {
      enabled = true
    }
  }
}

resource "netbird_reverse_proxy_service" "prometheus" {
  name              = "prometheus"
  domain            = "tiborsuty-prometheus.${data.netbird_reverse_proxy_domain.free.domain}"
  enabled           = true
  pass_host_header  = true
  rewrite_redirects = true

  targets = [{
    target_id   = data.netbird_network_resource.prometheus.id
    target_type = "host"
    port        = 9090
    protocol    = "http"
    path        = "/"
    enabled     = true
  }]

  auth = {
    bearer_auth = {
      enabled = true
    }
  }
}

resource "netbird_reverse_proxy_service" "alertmanager" {
  name              = "alertmanager"
  domain            = "tiborsuty-alertmanager.${data.netbird_reverse_proxy_domain.free.domain}"
  enabled           = true
  pass_host_header  = true
  rewrite_redirects = true

  targets = [{
    target_id   = data.netbird_network_resource.alertmanager.id
    target_type = "host"
    port        = 9093
    protocol    = "http"
    path        = "/"
    enabled     = true
  }]

  auth = {
    bearer_auth = {
      enabled = true
    }
  }
}

resource "netbird_reverse_proxy_service" "minio" {
  name              = "minio"
  domain            = "tiborsuty-minio.${data.netbird_reverse_proxy_domain.free.domain}"
  enabled           = true
  pass_host_header  = true
  rewrite_redirects = true

  targets = [{
    target_id   = data.netbird_network_resource.minio.id
    target_type = "host"
    port        = 9001
    protocol    = "http"
    path        = "/"
    enabled     = true
  }]

  auth = {
    bearer_auth = {
      enabled = true
    }
  }
}
