#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
kubeconfig=${KUBECONFIG:-"$repo_dir/.local/kubeconfig"}
manifests_dir="$repo_dir/bootstrap/argocd"
root_application="$repo_dir/bootstrap/root-application.yaml"

command -v kubectl >/dev/null 2>&1 || {
    echo "kubectl is required" >&2
    exit 1
}

test -r "$kubeconfig" || {
    echo "kubeconfig is not readable: $kubeconfig" >&2
    exit 1
}

test -r "$manifests_dir/kustomization.yaml" || {
    echo "Argo CD kustomization is not readable" >&2
    exit 1
}

test -r "$root_application" || {
    echo "Root Application is not readable: $root_application" >&2
    exit 1
}

export KUBECONFIG="$kubeconfig"

kubectl apply --server-side --force-conflicts -k "$manifests_dir"
kubectl wait \
    --for=condition=Established \
    crd/applications.argoproj.io \
    --timeout=2m
kubectl wait \
    --namespace argocd \
    --for=condition=Available \
    deployment \
    --all \
    --timeout=5m
kubectl rollout status \
    --namespace argocd \
    statefulset/argocd-application-controller \
    --timeout=5m
kubectl apply -f "$root_application"
