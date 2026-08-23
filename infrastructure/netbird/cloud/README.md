# NetBird Cloud configuration

OpenTofu manages the NetBird Cloud reverse-proxy services that cannot yet be
fully expressed by the Kubernetes operator. Kubernetes resources remain owned
by Argo CD and the NetBird operator under `../access/` and the application
directories.

The Homepage proxy publishes
`https://tiborsuty-homepage.eu1.netbird.services`, forwards HTTP to the
operator-created Homepage network resource on port `3000`, and requires
NetBird account SSO. It passes this stable public hostname to Homepage, where
it is explicitly allowlisted. Do not disable authentication: Cloud's shared
proxy is a public internet entry point even though its backend is private.

## State and credentials

State is stored and locked in the `netbird` namespace using Kubernetes objects:

- Secret `tfstate-default-netbird-cloud` contains the OpenTofu state;
- Lease `lock-tfstate-default-netbird-cloud` coordinates state locking.

The wrapper reads the existing `netbird/netbird-mgmt-api-key` Secret and passes
the token to the provider through `NB_PAT`. The token, local OpenTofu working
directory, plans, state, and variable files are excluded from Git.

## Commands

Install OpenTofu 1.12 or newer, then run from the repository root:

```sh
brew install opentofu
./bootstrap/netbird-cloud.sh plan
./bootstrap/netbird-cloud.sh apply
./bootstrap/netbird-cloud.sh output homepage_reverse_proxy_url
```

The helper uses `.local/kubeconfig` unless `KUBECONFIG` is set. It initializes
the Kubernetes backend before commands that need state.

If the Homepage `NetworkResource` is deleted and recreated, update
`homepage_resource_id` in `variables.tf` from:

```sh
KUBECONFIG="$PWD/.local/kubeconfig" \
  kubectl -n homepage get networkresource homepage \
  -o jsonpath='{.status.resourceID}{"\n"}'
```
