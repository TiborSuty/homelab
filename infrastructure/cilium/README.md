# Cilium

Cilium is the cluster's only CNI and replaces `kube-proxy` with its eBPF
service load balancer. The Helm release is installed during cluster bootstrap
because Kubernetes nodes cannot become Ready before a CNI is available.

The chart version is pinned in `bootstrap/install-cilium.sh`; deployment values
are kept in `values.yaml`.

After installation, verify the release with:

```sh
export KUBECONFIG="$PWD/.local/kubeconfig"
helm status cilium --namespace kube-system
cilium status --wait
cilium connectivity test \
  --namespace-labels pod-security.kubernetes.io/enforce=privileged
```

The elevated Pod Security label applies only to the temporary connectivity-test
namespaces. Remove all test resources afterwards with:

```sh
cilium connectivity test --cleanup
```
