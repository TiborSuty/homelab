# Infrastructure

Shared Kubernetes services and controllers belong here, for example ingress,
certificate management, storage, DNS, observability, and secrets management.

- `cilium/`: cluster networking, eBPF service load balancing, and Hubble.
- `cloudnative-pg/`: PostgreSQL operator, CRDs, and admission webhooks.
- `longhorn/`: replicated persistent storage managed by Argo CD.
- `monitoring/`: Prometheus, Grafana, Loki, and Alloy observability stack.
