# Homelab

Configuration for the Talos Linux Kubernetes cluster and workloads running on it.

```text
homelab/
├── bootstrap/       # GitOps bootstrap and cluster entry point
├── infrastructure/  # Shared cluster services and controllers
├── applications/    # User-facing applications
└── talos/           # Talos machine configuration and patches
```

Local access credentials are stored as `.local/talosconfig` and
`.local/kubeconfig`. The entire `.local/` directory and rendered machine
configurations are intentionally excluded from Git.

Use the local credentials explicitly:

```sh
export KUBECONFIG="$PWD/.local/kubeconfig"
talosctl --talosconfig ./.local/talosconfig version
```

## Cluster networking

Cilium is the only Kubernetes CNI and replaces `kube-proxy`. Talos machine
configurations are prepared with `talos/patches/cilium.yaml`; install or update
the pinned Cilium Helm release with:

```sh
./bootstrap/install-cilium.sh
```

## GitOps

Argo CD watches this public repository and reconciles the cluster from the
declarative definitions under `bootstrap/apps/`:

```sh
./bootstrap/install-argocd.sh
```

See `bootstrap/README.md` for the bootstrap order and local UI access.
