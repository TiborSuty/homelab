#!/bin/sh
set -eu
test "$(id -u)" = 1000
docker version --format 'Client {{.Client.Version}} / Engine {{.Server.Version}}'
docker compose version
docker buildx version
check_dir=$(mktemp -d "$HOME/docker-smoke.XXXXXX")
check_project=$(basename "$check_dir" | tr '[:upper:].' '[:lower:]-')
cleanup() {
  if [ -f "$check_dir/compose.yaml" ]; then
    docker compose -p "$check_project" -f "$check_dir/compose.yaml" down --volumes --remove-orphans || true
  fi
  docker image rm "$check_project:check" >/dev/null 2>&1 || true
  rm -rf "$check_dir"
}
trap cleanup EXIT
mkdir "$check_dir/public"
printf 'DOCKER_WORKSPACE_OK\n' > "$check_dir/public/index.html"
docker pull busybox:1.37.0
base_image=$(docker image inspect busybox:1.37.0 --format '{{index .RepoDigests 0}}')
printf 'FROM %s\nCOPY public/ /www/\n' "$base_image" > "$check_dir/Dockerfile"
docker build --progress=plain -t "$check_project:check" "$check_dir"
cat > "$check_dir/compose.yaml" <<YAML
services:
  web:
    image: $check_project:check
    command: [httpd, -f, -p, "8080", -h, /www]
    ports: ["127.0.0.1:18080:8080"]
    volumes:
      - ./public:/www:ro
      - data:/data
    healthcheck:
      test: [CMD, wget, -q, -O, /dev/null, http://127.0.0.1:8080/]
      interval: 2s
      timeout: 2s
      retries: 15
volumes:
  data: {}
YAML
docker compose -p "$check_project" -f "$check_dir/compose.yaml" up -d --wait
# Test published ports with the client's native HTTP tool.
if command -v curl >/dev/null; then
  test "$(curl -fsS http://127.0.0.1:18080/)" = DOCKER_WORKSPACE_OK
else
  test "$(wget -qO- http://127.0.0.1:18080/)" = DOCKER_WORKSPACE_OK
fi
test "$(docker run --rm --network "${check_project}_default" "$base_image" wget -qO- http://web:8080/)" = DOCKER_WORKSPACE_OK
docker compose -p "$check_project" -f "$check_dir/compose.yaml" exec -T --interactive=false web sh -c 'echo persisted > /data/check'
docker compose -p "$check_project" -f "$check_dir/compose.yaml" down
docker compose -p "$check_project" -f "$check_dir/compose.yaml" up -d --wait
test "$(docker compose -p "$check_project" -f "$check_dir/compose.yaml" exec -T --interactive=false web cat /data/check)" = persisted
printf 'PASS: non-root Docker, Buildx, Compose, source bind mounts, published ports, service DNS, and volume persistence\n'
