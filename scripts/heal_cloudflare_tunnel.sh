#!/usr/bin/env bash
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

container_name="${CLOUDFLARED_CONTAINER:-sloth-cloud-local-tunnel}"
public_gateway_port="${PUBLIC_GATEWAY_PORT:-18088}"
public_check_url="${PUBLIC_CHECK_URL:-https://ops.shulaiyun.top/}"
public_ok_statuses="${PUBLIC_OK_STATUS_CODES:-200,301,302,401,403}"
local_check_host="${LOCAL_GATEWAY_HOST:-ops.shulaiyun.top}"
local_ok_statuses="${LOCAL_OK_STATUS_CODES:-200,301,302,401,403}"
timeout_seconds="${HEAL_TIMEOUT_SECONDS:-8}"
recheck_delay_seconds="${HEAL_RECHECK_DELAY_SECONDS:-8}"
heal_protocols="${CLOUDFLARED_HEAL_PROTOCOLS:-http2,quic}"
log_dir="${HEAL_LOG_DIR:-$repo_root/runtime/logs}"
log_file="$log_dir/cloudflare-tunnel-healer.log"

mkdir -p "$log_dir"

log() {
  printf '[%s] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*" | tee -a "$log_file"
}

status_in_list() {
  local needle="$1"
  local list="$2"
  local item
  IFS=',' read -ra items <<< "$list"
  for item in "${items[@]}"; do
    item="${item//[[:space:]]/}"
    if [[ "$needle" == "$item" ]]; then
      return 0
    fi
  done
  return 1
}

http_status() {
  local url="$1"
  shift || true
  curl --noproxy '*' -k -sS -o /dev/null -w '%{http_code}' \
    --connect-timeout "$timeout_seconds" \
    --max-time "$timeout_seconds" \
    "$@" \
    "$url" 2>/dev/null || printf '000'
}

if ! command -v docker >/dev/null 2>&1; then
  log "Docker CLI not found. Is Docker Desktop running?"
  exit 2
fi

public_status="$(http_status "$public_check_url" -I)"
if status_in_list "$public_status" "$public_ok_statuses"; then
  log "OK public=$public_check_url status=$public_status"
  exit 0
fi

log "Public check failed: url=$public_check_url status=$public_status"

local_status="$(http_status "http://127.0.0.1:${public_gateway_port}/" -I -H "Host: ${local_check_host}")"
if ! status_in_list "$local_status" "$local_ok_statuses"; then
  log "Local public gateway is not healthy: status=$local_status. Restarting public gateway."
  bash scripts/start_public_gateway.sh >> "$log_file" 2>&1 || {
    log "Failed to restart public gateway."
    exit 3
  }
else
  log "Local public gateway is healthy: status=$local_status"
fi

if ! docker inspect "$container_name" >/dev/null 2>&1; then
  log "Cloudflared container not found: $container_name"
  exit 4
fi

IFS=',' read -ra protocols <<< "$heal_protocols"
for protocol in "${protocols[@]}"; do
  protocol="${protocol//[[:space:]]/}"
  [[ -n "$protocol" ]] || continue

  log "Recreating cloudflared connector: $container_name protocol=$protocol"
  CLOUDFLARED_PROTOCOL="$protocol" bash scripts/recreate_cloudflare_tunnel_http2.sh >> "$log_file" 2>&1

  sleep "$recheck_delay_seconds"
  public_status_after="$(http_status "$public_check_url" -I)"
  if status_in_list "$public_status_after" "$public_ok_statuses"; then
    log "Recovered public=$public_check_url status=$public_status_after protocol=$protocol"
    exit 0
  fi

  log "Still unhealthy after protocol=$protocol recreate: status=$public_status_after"
done

log "Still unhealthy after trying protocols: $heal_protocols"
exit 1
