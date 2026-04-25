#!/usr/bin/env bash

set -euo pipefail

ENV_FILE="${ENV_FILE:-/Users/shulai/iCloud云盘（归档）/Documents/New project/vps/runtime/env/api.env}"
NAMESPACE="${NAMESPACE:-sloth-labs}"
SECRET_NAME="${SECRET_NAME:-sloth-cloud-api-lab-secrets}"

REQUIRED_KEYS=(
  CONVOY_APPLICATION_KEY
  MANAGED_APP_INTERNAL_API_TOKEN
  ASSISTANT_OPENAI_API_KEY
  ASSISTANT_GEMINI_API_KEY
  ASSISTANT_CLAUDE_API_KEY
  ASSISTANT_QUOTA_COOKIE_SECRET
  OPERATOR_CLOUDFLARE_API_TOKEN
  OPERATOR_MONITORING_WEBHOOK_SECRET
)

if [ ! -f "$ENV_FILE" ]; then
  echo "Env file not found: $ENV_FILE" >&2
  exit 1
fi

tmp_file="$(mktemp)"
trap 'rm -f "$tmp_file"' EXIT

missing=()
for key in "${REQUIRED_KEYS[@]}"; do
  value="$(
    awk -v key="$key" '
      index($0, key "=") == 1 {
        sub("^[^=]*=", "")
        print
        found = 1
        exit
      }
      END {
        if (!found) {
          exit 1
        }
      }
    ' "$ENV_FILE" || true
  )"

  if [ -z "$value" ]; then
    missing+=("$key")
  else
    printf '%s=%s\n' "$key" "$value" >> "$tmp_file"
  fi
done

if [ "${#missing[@]}" -gt 0 ]; then
  echo "Missing required secret keys in $ENV_FILE:" >&2
  printf '  %s\n' "${missing[@]}" >&2
  exit 1
fi

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$NAMESPACE" create secret generic "$SECRET_NAME" \
  --from-env-file="$tmp_file" \
  --dry-run=client \
  -o yaml | kubectl apply -f -

echo "Seeded Kubernetes Secret $NAMESPACE/$SECRET_NAME with ${#REQUIRED_KEYS[@]} keys."
