# CloudNativePG

CloudNativePG manages PostgreSQL clusters across the Kubernetes cluster. Argo CD
deploys the official `cloudnative-pg` Helm chart into `cnpg-system` and keeps the
operator, CRDs, RBAC, and admission webhooks synchronized.

- Helm chart: `0.29.0`
- CloudNativePG operator: `1.30.0`
- Scope: cluster-wide
- Operator replicas: `1`

The operator is separate from PostgreSQL workloads. Each database cluster must
be declared independently with its PostgreSQL version, instance count, storage,
resources, users, and backup policy.

`PodMonitor` and the Grafana dashboard are disabled until a Prometheus Operator
based monitoring stack is installed.

## Verify the operator

```sh
KUBECONFIG="$PWD/.local/kubeconfig" \
  kubectl -n cnpg-system rollout status deployment/cloudnative-pg

KUBECONFIG="$PWD/.local/kubeconfig" \
  kubectl get crd clusters.postgresql.cnpg.io
```
