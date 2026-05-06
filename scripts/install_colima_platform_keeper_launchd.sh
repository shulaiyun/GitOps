#!/usr/bin/env bash
set -euo pipefail

label="${LAUNCHD_LABEL:-com.sloth.colima-platform-keeper}"
interval="${KEEP_INTERVAL_SECONDS:-120}"
plist_dir="$HOME/Library/LaunchAgents"
plist_file="$plist_dir/${label}.plist"
install_root="${SLOTH_KEEPER_HOME:-$HOME/.sloth-ops/colima-platform-keeper}"
bin_dir="$install_root/bin"
log_dir="$install_root/logs"
keeper_script="$bin_dir/colima-platform-keeper.sh"

mkdir -p "$plist_dir" "$bin_dir" "$log_dir"

cat > "$keeper_script" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

log_file="${KEEPER_LOG_FILE:-$HOME/.sloth-ops/colima-platform-keeper/logs/colima-platform-keeper.log}"
docker_wait_seconds="${DOCKER_WAIT_SECONDS:-90}"
gateway_healer_label="${GATEWAY_HEALER_LABEL:-com.sloth.public-gateway-healer}"

mkdir -p "$(dirname "$log_file")"

log() {
  printf '[%s] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*" | tee -a "$log_file"
}

if ! command -v colima >/dev/null 2>&1; then
  log "Colima CLI not found. Install Colima first."
  exit 2
fi

if ! command -v docker >/dev/null 2>&1; then
  log "Docker CLI not found. Install Docker CLI first."
  exit 2
fi

if ! colima status >/dev/null 2>&1; then
  log "Colima is not running. Starting Colima..."
  colima start || {
    log "Failed to start Colima."
    exit 3
  }
else
  log "Colima is running."
fi

deadline=$((SECONDS + docker_wait_seconds))
until docker info >/dev/null 2>&1; do
  if (( SECONDS >= deadline )); then
    log "Docker daemon did not become ready within ${docker_wait_seconds}s."
    exit 4
  fi
  sleep 3
done

log "Docker daemon is ready."

containers=(
  public-gateway
  platform-homepage
  platform-homepage-status-api
  platform-uptime-kuma
  platform-dockge
  platform-beszel-hub
  platform-traefik
  sloth-cloud-local-tunnel
)

for name in "${containers[@]}"; do
  if docker inspect "$name" >/dev/null 2>&1; then
    state="$(docker inspect "$name" --format '{{.State.Status}}' 2>/dev/null || true)"
    if [[ "$state" != "running" ]]; then
      log "Starting container: $name state=$state"
      docker start "$name" >/dev/null || log "Failed to start container: $name"
    fi
  fi
done

if launchctl print "gui/$(id -u)/${gateway_healer_label}" >/dev/null 2>&1; then
  launchctl kickstart -k "gui/$(id -u)/${gateway_healer_label}" >/dev/null 2>&1 || true
  log "Kicked ${gateway_healer_label}."
fi

log "Colima platform keeper finished."
SCRIPT

chmod +x "$keeper_script"

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
    <string>${keeper_script}</string>
  </array>
  <key>WorkingDirectory</key>
  <string>${install_root}</string>
  <key>StartInterval</key>
  <integer>${interval}</integer>
  <key>RunAtLoad</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${log_dir}/colima-platform-keeper.launchd.log</string>
  <key>StandardErrorPath</key>
  <string>${log_dir}/colima-platform-keeper.launchd.err.log</string>
</dict>
</plist>
PLIST

plutil -lint "$plist_file" >/dev/null

launchctl bootout "gui/$(id -u)" "$plist_file" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$plist_file"
launchctl kickstart -k "gui/$(id -u)/${label}" >/dev/null 2>&1 || true

cat <<EOF
Installed Colima platform keeper.

Label:
  ${label}

Standalone keeper:
  ${keeper_script}

Plist:
  ${plist_file}

Logs:
  ${log_dir}/colima-platform-keeper.log
  ${log_dir}/colima-platform-keeper.launchd.log
  ${log_dir}/colima-platform-keeper.launchd.err.log

Check status:
  launchctl print gui/$(id -u)/${label}

Disable:
  launchctl bootout gui/$(id -u) "${plist_file}"
EOF
