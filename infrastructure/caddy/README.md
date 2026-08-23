# Caddy

Caddy runs inside Kubernetes as the LAN reverse proxy for Homepage:

```text
LAN client :30080 -> Caddy NodePort -> Caddy Pod -> Homepage ClusterIP :3000
```

Open Homepage through any cluster node:

- <http://192.168.187.201:30080>
- <http://192.168.187.202:30080>
- <http://192.168.187.203:30080>

The Service is intentionally HTTP-only and should remain on the trusted home
LAN. Do not forward ports `30080-30087` to the internet because several of the
proxied administrative interfaces have no authentication.

Homepage's service cards use these Caddy routes:

| Port | UI | Kubernetes upstream |
| ---: | --- | --- |
| `30080` | Homepage | `homepage.homepage:3000` |
| `30081` | Argo CD | `argocd-server.argocd:443` |
| `30082` | Longhorn | `longhorn-frontend.longhorn-system:80` |
| `30083` | Hubble | `hubble-ui.kube-system:80` |
| `30084` | Grafana and Loki Explore | `monitoring-grafana.monitoring:80` |
| `30085` | Prometheus | `monitoring-kube-prometheus-prometheus.monitoring:9090` |
| `30086` | Alertmanager | `monitoring-kube-prometheus-alertmanager.monitoring:9093` |
| `30087` | MinIO Console | `minio-console.minio:9001` |

Add routes to `Caddyfile`. Kustomize hashes the generated ConfigMap name, so an
Argo CD sync rolls the Caddy Pods whenever that file changes.

Verify the deployment with:

```sh
KUBECONFIG="$PWD/.local/kubeconfig" \
  kubectl -n caddy-system get deployment,pods,service,endpointslice
```
