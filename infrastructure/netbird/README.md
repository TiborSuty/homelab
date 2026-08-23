# NetBird

NetBird provides private remote `kubectl` access to this cluster without making
the Kubernetes API publicly reachable. The initial deployment consists of:

- cert-manager `1.21.1` for the operator admission-webhook certificate;
- NetBird Kubernetes operator `0.8.0` connected to NetBird Cloud;
- a `ClusterProxy` named `homelab`;
- a NetBird `kubernetes-admins` group mapped to Kubernetes `cluster-admin`.
- a single routing peer exposing Homepage directly as a private network
  resource at `homepage.homepage.homelab.internal:3000`.

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

## 3. Authorize the administrator device

In the NetBird dashboard, add the administrator's NetBird peer (for example,
`MacBookPro.lan`) to the `kubernetes-admins` group. A request from a peer in
that group receives Kubernetes `cluster-admin` through identity impersonation;
do not add ordinary user devices.

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
netbird kubernetes write-kubeconfig homelab \
  --kubeconfig "$PWD/.local/netbird-kubeconfig"
KUBECONFIG="$PWD/.local/netbird-kubeconfig" kubectl get nodes
```

NetBird `0.77.1` can report an `in-addr.arpa` lookup error for the Kubernetes
commands on macOS even while the NetBird hostname resolves through macOS's
scoped DNS. In that case, create the same token-less context directly:

```sh
./bootstrap/create-netbird-kubeconfig.sh
KUBECONFIG="$PWD/.local/netbird-kubeconfig" kubectl get nodes
```

The generated kubeconfig is under the ignored `.local/` directory and contains
no Kubernetes credential. NetBird supplies the device identity at the proxy.

Test the final command from a network outside the home LAN, such as a phone
hotspot. Router port forwarding is not required.

## Private Homepage access

The NetBird account must contain the `homelab.internal` custom DNS zone,
distributed to `dashboard-clients`, and an enabled `dashboard-access` policy
allowing that group to reach `dashboard-services` on TCP port `3000`.

With the NetBird client connected, open:

```text
http://homepage.homepage.homelab.internal:3000
```

This route targets the Homepage `ClusterIP` Service directly. Caddy remains the
LAN entry point for ports `30080-30087`, but it is not in the NetBird path.
The routing peer uses NetBird's rootless userspace image because Cilium's
kube-proxy replacement bypasses the kernel conntrack return path used by the
standard routing image.

## Scope and recovery

The NetBird configuration exposes the Kubernetes API and Homepage only. It does
not expose Caddy's other admin UI ports, the Talos API, iDRAC, or the complete
home LAN. Add a separate `NetworkResource` and narrowly scoped policy for each
additional private service.

Because the `ClusterProxy` runs inside Kubernetes, it cannot provide break-glass
access while the cluster or Cilium is down. That requires a separate NetBird
routing peer on an independent LAN device.
