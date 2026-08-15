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
