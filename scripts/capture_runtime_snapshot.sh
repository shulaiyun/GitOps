#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-$ROOT/inventory/runtime-snapshot.json}"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 1
fi

containers="$(docker ps -q)"

if [[ -z "$containers" ]]; then
  printf '{\n  "generated_at": null,\n  "containers": [],\n  "networks": [],\n  "volumes": []\n}\n' >"$OUT"
  echo "Wrote empty snapshot to $OUT"
  exit 0
fi

tmp_containers="$(mktemp)"
tmp_networks="$(mktemp)"
tmp_volumes="$(mktemp)"
trap 'rm -f "$tmp_containers" "$tmp_networks" "$tmp_volumes"' EXIT

docker inspect $containers | jq 'map({
  name: (.Name | ltrimstr("/")),
  image: .Config.Image,
  compose_project: .Config.Labels["com.docker.compose.project"],
  compose_service: .Config.Labels["com.docker.compose.service"],
  networks: ((.NetworkSettings.Networks // {}) | keys),
  mounts: [(.Mounts // [])[] | {
    type,
    source: .Source,
    destination: .Destination,
    name: .Name
  }],
  ports: [(.NetworkSettings.Ports // {}) | to_entries[]? | {
    container_port: .key,
    bindings: (.value // [])
  }]
})' >"$tmp_containers"

docker network ls --format '{{.Name}}' | jq -R -s 'split("\n") | map(select(length > 0))' >"$tmp_networks"
docker volume ls --format '{{.Name}}' | jq -R -s 'split("\n") | map(select(length > 0))' >"$tmp_volumes"

jq -n \
  --arg generated_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  --slurpfile containers "$tmp_containers" \
  --slurpfile networks "$tmp_networks" \
  --slurpfile volumes "$tmp_volumes" \
  '{
    generated_at: $generated_at,
    containers: $containers[0],
    networks: $networks[0],
    volumes: $volumes[0]
  }' >"$OUT"

echo "Wrote runtime snapshot to $OUT"
