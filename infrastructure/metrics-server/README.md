# Metrics Server

Metrics Server provides the Kubernetes Resource Metrics API used by `kubectl
top`, autoscaling, and Homepage's Kubernetes CPU and memory widget. It is
deployed from the official Metrics Server Helm chart and monitored by the
existing Prometheus stack.

Talos' default kubelet serving certificates do not contain node IP SANs. The
chart therefore uses `--kubelet-insecure-tls` for the internal connection from
Metrics Server to the three kubelets. A future hardening step can replace this
with kubelet serving-certificate rotation and an automatic CSR approver.

Verify it after deployment:

```sh
KUBECONFIG="$PWD/.local/kubeconfig" kubectl top nodes
KUBECONFIG="$PWD/.local/kubeconfig" kubectl top pods -A
```
