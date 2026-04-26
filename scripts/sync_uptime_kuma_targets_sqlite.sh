#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGETS_FILE="${UPTIME_TARGETS_FILE:-$ROOT_DIR/inventory/uptime-targets.yaml}"
CONTAINER="${UPTIME_KUMA_CONTAINER:-platform-uptime-kuma}"
DB_PATH="${UPTIME_KUMA_CONTAINER_DB:-/app/data/kuma.db}"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required." >&2
  exit 1
fi

if ! command -v ruby >/dev/null 2>&1; then
  echo "ruby is required to read $TARGETS_FILE." >&2
  exit 1
fi

if [ ! -f "$TARGETS_FILE" ]; then
  echo "Monitor inventory not found at $TARGETS_FILE" >&2
  exit 1
fi

if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
  echo "Container $CONTAINER is not running." >&2
  exit 1
fi

if ! docker exec "$CONTAINER" sh -lc "test -f '$DB_PATH' && command -v sqlite3 >/dev/null 2>&1"; then
  echo "Uptime Kuma database or sqlite3 is unavailable inside $CONTAINER." >&2
  exit 1
fi

user_id="$(docker exec "$CONTAINER" sqlite3 "$DB_PATH" "select id from user order by id limit 1;")"

if [ -z "$user_id" ]; then
  echo "Uptime Kuma has no user yet. Open the Uptime Kuma page and finish first-time setup first." >&2
  exit 1
fi

tmp_sql="$(mktemp)"
trap 'rm -f "$tmp_sql"' EXIT

ruby -ryaml -rdate -rjson - "$TARGETS_FILE" "$user_id" > "$tmp_sql" <<'RUBY'
def q(value)
  return "null" if value.nil?
  quote = 39.chr
  quote + value.to_s.gsub(quote, quote + quote) + quote
end

def int(value)
  Integer(value)
end

def rewrite_localhost(value)
  return value unless value.is_a?(String)

  value
    .sub(%r{://127\.0\.0\.1(?=[:/])}, "://host.docker.internal")
    .sub(%r{://localhost(?=[:/])}, "://host.docker.internal")
end

def rewrite_host(value)
  ["127.0.0.1", "localhost"].include?(value) ? "host.docker.internal" : value
end

payload = YAML.safe_load(
  File.read(ARGV.fetch(0)),
  permitted_classes: [Date, Time],
  aliases: false
)
user_id = Integer(ARGV.fetch(1))

puts "begin transaction;"

payload.fetch("checks").each do |check|
  name = check.fetch("name")
  description = "inventory_id=#{check.fetch("id")}; tags=#{Array(check["tags"]).join(",")}"
  interval = [Integer(check["interval_seconds"] || 60), 20].max
  expected = check["expected_status"] ? "[\"#{check["expected_status"]}-#{check["expected_status"]}\"]" : "[\"200-299\"]"
  headers = check["headers"]
  headers = headers.to_json unless headers.nil? || headers.is_a?(String)

  common = [
    "active = 1",
    "user_id = #{user_id}",
    "interval = #{interval}",
    "retry_interval = #{interval}",
    "maxretries = 0",
    "ignore_tls = 0",
    "upside_down = 0",
    "maxredirects = 10",
    "accepted_statuscodes_json = #{q(expected)}",
    "method = 'GET'",
    "headers = #{q(headers)}",
    "description = #{q(description)}",
    "timeout = 48"
  ]

  case check.fetch("type")
  when "http"
    target = rewrite_localhost(check.fetch("target"))
    set = common + [
      "type = 'http'",
      "url = #{q(target)}",
      "hostname = null",
      "port = null"
    ]
    columns = "name, active, user_id, interval, retry_interval, url, type, accepted_statuscodes_json, method, headers, description, timeout"
    values = "#{q(name)}, 1, #{user_id}, #{interval}, #{interval}, #{q(target)}, 'http', #{q(expected)}, 'GET', #{q(headers)}, #{q(description)}, 48"
  when "tcp"
    host, port = check.fetch("target").to_s.split(":", 2)
    raise "Invalid tcp target for #{name}" if host.nil? || port.nil?
    host = rewrite_host(host)
    set = common + [
      "type = 'port'",
      "url = null",
      "hostname = #{q(host)}",
      "port = #{int(port)}"
    ]
    columns = "name, active, user_id, interval, retry_interval, hostname, port, type, accepted_statuscodes_json, method, headers, description, timeout"
    values = "#{q(name)}, 1, #{user_id}, #{interval}, #{interval}, #{q(host)}, #{int(port)}, 'port', #{q(expected)}, 'GET', #{q(headers)}, #{q(description)}, 48"
  else
    raise "Unsupported monitor type: #{check.fetch("type")}"
  end

  puts "update monitor set #{set.join(", ")} where name = #{q(name)};"
  puts "insert into monitor (#{columns}) select #{values} where not exists (select 1 from monitor where name = #{q(name)});"
end

puts <<~SQL
  insert into monitor_notification (monitor_id, notification_id)
  select m.id, n.id
  from monitor m
  join notification n on n.active = 1 and n.is_default = 1
  where not exists (
    select 1
    from monitor_notification mn
    where mn.monitor_id = m.id and mn.notification_id = n.id
  );
SQL

puts "commit;"
RUBY

docker exec -i "$CONTAINER" sqlite3 "$DB_PATH" < "$tmp_sql"
docker restart "$CONTAINER" >/dev/null

echo "Synced Uptime Kuma monitors from $TARGETS_FILE"
echo "Container restarted: $CONTAINER"
echo "Current monitor count: $(docker exec "$CONTAINER" sqlite3 "$DB_PATH" "select count(*) from monitor;")"
