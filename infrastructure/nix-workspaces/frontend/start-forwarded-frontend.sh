#!/bin/sh
set -eu

app=${1:?Expected dms or iam}
case "$app" in
  dms) port=4200; mac_port=5200 ;;
  iam) port=4201; mac_port=5201 ;;
  *) echo "Unknown frontend: $app" >&2; exit 1 ;;
esac

project=/workspace/home/projects/frontend-monorepo
while [ ! -f /workspace/home/.frontend-ready ] || [ ! -s "$project/apps/$app/.env" ]; do
  sleep 5
done
cd "$project"
export NX_DAEMON=false
# Do not reuse persistent task records containing PIDs from an earlier container.
export NX_WORKSPACE_DATA_DIRECTORY="/tmp/nx-$app-workspace-data"
exec ./node_modules/.bin/nx serve "$app" --host=0.0.0.0 --port="$port" \
  --publicHost="ws://localhost:$mac_port/ws"
