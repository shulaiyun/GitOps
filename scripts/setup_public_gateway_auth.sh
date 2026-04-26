#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
stack_dir="$repo_root/stacks/public-gateway"
template="$stack_dir/config/routes.yaml.template"
data_dir="$stack_dir/data"
env_file="$stack_dir/.env.local"
generated_routes="$data_dir/routes.yaml"
urls_file="$data_dir/public-urls.txt"

mkdir -p "$data_dir"

if [[ -f "$env_file" ]]; then
  # shellcheck disable=SC1090
  source "$env_file"
fi

PUBLIC_BASE_DOMAIN="${PUBLIC_BASE_DOMAIN:-shulaiyun.top}"
PUBLIC_GATEWAY_PORT="${PUBLIC_GATEWAY_PORT:-18088}"
PUBLIC_GATEWAY_USER="${PUBLIC_GATEWAY_USER:-sloth}"
PUBLIC_GATEWAY_PASSWORD="${PUBLIC_GATEWAY_PASSWORD:-}"

if [[ -z "$PUBLIC_GATEWAY_PASSWORD" ]]; then
  PUBLIC_GATEWAY_PASSWORD="$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 24)"
fi

password_hash="$(openssl passwd -apr1 "$PUBLIC_GATEWAY_PASSWORD")"

cat > "$env_file" <<EOF
PUBLIC_BASE_DOMAIN=$PUBLIC_BASE_DOMAIN
PUBLIC_GATEWAY_PORT=$PUBLIC_GATEWAY_PORT
PUBLIC_GATEWAY_USER=$PUBLIC_GATEWAY_USER
PUBLIC_GATEWAY_PASSWORD=$PUBLIC_GATEWAY_PASSWORD
EOF

python3 - "$template" "$generated_routes" "$PUBLIC_BASE_DOMAIN" "$PUBLIC_GATEWAY_USER" "$password_hash" <<'PY'
import sys
from pathlib import Path

template, output, domain, user, password_hash = sys.argv[1:]
text = Path(template).read_text()
text = text.replace("{{PUBLIC_BASE_DOMAIN}}", domain)
text = text.replace("{{PUBLIC_GATEWAY_USER}}", user)
text = text.replace("{{PUBLIC_GATEWAY_PASSWORD_HASH}}", password_hash)
Path(output).write_text(text)
PY

cat > "$urls_file" <<EOF
Public gateway local test URL:
  http://127.0.0.1:$PUBLIC_GATEWAY_PORT

Cloudflare Tunnel origin service:
  http://host.docker.internal:$PUBLIC_GATEWAY_PORT

Public hostnames to create:
  https://ops.$PUBLIC_BASE_DOMAIN
  https://argo.ops.$PUBLIC_BASE_DOMAIN
  https://dockge.ops.$PUBLIC_BASE_DOMAIN
  https://uptime.ops.$PUBLIC_BASE_DOMAIN
  https://beszel.ops.$PUBLIC_BASE_DOMAIN
  https://traefik.ops.$PUBLIC_BASE_DOMAIN
  https://cloud.ops.$PUBLIC_BASE_DOMAIN
  https://api.ops.$PUBLIC_BASE_DOMAIN
  https://paymenter.ops.$PUBLIC_BASE_DOMAIN
  https://xboard.ops.$PUBLIC_BASE_DOMAIN
  https://cloud-lab.ops.$PUBLIC_BASE_DOMAIN
  https://api-lab.ops.$PUBLIC_BASE_DOMAIN
  https://convoy.ops.$PUBLIC_BASE_DOMAIN
EOF

echo "Public gateway config generated."
echo "Domain: $PUBLIC_BASE_DOMAIN"
echo "Local port: $PUBLIC_GATEWAY_PORT"
echo "Username: $PUBLIC_GATEWAY_USER"
echo "Password: $PUBLIC_GATEWAY_PASSWORD"
echo
echo "Generated files:"
echo "  $env_file"
echo "  $generated_routes"
echo "  $urls_file"
