#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
kubeconfig=${KUBECONFIG:-"$repo_dir/.local/kubeconfig"}
values_file="$repo_dir/infrastructure/cilium/values.yaml"
chart_version=${CILIUM_CHART_VERSION:-1.20.0}

command -v helm >/dev/null 2>&1 || {
    echo "helm is required" >&2
    exit 1
}

test -r "$kubeconfig" || {
    echo "kubeconfig is not readable: $kubeconfig" >&2
    exit 1
}

test -r "$values_file" || {
    echo "Cilium values are not readable: $values_file" >&2
    exit 1
}

export KUBECONFIG="$kubeconfig"

helm repo add cilium https://helm.cilium.io/ --force-update
helm repo update cilium
helm upgrade --install cilium cilium/cilium \
    --version "$chart_version" \
    --namespace kube-system \
    --values "$values_file" \
    --wait \
    --timeout 10m
