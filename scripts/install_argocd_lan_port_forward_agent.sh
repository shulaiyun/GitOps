#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This helper is for macOS only." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_SCRIPT="${SCRIPT_DIR}/start_argocd_lan_port_forward.sh"
APP_SUPPORT_DIR="${HOME}/Library/Application Support/SlothOps/argocd-lan-port-forward"
RUN_SCRIPT="${APP_SUPPORT_DIR}/start_argocd_lan_port_forward.sh"

LABEL="com.sloth.argocd-lan-port-forward"
PLIST_DIR="${HOME}/Library/LaunchAgents"
PLIST_PATH="${PLIST_DIR}/${LABEL}.plist"
USER_ID="$(id -u)"
LOCAL_PORT="${ARGOCD_LAN_PORT:-19082}"

mkdir -p "${APP_SUPPORT_DIR}" "${PLIST_DIR}"
install -m 755 "${SOURCE_SCRIPT}" "${RUN_SCRIPT}"
: > "/tmp/${LABEL}.out.log"
: > "/tmp/${LABEL}.err.log"

cat > "${PLIST_PATH}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>${RUN_SCRIPT}</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    <key>ARGOCD_LAN_PORT</key>
    <string>${LOCAL_PORT}</string>
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <dict>
    <key>SuccessfulExit</key>
    <false/>
  </dict>
  <key>ThrottleInterval</key>
  <integer>10</integer>
  <key>StandardOutPath</key>
  <string>/tmp/${LABEL}.out.log</string>
  <key>StandardErrorPath</key>
  <string>/tmp/${LABEL}.err.log</string>
</dict>
</plist>
PLIST

if launchctl print "gui/${USER_ID}/${LABEL}" >/dev/null 2>&1; then
  launchctl bootout "gui/${USER_ID}" "${PLIST_PATH}" >/dev/null 2>&1 || true
fi

launchctl bootstrap "gui/${USER_ID}" "${PLIST_PATH}"
launchctl kickstart -k "gui/${USER_ID}/${LABEL}"

mac_lan_ip="$(ipconfig getifaddr en0 2>/dev/null || true)"

echo "Installed LaunchAgent:"
echo "  ${PLIST_PATH}"
echo
echo "It keeps Argo CD reachable from the LAN on port ${LOCAL_PORT}:"
if [[ -n "${mac_lan_ip}" ]]; then
  echo "  http://${mac_lan_ip}:${LOCAL_PORT}/"
else
  echo "  http://<this-mac-lan-ip>:${LOCAL_PORT}/"
fi
echo
echo "Source script copied from:"
echo "  ${SOURCE_SCRIPT}"
echo
launchctl print "gui/${USER_ID}/${LABEL}" | sed -n '1,90p'
