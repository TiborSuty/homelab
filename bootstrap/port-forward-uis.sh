#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(dirname "$script_dir")
kubeconfig_path=${KUBECONFIG:-"$repository_root/.local/kubeconfig"}
forward_pids=""

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required" >&2
  exit 1
fi

if [ ! -f "$kubeconfig_path" ]; then
  echo "Kubeconfig not found: $kubeconfig_path" >&2
  exit 1
fi

start_forward() {
  namespace=$1
  service=$2
  ports=$3

  kubectl --kubeconfig "$kubeconfig_path" -n "$namespace" port-forward \
    --address=127.0.0.1 "svc/$service" "$ports" &
  forward_pids="$forward_pids $!"
}

stop_forwards() {
  trap - EXIT INT TERM
  if [ -n "$forward_pids" ]; then
    # The list contains only PIDs created by this script.
    # shellcheck disable=SC2086
    kill $forward_pids 2>/dev/null || true
    # shellcheck disable=SC2086
    wait $forward_pids 2>/dev/null || true
  fi
}

trap stop_forwards EXIT INT TERM

start_forward homepage homepage 3001:3000
start_forward argocd argocd-server 8080:443
start_forward longhorn-system longhorn-frontend 8081:80
start_forward kube-system hubble-ui 12000:80
start_forward monitoring monitoring-grafana 3000:80
start_forward monitoring monitoring-kube-prometheus-prometheus 9090:9090
start_forward monitoring monitoring-kube-prometheus-alertmanager 9093:9093
start_forward minio minio-console 9001:9001

echo "Homepage:    http://localhost:3001"
echo "Argo CD:     https://localhost:8080"
echo "Longhorn:    http://localhost:8081"
echo "Hubble:      http://localhost:12000"
echo "Grafana:     http://localhost:3000"
echo "Prometheus:  http://localhost:9090"
echo "Alertmanager:http://localhost:9093"
echo "MinIO:       http://localhost:9001"
echo "Press Ctrl-C to stop all forwards."

wait
