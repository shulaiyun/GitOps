#!/usr/bin/env bash
set -euo pipefail

container_name="${CLOUDFLARED_CONTAINER:-sloth-cloud-local-tunnel}"
image="${CLOUDFLARED_IMAGE:-cloudflare/cloudflared:latest}"
protocol="${CLOUDFLARED_PROTOCOL:-http2}"
network="${CLOUDFLARED_NETWORK:-public-gateway_default}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
env_file="$repo_root/stacks/public-gateway/.env.local"
inventory_file="$repo_root/inventory/public-hostnames.yaml"

case "$protocol" in
  http2|quic|auto) ;;
  *)
    echo "Unsupported CLOUDFLARED_PROTOCOL: $protocol" >&2
    echo "Supported values: http2, quic, auto" >&2
    exit 2
    ;;
esac

read_env_value() {
  local key="$1"
  if [ ! -f "$env_file" ]; then
    return 1
  fi
  awk -F= -v key="$key" '$1 == key {print substr($0, length(key) + 2); exit}' "$env_file"
}

read_inventory_value() {
  local key="$1"
  ruby -ryaml -e 'data = YAML.load_file(ARGV[0]); value = data[ARGV[1]]; puts value if value' "$inventory_file" "$key"
}

extract_token_from_container() {
  docker inspect "$container_name" --format '{{json .Config.Cmd}}' |
    python3 -c 'import json,sys; cmd=json.load(sys.stdin); print(cmd[cmd.index("--token")+1])'
}

fetch_token_from_cloudflare() {
  local api_token="$1"
  local account_id="$2"
  local tunnel_id="$3"
  CLOUDFLARE_API_TOKEN="$api_token" python3 - "$account_id" "$tunnel_id" <<'PY'
import json
import os
import sys
import urllib.request

account_id, tunnel_id = sys.argv[1], sys.argv[2]
api_token = os.environ["CLOUDFLARE_API_TOKEN"]
url = f"https://api.cloudflare.com/client/v4/accounts/{account_id}/cfd_tunnel/{tunnel_id}/token"
req = urllib.request.Request(url, headers={"Authorization": f"Bearer {api_token}"})
with urllib.request.urlopen(req, timeout=30) as resp:
    data = json.loads(resp.read().decode())
if not data.get("success"):
    raise SystemExit(json.dumps(data, ensure_ascii=False, indent=2))
print(data["result"])
PY
}

token=""
if docker inspect "$container_name" >/dev/null 2>&1; then
  token="$(extract_token_from_container)"
else
  api_token="${CLOUDFLARE_API_TOKEN:-${OPERATOR_CLOUDFLARE_API_TOKEN:-$(read_env_value CLOUDFLARE_API_TOKEN || true)}}"
  account_id="${CLOUDFLARE_ACCOUNT_ID:-${OPERATOR_CLOUDFLARE_ACCOUNT_ID:-$(read_env_value CLOUDFLARE_ACCOUNT_ID || true)}}"
  tunnel_id="${CLOUDFLARE_TUNNEL_ID:-${OPERATOR_CLOUDFLARE_DEFAULT_TUNNEL_ID:-$(read_env_value CLOUDFLARE_TUNNEL_ID || true)}}"
  account_id="${account_id:-$(read_inventory_value cloudflare_account_id)}"
  tunnel_id="${tunnel_id:-$(read_inventory_value cloudflare_tunnel_id)}"
  if [ -z "$api_token" ] || [ -z "$account_id" ] || [ -z "$tunnel_id" ]; then
    echo "Container not found and Cloudflare API fallback is missing token/account/tunnel configuration." >&2
    exit 1
  fi
  token="$(fetch_token_from_cloudflare "$api_token" "$account_id" "$tunnel_id")"
fi

if [ -z "$token" ]; then
  echo "Could not extract tunnel token from $container_name" >&2
  exit 1
fi

docker_run_args=(-d --name "$container_name" --restart unless-stopped)
network_note="host-gateway fallback"
if docker network inspect "$network" >/dev/null 2>&1; then
  docker_run_args+=(--network "$network")
  network_note="$network"
else
  docker_run_args+=(--add-host=host.docker.internal:host-gateway)
  echo "Docker network not found: $network. Falling back to host.docker.internal." >&2
fi

docker rm -f "$container_name" >/dev/null 2>&1 || true
docker run -d \
  "${docker_run_args[@]}" \
  "$image" \
  tunnel --no-autoupdate --protocol "$protocol" run --token "$token" >/dev/null

unset token

echo "Recreated $container_name with cloudflared protocol=$protocol network=$network_note."
echo "Checking recent tunnel logs:"
sleep 5
docker logs --tail=40 "$container_name" 2>&1 | sed -E 's/[A-Za-z0-9_-]{80,}/[REDACTED]/g'
