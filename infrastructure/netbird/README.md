# NetBird

NetBird provides private remote `kubectl` access to this cluster without making
the Kubernetes API publicly reachable. The initial deployment consists of:

- cert-manager `1.21.1` for the operator admission-webhook certificate;
- NetBird Kubernetes operator `0.8.0` connected to NetBird Cloud;
- a `ClusterProxy` named `homelab`;
- a NetBird `kubernetes-admins` group mapped to Kubernetes `cluster-admin`.

The API token is never stored in Git. It exists only in the
`netbird/netbird-mgmt-api-key` Kubernetes Secret.

## 1. Create the NetBird account and API token

Sign in to <https://app.netbird.io> using the identity that will administer the
homelab. In the dashboard, create a personal access token from the user's
**Access Tokens** settings. The operator uses this token to create the NetBird
group and API proxy peer.

Create the Kubernetes Secret from an interactive terminal:

```sh
./bootstrap/create-netbird-api-secret.sh
```

The prompt does not echo the token. To replace an existing token:

```sh
NETBIRD_ROTATE=1 ./bootstrap/create-netbird-api-secret.sh
```

## 2. Deploy through Argo CD

Commit and push the configuration to `main`. The root Argo CD application then
installs cert-manager, the NetBird operator, and the access resources in that
order. Verify them with:

```sh
KUBECONFIG="$PWD/.local/kubeconfig" \
  kubectl -n argocd get applications cert-manager netbird-operator netbird-access

KUBECONFIG="$PWD/.local/kubeconfig" \
  kubectl -n netbird get pods,groups.netbird.io,clusterproxies.netbird.io
```

## 3. Authorize the administrator

In the NetBird dashboard, add the administrator user to the
`kubernetes-admins` group. Membership in that group grants Kubernetes
`cluster-admin` through identity impersonation; do not add ordinary users.

## 4. Connect the Mac

Install and connect the official macOS client:

```sh
brew tap netbirdio/tap
brew install --cask netbirdio/tap/netbird-ui
netbird up
```

Complete the browser login using the same NetBird account. Then create a local
kubeconfig context backed by the NetBird identity:

```sh
netbird status
netbird kubernetes list
netbird kubernetes write-kubeconfig homelab
kubectl --context homelab get nodes
```

Test the final command from a network outside the home LAN, such as a phone
hotspot. Router port forwarding is not required.

## Scope and recovery

This first stage exposes only the Kubernetes API. It does not expose Caddy's
admin UI ports, the Talos API, iDRAC, or the complete home LAN. A later
`NetworkRouter` can provide selected private services after the base tunnel is
verified.

Because the `ClusterProxy` runs inside Kubernetes, it cannot provide break-glass
access while the cluster or Cilium is down. That requires a separate NetBird
routing peer on an independent LAN device.
