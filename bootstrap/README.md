# Bootstrap

Cilium is installed first because the Kubernetes nodes need a working CNI
before Argo CD can run. Argo CD then becomes the GitOps entry point for the
remaining infrastructure and applications.

```sh
./bootstrap/install-cilium.sh
./bootstrap/install-argocd.sh
```

Argo CD is pinned to `v3.5.1` in `argocd/kustomization.yaml`. The root
`Application` follows the `main` branch of this repository and synchronizes the
definitions in `apps/`. Automatic self-healing is enabled, while automatic
pruning stays disabled until the managed resources have been verified.

NetBird requires a personal access token that must remain outside Git. Create
the token in the NetBird dashboard, then bootstrap its Kubernetes Secret before
the NetBird operator synchronizes:

```sh
./bootstrap/create-netbird-api-secret.sh
```

The complete remote-access procedure is documented in
[`infrastructure/netbird/README.md`](../infrastructure/netbird/README.md).

## Argo CD UI

Keep the UI private and forward it to the local machine when needed:

```sh
KUBECONFIG="$PWD/.local/kubeconfig" \
  kubectl -n argocd port-forward svc/argocd-server 8080:443
```

Open <https://localhost:8080>. The initial username is `admin`; obtain its
one-time password without storing it in the repository:

```sh
KUBECONFIG="$PWD/.local/kubeconfig" \
  kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 --decode
echo
```

Change the password after the first login, then remove the initial password
Secret:

```sh
KUBECONFIG="$PWD/.local/kubeconfig" \
  kubectl -n argocd delete secret argocd-initial-admin-secret
```
