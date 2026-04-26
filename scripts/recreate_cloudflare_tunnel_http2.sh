#!/usr/bin/env bash
set -euo pipefail

container_name="${CLOUDFLARED_CONTAINER:-sloth-cloud-local-tunnel}"
image="${CLOUDFLARED_IMAGE:-cloudflare/cloudflared:latest}"

if ! docker inspect "$container_name" >/dev/null 2>&1; then
  echo "Container not found: $container_name" >&2
  exit 1
fi

token="$(
  docker inspect "$container_name" --format '{{json .Config.Cmd}}' |
    python3 -c 'import json,sys; cmd=json.load(sys.stdin); print(cmd[cmd.index("--token")+1])'
)"

if [ -z "$token" ]; then
  echo "Could not extract tunnel token from $container_name" >&2
  exit 1
fi

docker rm -f "$container_name" >/dev/null
docker run -d \
  --name "$container_name" \
  --restart unless-stopped \
  --add-host=host.docker.internal:host-gateway \
  "$image" \
  tunnel --no-autoupdate --protocol http2 run --token "$token" >/dev/null

unset token

echo "Recreated $container_name with cloudflared protocol=http2."
echo "Checking recent tunnel logs:"
sleep 5
docker logs --tail=40 "$container_name" 2>&1 | sed -E 's/[A-Za-z0-9_-]{80,}/[REDACTED]/g'
