# Metrics Server

Metrics Server provides the Kubernetes Resource Metrics API used by `kubectl
top`, autoscaling, and Homepage's Kubernetes CPU and memory widget. It is
deployed from the official Metrics Server Helm chart and monitored by the
existing Prometheus stack.

Verify it after deployment:

```sh
KUBECONFIG="$PWD/.local/kubeconfig" kubectl top nodes
KUBECONFIG="$PWD/.local/kubeconfig" kubectl top pods -A
```
