#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
stack_dir="$repo_root/stacks/public-gateway"
env_file="$stack_dir/.env.local"
routes_file="$stack_dir/data/routes.yaml"

if [[ ! -f "$env_file" || ! -f "$routes_file" ]]; then
  bash "$repo_root/scripts/setup_public_gateway_auth.sh"
fi

docker compose --env-file "$env_file" -f "$stack_dir/compose.yaml" up -d
docker compose --env-file "$env_file" -f "$stack_dir/compose.yaml" ps

echo
echo "Public gateway is listening locally on:"
awk -F= '/PUBLIC_GATEWAY_PORT/ { print "  http://127.0.0.1:" $2 }' "$env_file"
echo
echo "Cloudflare Tunnel should point public hostnames to:"
awk -F= '/PUBLIC_GATEWAY_PORT/ { print "  http://host.docker.internal:" $2 }' "$env_file"
