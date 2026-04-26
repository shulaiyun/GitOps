#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This helper is for macOS only." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_FIX_SCRIPT="${SCRIPT_DIR}/fix_macos_local_proxy_bypass.sh"
APP_SUPPORT_DIR="${HOME}/Library/Application Support/SlothOps/local-proxy-bypass"
FIX_SCRIPT="${APP_SUPPORT_DIR}/fix_macos_local_proxy_bypass.sh"

mkdir -p "${APP_SUPPORT_DIR}"
install -m 755 "${SOURCE_FIX_SCRIPT}" "${FIX_SCRIPT}"

LABEL="com.sloth.local-proxy-bypass"
PLIST_DIR="${HOME}/Library/LaunchAgents"
PLIST_PATH="${PLIST_DIR}/${LABEL}.plist"
USER_ID="$(id -u)"

mkdir -p "${PLIST_DIR}"
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
    <string>${FIX_SCRIPT}</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>StartInterval</key>
  <integer>300</integer>
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

echo "Installed LaunchAgent:"
echo "  ${PLIST_PATH}"
echo
echo "It runs this helper at login and every 5 minutes:"
echo "  ${FIX_SCRIPT}"
echo
echo "Source script copied from:"
echo "  ${SOURCE_FIX_SCRIPT}"
echo
launchctl print "gui/${USER_ID}/${LABEL}" | sed -n '1,80p'
