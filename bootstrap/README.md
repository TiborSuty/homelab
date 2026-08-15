# Bootstrap

Cluster bootstrap definitions belong here. Cilium is installed first because
the Kubernetes nodes need a working CNI before a future GitOps controller can
run.

```sh
./bootstrap/install-cilium.sh
```

A future GitOps controller will become the entry point for the remaining
infrastructure and application definitions.
