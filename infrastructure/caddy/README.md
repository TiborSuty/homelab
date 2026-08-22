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
LAN. Do not forward router port `30080` to the internet because Homepage has no
authentication.

Add routes to `Caddyfile`. Kustomize hashes the generated ConfigMap name, so an
Argo CD sync rolls the Caddy Pods whenever that file changes.

Verify the deployment with:

```sh
KUBECONFIG="$PWD/.local/kubeconfig" \
  kubectl -n caddy-system get deployment,pods,service,endpointslice
```
