# Talos homelab configuration

All nodes use the `controlplane` machine type. The
`controlplane-workloads.yaml` patch enables ordinary workloads on every
control-plane node.

## Layout

- `base/controlplane.yaml`: sensitive shared configuration and cluster PKI.
- `patches/common.yaml`: SSD selector, DNS, and NTP.
- `patches/controlplane-workloads.yaml`: enables workload scheduling.
- `patches/cilium.yaml`: disables the built-in Flannel CNI and `kube-proxy`.
- `patches/controlplane-N.yaml`: hostname, static address, interface, and VIP.
- `rendered/controlplane-N.yaml`: sensitive, complete configuration to apply.

The base and rendered files contain private keys and must stay private.

## Render and validate

```sh
./talos/render-configs.sh
```

## Nodes

- `controlplane-1`: installed at `192.168.187.201` on `eno1`.
- `controlplane-2`: installed at `192.168.187.202` on `eno2`.
- `controlplane-3`: installed at `192.168.187.203` on `eno2`, MAC
  `14:18:77:43:34:ec`.

Do not bootstrap additional nodes. Bootstrap the cluster exactly once through
`controlplane-1`; the other control-plane nodes join automatically.

## Cluster networking

Cilium is installed separately from `infrastructure/cilium` during bootstrap.
The Talos machine configuration sets the built-in CNI to `none` and disables
`kube-proxy`. It is therefore expected for nodes to remain `NotReady` after an
etcd bootstrap until `bootstrap/install-cilium.sh` completes successfully.

## Reinstall controlplane-3 from maintenance mode

If the third server is booted into maintenance mode again, apply its rendered
configuration to the temporary DHCP address:

```sh
talosctl apply-config \
  --insecure \
  --nodes 192.168.187.141 \
  --endpoints 192.168.187.141 \
  --file talos/rendered/controlplane-3.yaml
```
