#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="$ROOT_DIR/stacks/platform-core/compose.yaml"
BESZEL_DATA_DIR="$ROOT_DIR/stacks/platform-core/data/beszel"
AGENT_DATA_DIR="$ROOT_DIR/stacks/platform-core/data/beszel-agent"
AGENT_ENV_FILE="$AGENT_DATA_DIR/agent.env"
DB_FILE="$BESZEL_DATA_DIR/data.db"
KEY_FILE="$BESZEL_DATA_DIR/id_ed25519"
LISTEN_PATH="${BESZEL_AGENT_LISTEN:-/beszel_socket/beszel.sock}"
HUB_URL="http://localhost:${BESZEL_PORT:-15004}"

if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "sqlite3 is required to provision the Beszel local agent." >&2
  exit 1
fi

if ! command -v ssh-keygen >/dev/null 2>&1; then
  echo "ssh-keygen is required to extract the Beszel public key." >&2
  exit 1
fi

if ! command -v openssl >/dev/null 2>&1; then
  echo "openssl is required to generate a Beszel universal token." >&2
  exit 1
fi

if [ ! -f "$DB_FILE" ]; then
  echo "Beszel database not found at $DB_FILE" >&2
  exit 1
fi

if [ ! -f "$KEY_FILE" ]; then
  echo "Beszel hub key not found at $KEY_FILE" >&2
  exit 1
fi

user_id="$(sqlite3 "$DB_FILE" "select id from users where role = 'admin' order by created limit 1;")"
if [ -z "$user_id" ]; then
  user_id="$(sqlite3 "$DB_FILE" "select id from users order by created limit 1;")"
fi

if [ -z "$user_id" ]; then
  echo "No Beszel user found. Sign in to Beszel once, then re-run this script." >&2
  exit 1
fi

public_key="$(ssh-keygen -y -f "$KEY_FILE")"
token="$(sqlite3 "$DB_FILE" "select token from universal_tokens where user = '$user_id' limit 1;")"

if [ -z "$token" ]; then
  token="$(openssl rand -hex 16)"
  sqlite3 "$DB_FILE" "insert into universal_tokens (token, user) values ('$token', '$user_id')
    on conflict(user) do update set token = excluded.token;"
fi

mkdir -p "$AGENT_DATA_DIR"

cat > "$AGENT_ENV_FILE" <<EOF
KEY=$public_key
TOKEN=$token
LISTEN=$LISTEN_PATH
HUB_URL=$HUB_URL
EOF

chmod 600 "$AGENT_ENV_FILE"

docker compose -f "$COMPOSE_FILE" --profile agent up -d beszel-agent
sleep 3

echo "Beszel local agent configured."
echo "Agent env: $AGENT_ENV_FILE"
echo "Hub URL: $HUB_URL"
echo "Socket path: $LISTEN_PATH"
echo
echo "Known systems:"
sqlite3 "$DB_FILE" "select id, name, host, status, updated from systems order by updated desc;"
