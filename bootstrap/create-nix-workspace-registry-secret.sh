#!/bin/sh
set -eu
set +x

repository_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
kubeconfig_path=${KUBECONFIG:-"$repository_root/.local/kubeconfig"}
credentials_path=${REGISTRY_CREDENTIALS_FILE:-"$repository_root/.local/registry.env"}

# shellcheck disable=SC1090
. "$credentials_path"
: "${WORKSPACE_REGISTRY_PULL_PASSWORD:?Run bootstrap/create-registry-secrets.sh first}"
umask 077
temp_dir=$(mktemp -d)
trap 'rm -rf "$temp_dir"; unset WORKSPACE_REGISTRY_PULL_PASSWORD' 0
trap 'exit 1' 1 2 15
WORKSPACE_REGISTRY_PULL_PASSWORD="$WORKSPACE_REGISTRY_PULL_PASSWORD" \
  python3 - "$temp_dir/config.json" <<'PY'
import base64
import json
import os
import sys

auth = base64.b64encode(
    ("nix-workspaces-pull:" + os.environ["WORKSPACE_REGISTRY_PULL_PASSWORD"]).encode()
).decode()
with open(sys.argv[1], "w") as output:
    json.dump({"auths": {"registry.homelab.internal": {"auth": auth}}}, output)
PY
kubectl --kubeconfig "$kubeconfig_path" apply \
  -f "$repository_root/infrastructure/nix-workspaces/namespace.yaml"
kubectl --kubeconfig "$kubeconfig_path" -n nix-workspaces \
  create secret generic workspace-registry-pull \
  --type=kubernetes.io/dockerconfigjson \
  --from-file=".dockerconfigjson=$temp_dir/config.json" --dry-run=client -o yaml | \
  kubectl --kubeconfig "$kubeconfig_path" -n nix-workspaces apply -f -
