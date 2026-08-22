# Monitoring

The monitoring stack consists of:

- Prometheus Operator, Prometheus, Alertmanager, kube-state-metrics, and node
  exporter from `kube-prometheus-stack`.
- Grafana with provisioned Prometheus and Loki data sources.
- Loki in monolithic mode with local filesystem storage on a Longhorn volume.
- Grafana Alloy as a DaemonSet that reads Kubernetes container logs on each
  node and sends them to Loki.
- ARC controller and runner-set listener metrics collected through the
  `github-arc` PodMonitor.

Prometheus retains up to 15 days or 15 GiB of metrics on a 20 Gi Longhorn PVC.
Loki retains seven days of logs on a 20 Gi Longhorn PVC. Grafana uses a 5 Gi
Longhorn PVC and Alertmanager uses 2 Gi.

The control-plane metrics for etcd, controller-manager, and scheduler are
disabled because Talos does not expose those endpoints by default. kube-proxy
metrics are disabled because Cilium replaces kube-proxy in this cluster.

## Grafana credentials

Create the ignored local credentials file and Kubernetes Secret before the
first Argo CD sync:

```sh
./bootstrap/create-grafana-secret.sh
```

The credentials are stored in `.local/grafana.env` with mode `600`.

## Grafana UI

Grafana is permanently available from the trusted home LAN through any cluster
node:

- <http://192.168.187.201:30300>
- <http://192.168.187.202:30300>
- <http://192.168.187.203:30300>

All three addresses route to the same Grafana Service. This uses plain HTTP and
should remain LAN-only; do not forward port `30300` on the router.

For localhost-only access, port forwarding remains available:

```sh
KUBECONFIG="$PWD/.local/kubeconfig" \
  kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80
```

Sign in with the values from `.local/grafana.env`. Prometheus is the default
data source; Loki is available for log queries in Explore.

## GitHub ARC metrics

The ARC controller and runner-set listeners expose Prometheus metrics on port
`8080`. Useful queries include:

```promql
gha_controller_running_listeners
gha_running_jobs
gha_busy_runners
gha_desired_runners
gha_failed_ephemeral_runners
histogram_quantile(0.95, sum by (le) (rate(gha_job_startup_duration_seconds_bucket[5m])))
```
