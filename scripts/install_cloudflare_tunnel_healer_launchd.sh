#!/usr/bin/env bash
set -euo pipefail

label="${LAUNCHD_LABEL:-com.sloth.public-gateway-healer}"
interval="${HEAL_INTERVAL_SECONDS:-60}"
plist_dir="$HOME/Library/LaunchAgents"
plist_file="$plist_dir/${label}.plist"
install_root="${SLOTH_HEALER_HOME:-$HOME/.sloth-ops/public-gateway-healer}"
bin_dir="$install_root/bin"
log_dir="$install_root/logs"
healer_script="$bin_dir/cloudflare-tunnel-healer.sh"

mkdir -p "$plist_dir" "$bin_dir" "$log_dir"

cat > "$healer_script" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

container_name="${CLOUDFLARED_CONTAINER:-sloth-cloud-local-tunnel}"
image="${CLOUDFLARED_IMAGE:-cloudflare/cloudflared:latest}"
public_gateway_port="${PUBLIC_GATEWAY_PORT:-18088}"
public_check_url="${PUBLIC_CHECK_URL:-https://ops.shulaiyun.top/}"
public_ok_statuses="${PUBLIC_OK_STATUS_CODES:-200,301,302,401,403}"
local_check_host="${LOCAL_GATEWAY_HOST:-ops.shulaiyun.top}"
local_ok_statuses="${LOCAL_OK_STATUS_CODES:-200,301,302,401,403}"
timeout_seconds="${HEAL_TIMEOUT_SECONDS:-8}"
recheck_delay_seconds="${HEAL_RECHECK_DELAY_SECONDS:-8}"
heal_protocols="${CLOUDFLARED_HEAL_PROTOCOLS:-http2,quic}"
log_file="${HEAL_LOG_FILE:-$HOME/.sloth-ops/public-gateway-healer/logs/cloudflare-tunnel-healer.log}"

mkdir -p "$(dirname "$log_file")"

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

extract_token() {
  docker inspect "$container_name" --format '{{json .Config.Cmd}}' |
    python3 -c 'import json,sys; cmd=json.load(sys.stdin); print(cmd[cmd.index("--token")+1])'
}

recreate_tunnel() {
  local protocol="$1"
  local token
  token="$(extract_token)"
  if [[ -z "$token" ]]; then
    log "Could not extract tunnel token from $container_name"
    return 1
  fi

  docker rm -f "$container_name" >/dev/null
  docker run -d \
    --name "$container_name" \
    --restart unless-stopped \
    --add-host=host.docker.internal:host-gateway \
    "$image" \
    tunnel --no-autoupdate --protocol "$protocol" run --token "$token" >/dev/null
  unset token
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
  log "Local public gateway is not healthy: status=$local_status. Cannot repair from standalone healer."
  exit 3
fi

if ! docker inspect "$container_name" >/dev/null 2>&1; then
  log "Cloudflared container not found: $container_name"
  exit 4
fi

IFS=',' read -ra protocols <<< "$heal_protocols"
for protocol in "${protocols[@]}"; do
  protocol="${protocol//[[:space:]]/}"
  [[ -n "$protocol" ]] || continue
  case "$protocol" in
    http2|quic|auto) ;;
    *)
      log "Skipping unsupported protocol=$protocol"
      continue
      ;;
  esac

  log "Recreating cloudflared connector: $container_name protocol=$protocol"
  recreate_tunnel "$protocol"

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
SCRIPT

chmod +x "$healer_script"

cat > "$plist_file" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${label}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>${healer_script}</string>
  </array>
  <key>WorkingDirectory</key>
  <string>${install_root}</string>
  <key>StartInterval</key>
  <integer>${interval}</integer>
  <key>RunAtLoad</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${log_dir}/cloudflare-tunnel-healer.launchd.log</string>
  <key>StandardErrorPath</key>
  <string>${log_dir}/cloudflare-tunnel-healer.launchd.err.log</string>
</dict>
</plist>
PLIST

plutil -lint "$plist_file" >/dev/null

launchctl bootout "gui/$(id -u)" "$plist_file" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$plist_file"
launchctl kickstart -k "gui/$(id -u)/${label}" >/dev/null 2>&1 || true

cat <<EOF
Installed Cloudflare tunnel healer.

Label:
  ${label}

Standalone healer:
  ${healer_script}

Plist:
  ${plist_file}

Logs:
  ${log_dir}/cloudflare-tunnel-healer.log
  ${log_dir}/cloudflare-tunnel-healer.launchd.log
  ${log_dir}/cloudflare-tunnel-healer.launchd.err.log

Check status:
  launchctl print gui/$(id -u)/${label}

Disable:
  launchctl bootout gui/$(id -u) "${plist_file}"
EOF
