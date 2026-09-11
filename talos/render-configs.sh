#!/bin/sh
set -eu

talos_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
base_config="$talos_dir/base/controlplane.yaml"
common_patch="$talos_dir/patches/common.yaml"
workloads_patch="$talos_dir/patches/controlplane-workloads.yaml"
cilium_patch="$talos_dir/patches/cilium.yaml"
registry_ca="$talos_dir/registry-ca.crt"

if [ ! -f "$registry_ca" ]; then
    echo "registry CA certificate not found: $registry_ca" >&2
    echo "run ./bootstrap/create-registry-secrets.sh first" >&2
    exit 1
fi

registry_patch=$(mktemp "${TMPDIR:-/tmp}/talos-registry.XXXXXX")
cleanup() {
    if [ -f "$registry_patch" ]; then
        unlink "$registry_patch"
    fi
}
trap cleanup 0 1 2 15

{
    cat <<'EOF'
apiVersion: v1alpha1
kind: StaticHostConfig
name: 192.168.187.211
hostnames:
    - registry.homelab.internal
---
apiVersion: v1alpha1
kind: RegistryTLSConfig
name: registry.homelab.internal
ca: |-
EOF
    sed 's/^/    /' "$registry_ca"
} >"$registry_patch"

render_node() {
    node_name=$1
    node_patch="$talos_dir/patches/$node_name.yaml"
    output_config="$talos_dir/rendered/$node_name.yaml"

    talosctl machineconfig patch "$base_config" \
        --patch "@$common_patch" \
        --patch "@$workloads_patch" \
        --patch "@$cilium_patch" \
        --patch "@$registry_patch" \
        --patch "@$node_patch" \
        --output "$output_config"

    chmod 600 "$output_config"
    talosctl validate --config "$output_config" --mode metal --strict
}

render_node controlplane-1
render_node controlplane-2

if [ -f "$talos_dir/patches/controlplane-3.yaml" ]; then
    render_node controlplane-3
fi
