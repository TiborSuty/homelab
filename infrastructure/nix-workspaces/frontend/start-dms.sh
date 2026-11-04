#!/bin/sh
set -eu

project=/workspace/home/projects/frontend-monorepo
while [ ! -f /workspace/home/.frontend-ready ]; do
  sleep 5
done
cd "$project"
umask 077
install -m 600 /run/project-environment/dms.env apps/dms/.env
export NX_DAEMON=false
# Running-task records contain PIDs, which are reused after container restart.
# Keep that database in the container layer rather than the persistent home.
export NX_WORKSPACE_DATA_DIRECTORY=/tmp/nx-dms-workspace-data
exec ./node_modules/.bin/nx serve dms --host=0.0.0.0 --port=4300
