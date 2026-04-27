#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
stack_dir="$repo_root/stacks/public-gateway"
env_file="$stack_dir/.env.local"

if [[ ! -f "$env_file" ]]; then
  bash "$repo_root/scripts/setup_public_gateway_auth.sh" >/dev/null
fi

# shellcheck disable=SC1090
source "$env_file"

PUBLIC_BASE_DOMAIN="${PUBLIC_BASE_DOMAIN:-shulaiyun.top}"
PUBLIC_GATEWAY_PORT="${PUBLIC_GATEWAY_PORT:-18088}"
PUBLIC_GATEWAY_USER="${PUBLIC_GATEWAY_USER:-sloth}"
PUBLIC_ORIGIN_HOST="${PUBLIC_ORIGIN_HOST:-host.docker.internal}"
CLOUDFLARE_API_TOKEN="${CLOUDFLARE_API_TOKEN:-}"
OPERATOR_CLOUDFLARE_API_TOKEN="${OPERATOR_CLOUDFLARE_API_TOKEN:-}"

if [[ "${1:-}" == "--generate" ]]; then
  new_password="$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 24)"
  echo "Generated new password: $new_password"
else
  read -r -s -p "New password for https://ops.$PUBLIC_BASE_DOMAIN: " new_password
  echo
  read -r -s -p "Confirm new password: " confirm_password
  echo

  if [[ "$new_password" != "$confirm_password" ]]; then
    echo "Passwords do not match." >&2
    exit 1
  fi
fi

if [[ -z "$new_password" ]]; then
  echo "Password cannot be empty." >&2
  exit 1
fi

quote_env() {
  printf '%q' "$1"
}

umask 077
{
  printf 'PUBLIC_BASE_DOMAIN=%s\n' "$(quote_env "$PUBLIC_BASE_DOMAIN")"
  printf 'PUBLIC_GATEWAY_PORT=%s\n' "$(quote_env "$PUBLIC_GATEWAY_PORT")"
  printf 'PUBLIC_GATEWAY_USER=%s\n' "$(quote_env "$PUBLIC_GATEWAY_USER")"
  printf 'PUBLIC_GATEWAY_PASSWORD=%s\n' "$(quote_env "$new_password")"
  printf 'PUBLIC_ORIGIN_HOST=%s\n' "$(quote_env "$PUBLIC_ORIGIN_HOST")"

  if [[ -n "$CLOUDFLARE_API_TOKEN" ]]; then
    printf 'CLOUDFLARE_API_TOKEN=%s\n' "$(quote_env "$CLOUDFLARE_API_TOKEN")"
  fi

  if [[ -n "$OPERATOR_CLOUDFLARE_API_TOKEN" ]]; then
    printf 'OPERATOR_CLOUDFLARE_API_TOKEN=%s\n' "$(quote_env "$OPERATOR_CLOUDFLARE_API_TOKEN")"
  fi
} > "$env_file"

bash "$repo_root/scripts/setup_public_gateway_auth.sh" >/dev/null
bash "$repo_root/scripts/start_public_gateway.sh" >/dev/null
bash "$repo_root/scripts/check_public_gateway.sh"

echo
echo "Homepage password updated."
echo "URL: https://ops.$PUBLIC_BASE_DOMAIN"
echo "Username: $PUBLIC_GATEWAY_USER"
