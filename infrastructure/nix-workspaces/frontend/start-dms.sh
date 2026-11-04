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
exec ./node_modules/.bin/nx serve dms --host=0.0.0.0 --port=4300
