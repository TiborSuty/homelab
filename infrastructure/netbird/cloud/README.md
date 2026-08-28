# NetBird Cloud configuration

Terraform manages the NetBird Cloud reverse-proxy services that cannot yet be
fully expressed by the Kubernetes operator. Kubernetes resources remain owned
by Argo CD and the NetBird operator under `../access/` and the application
directories.

The managed proxies publish:

- Argo CD at `https://tiborsuty-argocd.eu1.netbird.services`;
- Longhorn at `https://tiborsuty-longhorn.eu1.netbird.services`;
- Hubble at `https://tiborsuty-hubble.eu1.netbird.services`;
- Homepage at `https://tiborsuty-homepage.eu1.netbird.services`;
- Headlamp at `https://tiborsuty-headlamp.eu1.netbird.services`;
- Coder at `https://tiborsuty-coder.eu1.netbird.services`;
- Grafana at `https://tiborsuty-grafana.eu1.netbird.services`;
- Prometheus at `https://tiborsuty-prometheus.eu1.netbird.services`;
- Alertmanager at `https://tiborsuty-alertmanager.eu1.netbird.services`;
- MinIO at `https://tiborsuty-minio.eu1.netbird.services`.

All forward HTTP to operator-created network resources and require NetBird
account SSO. SSO distribution groups are intentionally unset because they must
come from the identity provider; NetBird peer groups are not valid substitutes.
Homepage explicitly allowlists its stable public hostname. Do not disable
authentication: Cloud's shared proxy is a public internet entry point even
though its backends are private.

Coder's SSO-protected proxy is intended for browser access. Coder CLI traffic
uses `http://coder.coder-system.homelab.internal` through the private NetBird
network resource, and workspace agents use the in-cluster Service directly.

Terraform also owns the `dashboard-access` policy. It restricts direct mesh
access to the `dashboard-clients` peer group and permits those clients to reach
resources in `dashboard-services` on only the backend HTTP ports used by the
managed dashboards (`80`, `3000`, `9001`, `9090`, and `9093`).

## State and credentials

State is stored and locked in the `netbird` namespace using Kubernetes objects:

- Secret `tfstate-default-netbird-cloud` contains the Terraform state;
- Lease `lock-tfstate-default-netbird-cloud` coordinates state locking.

The wrapper reads the existing `netbird/netbird-mgmt-api-key` Secret and passes
the token to the provider through `NB_PAT`. The token, local Terraform working
directory, plans, state, and variable files are excluded from Git.

## Commands

Install Terraform 1.15 or newer from HashiCorp's official Homebrew tap, then run
from the repository root:

```sh
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
./bootstrap/netbird-cloud.sh plan
./bootstrap/netbird-cloud.sh apply
./bootstrap/netbird-cloud.sh output
```

The helper uses `.local/kubeconfig` unless `KUBECONFIG` is set. It initializes
the Kubernetes backend before commands that need state.

If an operator-managed `NetworkResource` is deleted and recreated, update its
corresponding ID in `variables.tf` from:

```sh
KUBECONFIG="$PWD/.local/kubeconfig" \
  kubectl get networkresource --all-namespaces \
  -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,RESOURCE-ID:.status.resourceID'
```
