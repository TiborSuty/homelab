#!/usr/bin/env bash
set -euo pipefail
nx_package=$1
"$nx_package/bin/nx" --version
node - "$nx_package" <<'JS'
const assert = require('node:assert');
const pkg = process.argv[2] + '/lib/node_modules/nx';
assert.equal(require(pkg + '/package.json').version, '23.2.1');
const native = require(pkg + '/dist/src/native');
assert(Object.keys(native).length > 10, 'Native binding did not export its API');
console.log('PASS: Nx native bindings loaded');
JS
nx_test_dir=$(mktemp -d)
trap 'rm -rf "$nx_test_dir"' EXIT
mkdir -p "$nx_test_dir/node_modules"
ln -s "$nx_package/lib/node_modules/nx" "$nx_test_dir/node_modules/nx"
cat > "$nx_test_dir/package.json" <<'JSON'
{"name":"nix-nx-smoke","private":true,"devDependencies":{"nx":"23.2.1"}}
JSON
printf '{}\n' > "$nx_test_dir/nx.json"
cat > "$nx_test_dir/project.json" <<'JSON'
{"name":"nix-nx-smoke","targets":{"check":{"command":"node -e \"console.log('NX_NIX_OK')\""}}}
JSON
cd "$nx_test_dir"
NX_DAEMON=false NX_NO_CLOUD=true CI=true "$nx_package/bin/nx" run nix-nx-smoke:check --skip-nx-cache
printf 'PASS: pinned global Nx executes a workspace task\n'
