# Infrastructure

Shared Kubernetes services and controllers belong here, for example ingress,
certificate management, storage, DNS, observability, and secrets management.

- `cilium/`: cluster networking, eBPF service load balancing, and Hubble.
- `cloudnative-pg/`: PostgreSQL operator, CRDs, and admission webhooks.
- `container-registry-image-pulls.md`: Talos networking, TLS trust, and authentication requirements for private registry pulls.
- `github-arc/`: ephemeral GitHub Actions runners managed by ARC.
- `longhorn/`: replicated persistent storage managed by Argo CD.
- `metrics-server/`: Kubernetes Resource Metrics API for `kubectl top` and Homepage.
- `monitoring/`: Prometheus, Grafana, Loki, and Alloy observability stack.
- `netbird/`: private cluster access plus Terraform-managed NetBird Cloud services.
- `registry/`: private Zot OCI registry with Cilium L2 exposure and Longhorn storage.
