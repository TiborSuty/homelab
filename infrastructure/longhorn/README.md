# Longhorn

Longhorn provides replicated persistent storage using the V1 data engine. The
chart is deployed by Argo CD from `https://charts.longhorn.io` and pinned in
`bootstrap/apps/longhorn.yaml`.

Each node has one 256 GB SSD shared by Talos and Longhorn. Replica data is kept
under `/var/lib/longhorn` on the persistent Talos EPHEMERAL partition. Longhorn
reserves 30 percent of every disk for Talos, etcd, container images, and logs.
Logical volume capacity may be overprovisioned to 175 percent for sparse
development volumes, while Longhorn still requires 25 percent physical free
space. Three Longhorn replicas therefore consume three times the requested
volume capacity across the cluster. Monitor physical usage before creating more
large volumes. Overprovisioning changes scheduling capacity only; it does not
create physical disk space.

This layout survives normal reboots and Talos upgrades, but a reset or clean
reinstallation of every node destroys all replicas. Important data still needs
an external backup target. Dedicated data disks are preferred when the hardware
is expanded.

The UI remains private. Access it through a local port-forward:

```sh
KUBECONFIG="$PWD/.local/kubeconfig" \
  kubectl -n longhorn-system port-forward svc/longhorn-frontend 8081:80
```

Open <http://localhost:8081>.
