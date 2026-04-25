#!/usr/bin/env bash

set -euo pipefail

NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
SERVICE_NAME="${ARGOCD_SERVICE_NAME:-argocd-server}"
LOCAL_PORT="${ARGOCD_LOCAL_PORT:-19080}"
BIND_ADDRESS="${ARGOCD_BIND_ADDRESS:-127.0.0.1}"
REMOTE_PORT="${ARGOCD_REMOTE_PORT:-80}"
SCHEME="${ARGOCD_SCHEME:-http}"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required" >&2
  exit 1
fi

mac_lan_ip="$(ifconfig | awk '/inet 192\.168\.|inet 10\.|inet 172\.(1[6-9]|2[0-9]|3[0-1])\./ {print $2; exit}')"

echo "Starting Argo CD port-forward..."
echo "Namespace: ${NAMESPACE}"
echo "Service:   ${SERVICE_NAME}"
echo "Bind:      ${BIND_ADDRESS}"
echo "Local:     ${LOCAL_PORT}"
echo

if [[ "${BIND_ADDRESS}" == "127.0.0.1" || "${BIND_ADDRESS}" == "localhost" ]]; then
  echo "Local-only URL:"
  echo "  ${SCHEME}://127.0.0.1:${LOCAL_PORT}"
else
  echo "LAN URL:"
  if [[ -n "${mac_lan_ip}" ]]; then
    echo "  ${SCHEME}://${mac_lan_ip}:${LOCAL_PORT}"
  else
    echo "  ${SCHEME}://<this-mac-lan-ip>:${LOCAL_PORT}"
  fi
  echo
  echo "Other computers on the same router still need:"
  echo "  1. This terminal to stay open"
  echo "  2. macOS firewall to allow the connection"
  echo "  3. the router/Wi-Fi not to block client-to-client access"
fi

echo
echo "Press Ctrl+C to stop."

exec kubectl port-forward \
  --address "${BIND_ADDRESS}" \
  "service/${SERVICE_NAME}" \
  -n "${NAMESPACE}" \
  "${LOCAL_PORT}:${REMOTE_PORT}"
