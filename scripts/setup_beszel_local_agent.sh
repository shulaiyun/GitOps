#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="$ROOT_DIR/stacks/platform-core/compose.yaml"
BESZEL_DATA_DIR="$ROOT_DIR/stacks/platform-core/data/beszel"
AGENT_DATA_DIR="$ROOT_DIR/stacks/platform-core/data/beszel-agent"
AGENT_ENV_FILE="$AGENT_DATA_DIR/agent.env"
DB_FILE="$BESZEL_DATA_DIR/data.db"
KEY_FILE="$BESZEL_DATA_DIR/id_ed25519"
LISTEN_ADDR="${BESZEL_AGENT_LISTEN:-/beszel_socket/beszel.sock}"
AGENT_MODE="${BESZEL_AGENT_MODE:-ssh}"
HUB_URL="${BESZEL_AGENT_HUB_URL:-http://127.0.0.1:15004}"
SYSTEM_NAME="${BESZEL_SYSTEM_NAME:-colima}"

if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "sqlite3 is required to provision the Beszel local agent." >&2
  exit 1
fi

if ! command -v ssh-keygen >/dev/null 2>&1; then
  echo "ssh-keygen is required to extract the Beszel public key." >&2
  exit 1
fi

if [ "$AGENT_MODE" = "websocket" ] && ! command -v openssl >/dev/null 2>&1; then
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

mkdir -p "$AGENT_DATA_DIR"

case "$AGENT_MODE" in
  ssh)
    cat > "$AGENT_ENV_FILE" <<EOF
KEY=$public_key
LISTEN=$LISTEN_ADDR
EOF
    ;;
  websocket)
    token="$(sqlite3 "$DB_FILE" "select token from universal_tokens where user = '$user_id' limit 1;")"
    if [ -z "$token" ]; then
      token="$(openssl rand -hex 16)"
      sqlite3 "$DB_FILE" "insert into universal_tokens (token, user) values ('$token', '$user_id')
        on conflict(user) do update set token = excluded.token;"
    fi
    cat > "$AGENT_ENV_FILE" <<EOF
KEY=$public_key
TOKEN=$token
LISTEN=$LISTEN_ADDR
HUB_URL=$HUB_URL
EOF
    ;;
  *)
    echo "Unsupported BESZEL_AGENT_MODE: $AGENT_MODE. Use ssh or websocket." >&2
    exit 1
    ;;
esac

chmod 600 "$AGENT_ENV_FILE"

docker compose -f "$COMPOSE_FILE" --profile agent up -d --force-recreate beszel-agent
sleep 3

if [ "$AGENT_MODE" = "ssh" ] && [[ "$LISTEN_ADDR" = /* ]]; then
  docker compose -f "$COMPOSE_FILE" --profile agent stop beszel >/dev/null
  sqlite3 "$DB_FILE" "
    insert into systems (name, host, port, status, users, created, updated)
    select '$SYSTEM_NAME', '$LISTEN_ADDR', '', 'up', json_array('$user_id'), strftime('%Y-%m-%d %H:%M:%fZ','now'), strftime('%Y-%m-%d %H:%M:%fZ','now')
    where not exists (
      select 1 from systems
      where name = '$SYSTEM_NAME'
         or host = '$LISTEN_ADDR'
         or host = 'platform-beszel-agent'
    );
    update systems
      set host = '$LISTEN_ADDR',
          port = '',
          status = case when status = '' then 'up' else status end,
          users = case when users = '[]' or users = '' then json_array('$user_id') else users end,
          updated = strftime('%Y-%m-%d %H:%M:%fZ','now')
      where name = '$SYSTEM_NAME'
         or host = '$LISTEN_ADDR'
         or host = 'platform-beszel-agent'
         or name = 'colima';"
  docker compose -f "$COMPOSE_FILE" --profile agent up -d beszel >/dev/null
fi

echo "Beszel local agent configured."
echo "Agent env: $AGENT_ENV_FILE"
echo "Agent mode: $AGENT_MODE"
if [ "$AGENT_MODE" = "websocket" ]; then
  echo "Hub URL: $HUB_URL"
fi
echo "Agent listen: $LISTEN_ADDR"
echo
echo "Known systems:"
sqlite3 "$DB_FILE" "select id, name, host, port, status, updated from systems order by updated desc;"
