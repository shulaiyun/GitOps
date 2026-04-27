#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
stack_dir="$repo_root/stacks/public-gateway"
env_file="$stack_dir/.env.local"

if [[ ! -f "$env_file" ]]; then
  echo "Missing $env_file. Run scripts/start_public_gateway.sh first." >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$env_file"

base="http://127.0.0.1:${PUBLIC_GATEWAY_PORT:-18088}"
auth="${PUBLIC_GATEWAY_USER}:${PUBLIC_GATEWAY_PASSWORD}"

echo "== Public gateway auth policy =="
while IFS='|' read -r host route_path expected
do
  echo "---- $host$route_path"
  code="$(curl --noproxy '*' -sS -o /dev/null --max-time 8 -H "Host: $host" \
    -w "%{http_code}" \
    "$base$route_path" || true)"

  if [[ "$code" != "$expected" ]]; then
    echo "status=$code expected=$expected"
    exit 1
  fi

  echo "status=$code expected=$expected"
done <<EOF
ops.$PUBLIC_BASE_DOMAIN|/|401
argo-ops.$PUBLIC_BASE_DOMAIN|/|200
cloud-ops.$PUBLIC_BASE_DOMAIN|/|200
api-ops.$PUBLIC_BASE_DOMAIN|/api/v1/health|200
uptime-ops.$PUBLIC_BASE_DOMAIN|/dashboard|200
beszel-ops.$PUBLIC_BASE_DOMAIN|/|200
EOF

echo
echo "== Public gateway authenticated reachability =="
while read -r host path
do
  echo "---- $host"
  curl --noproxy '*' -sS -o /dev/null --max-time 8 -u "$auth" -H "Host: $host" \
    -w "status=%{http_code} content_type=%{content_type}\n" \
    "$base$path" || true
done <<EOF
ops.$PUBLIC_BASE_DOMAIN /
home-ops.$PUBLIC_BASE_DOMAIN /
argo.ops.$PUBLIC_BASE_DOMAIN /
argo-ops.$PUBLIC_BASE_DOMAIN /
dockge.ops.$PUBLIC_BASE_DOMAIN /
dockge-ops.$PUBLIC_BASE_DOMAIN /
uptime.ops.$PUBLIC_BASE_DOMAIN /
uptime-ops.$PUBLIC_BASE_DOMAIN /
beszel.ops.$PUBLIC_BASE_DOMAIN /
beszel-ops.$PUBLIC_BASE_DOMAIN /
traefik.ops.$PUBLIC_BASE_DOMAIN /dashboard/
traefik-ops.$PUBLIC_BASE_DOMAIN /dashboard/
cloud.ops.$PUBLIC_BASE_DOMAIN /
cloud-ops.$PUBLIC_BASE_DOMAIN /
api.ops.$PUBLIC_BASE_DOMAIN /api/v1/health
api-ops.$PUBLIC_BASE_DOMAIN /api/v1/health
paymenter.ops.$PUBLIC_BASE_DOMAIN /
paymenter-ops.$PUBLIC_BASE_DOMAIN /
xboard.ops.$PUBLIC_BASE_DOMAIN /
xboard-ops.$PUBLIC_BASE_DOMAIN /
cloud-lab.ops.$PUBLIC_BASE_DOMAIN /
cloud-lab-ops.$PUBLIC_BASE_DOMAIN /
api-lab.ops.$PUBLIC_BASE_DOMAIN /api/v1/health
api-lab-ops.$PUBLIC_BASE_DOMAIN /api/v1/health
convoy.ops.$PUBLIC_BASE_DOMAIN /
convoy-ops.$PUBLIC_BASE_DOMAIN /
EOF
