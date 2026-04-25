#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DB_FILE="${UPTIME_KUMA_DB_FILE:-$ROOT_DIR/stacks/platform-core/data/uptime-kuma/kuma.db}"
TARGETS_FILE="$ROOT_DIR/inventory/uptime-targets.yaml"
CREDENTIALS_FILE="${UPTIME_KUMA_CREDENTIALS_FILE:-$ROOT_DIR/stacks/platform-core/data/uptime-kuma/credentials.env}"
COMPOSE_FILE="$ROOT_DIR/stacks/platform-core/compose.yaml"

if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "sqlite3 is required to bootstrap Uptime Kuma." >&2
  exit 1
fi

if ! command -v ruby >/dev/null 2>&1; then
  echo "ruby is required to read the monitor inventory." >&2
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required to talk to the Uptime Kuma container." >&2
  exit 1
fi

if [ ! -f "$DB_FILE" ]; then
  echo "Uptime Kuma database not found at $DB_FILE" >&2
  exit 1
fi

if [ ! -f "$TARGETS_FILE" ]; then
  echo "Monitor inventory not found at $TARGETS_FILE" >&2
  exit 1
fi

user_count="$(sqlite3 "$DB_FILE" "select count(*) from user;")"
setup_required=0

if [ "$user_count" = "0" ]; then
  setup_required=1
  username="${UPTIME_KUMA_USERNAME:-sloth-admin}"
  password="${UPTIME_KUMA_PASSWORD:-$(openssl rand -hex 16)}"
  mkdir -p "$(dirname "$CREDENTIALS_FILE")"
  cat > "$CREDENTIALS_FILE" <<EOF
UPTIME_KUMA_USERNAME=$username
UPTIME_KUMA_PASSWORD=$password
EOF
  chmod 600 "$CREDENTIALS_FILE"
else
  if [ -f "$CREDENTIALS_FILE" ]; then
    # shellcheck disable=SC1090
    source "$CREDENTIALS_FILE"
    username="${UPTIME_KUMA_USERNAME}"
    password="${UPTIME_KUMA_PASSWORD}"
  else
    echo "Uptime Kuma already has a user, but $CREDENTIALS_FILE is missing." >&2
    echo "Set UPTIME_KUMA_USERNAME and UPTIME_KUMA_PASSWORD in the shell, then re-run." >&2
    exit 1
  fi
fi

targets_json="$(ruby -rjson -ryaml -rdate -e 'payload = YAML.safe_load(File.read(ARGV[0]), permitted_classes: [Date, Time], aliases: false); puts JSON.generate(payload.fetch("checks"))' "$TARGETS_FILE")"
existing_map_json="$(sqlite3 -separator $'\t' "$DB_FILE" "select id, name from monitor order by id;" | ruby -rjson -e 'map = {}; STDIN.each_line do |line| id, name = line.chomp.split("\t", 2); map[name] = id.to_i if id && name; end; puts JSON.generate(map)')"

docker exec -i \
  -e UPTIME_KUMA_URL="http://127.0.0.1:3001" \
  -e UPTIME_KUMA_USERNAME="$username" \
  -e UPTIME_KUMA_PASSWORD="$password" \
  -e UPTIME_KUMA_SETUP_REQUIRED="$setup_required" \
  -e UPTIME_TARGETS_JSON="$targets_json" \
  -e UPTIME_EXISTING_MAP_JSON="$existing_map_json" \
  platform-uptime-kuma \
  node - <<'NODE'
const { io } = require("socket.io-client");

const url = process.env.UPTIME_KUMA_URL;
const username = process.env.UPTIME_KUMA_USERNAME;
const password = process.env.UPTIME_KUMA_PASSWORD;
const setupRequired = process.env.UPTIME_KUMA_SETUP_REQUIRED === "1";
const checks = JSON.parse(process.env.UPTIME_TARGETS_JSON || "[]");
const existingMap = JSON.parse(process.env.UPTIME_EXISTING_MAP_JSON || "{}");

function rewriteLocalHost(value) {
  if (typeof value !== "string") {
    return value;
  }

  return value
    .replace("://127.0.0.1", "://host.docker.internal")
    .replace("://localhost", "://host.docker.internal");
}

function buildMonitor(check) {
  const interval = Math.max(Number(check.interval_seconds || 60), 20);
  const common = {
    name: check.name,
    type: check.type,
    active: true,
    interval,
    retryInterval: interval,
    resendInterval: 0,
    maxretries: 0,
    upsideDown: false,
    accepted_statuscodes: check.expected_status ? [`${check.expected_status}-${check.expected_status}`] : ["200-299"],
    notificationIDList: {},
    ignoreTls: false,
    expiryNotification: false,
    maxredirects: 10,
    timeout: 48,
    proxyId: null,
    method: "GET",
    body: null,
    headers: null,
    description: null,
    parent: null,
    basic_auth_user: null,
    basic_auth_pass: null,
    oauth_client_id: null,
    oauth_client_secret: null,
    oauth_token_url: null,
    oauth_scopes: null,
    oauth_auth_method: null,
    tlsCa: null,
    tlsCert: null,
    tlsKey: null,
    keyword: null,
    invertKeyword: false,
    dns_resolve_type: null,
    dns_resolve_server: null,
    pushToken: null,
    docker_container: null,
    docker_host: null,
    mqttUsername: null,
    mqttPassword: null,
    mqttTopic: null,
    mqttSuccessMessage: null,
    databaseConnectionString: null,
    databaseQuery: null,
    authMethod: null,
    authWorkstation: null,
    authDomain: null,
    grpcUrl: null,
    grpcProtobuf: null,
    grpcMethod: null,
    grpcServiceName: null,
    grpcBody: null,
    grpcMetadata: null,
    grpcEnableTls: false,
    radiusUsername: null,
    radiusPassword: null,
    radiusCalledStationId: null,
    radiusCallingStationId: null,
    radiusSecret: null,
    httpBodyEncoding: "json",
    expectedValue: null,
    jsonPath: null,
    kafkaProducerTopic: null,
    kafkaProducerBrokers: [],
    kafkaProducerSaslOptions: {},
    kafkaProducerMessage: null,
    kafkaProducerSsl: false,
    kafkaProducerAllowAutoTopicCreation: false,
    gamedigGivenPortOnly: true,
  };

  if (check.type === "http") {
    return {
      ...common,
      url: rewriteLocalHost(check.target),
    };
  }

  if (check.type === "tcp") {
    const [hostname, port] = String(check.target).split(":");
    return {
      ...common,
      type: "port",
      hostname: hostname === "127.0.0.1" || hostname === "localhost" ? "host.docker.internal" : hostname,
      port: Number(port),
      packetSize: 56,
    };
  }

  throw new Error(`Unsupported monitor type: ${check.type}`);
}

function waitForConnect(socket) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("Timed out connecting to Uptime Kuma")), 10000);
    socket.on("connect", () => {
      clearTimeout(timer);
      resolve();
    });
    socket.on("connect_error", (error) => {
      clearTimeout(timer);
      reject(error);
    });
  });
}

function emitAck(socket, event, ...args) {
  return new Promise((resolve, reject) => {
    socket.emit(event, ...args, (response) => {
      if (!response) {
        reject(new Error(`No response from ${event}`));
        return;
      }
      if (response.ok === false) {
        reject(new Error(response.msg || `${event} failed`));
        return;
      }
      resolve(response);
    });
  });
}

(async () => {
  const socket = io(url, { transports: ["websocket"] });

  try {
    await waitForConnect(socket);

    if (setupRequired) {
      await emitAck(socket, "setup", username, password);
    }

    await emitAck(socket, "login", { username, password });

    const created = [];
    const updated = [];

    for (const check of checks) {
      const monitor = buildMonitor(check);
      const existingId = existingMap[check.name];

      if (existingId) {
        monitor.id = existingId;
        await emitAck(socket, "editMonitor", monitor);
        updated.push({ name: check.name, id: existingId });
        continue;
      }

      const result = await emitAck(socket, "add", monitor);
      created.push({ name: check.name, id: result.monitorID });
    }

    console.log(JSON.stringify({ username, created, updated }, null, 2));
  } finally {
    socket.close();
  }
})().catch((error) => {
  console.error(error.stack || error.message);
  process.exit(1);
});
NODE

sqlite3 "$DB_FILE" <<'SQL'
update monitor
set url = replace(replace(url, 'http://127.0.0.1', 'http://host.docker.internal'), 'http://localhost', 'http://host.docker.internal')
where type = 'http' and url is not null;

update monitor
set type = 'port'
where type = 'tcp';

update monitor
set hostname = 'host.docker.internal'
where type = 'port' and hostname in ('127.0.0.1', 'localhost');
SQL

docker compose -f "$COMPOSE_FILE" restart uptime-kuma >/dev/null
sleep 3

echo
echo "Uptime Kuma credentials:"
echo "  file: $CREDENTIALS_FILE"
echo "  username: $username"
echo "  password: stored in the credentials file"
echo
echo "Current monitor count: $(sqlite3 "$DB_FILE" "select count(*) from monitor;")"
