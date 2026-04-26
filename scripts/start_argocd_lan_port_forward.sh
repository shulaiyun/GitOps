#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
SERVICE_NAME="${ARGOCD_SERVICE_NAME:-argocd-server}"
LOCAL_PORT="${ARGOCD_LAN_PORT:-19082}"
BIND_ADDRESS="${ARGOCD_BIND_ADDRESS:-0.0.0.0}"
REMOTE_PORT="${ARGOCD_REMOTE_PORT:-80}"
SCHEME="${ARGOCD_SCHEME:-http}"

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
export KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/config}"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required" >&2
  exit 1
fi

mac_lan_ip="$(ipconfig getifaddr en0 2>/dev/null || true)"
if [[ -z "${mac_lan_ip}" ]]; then
  mac_lan_ip="$(ifconfig | awk '/inet 192\.168\.|inet 10\.|inet 172\.(1[6-9]|2[0-9]|3[0-1])\./ {print $2; exit}')"
fi

echo "Starting Argo CD LAN port-forward..."
echo "Namespace: ${NAMESPACE}"
echo "Service:   ${SERVICE_NAME}"
echo "Bind:      ${BIND_ADDRESS}"
echo "Local:     ${LOCAL_PORT}"
echo "Remote:    ${REMOTE_PORT}"
echo "KUBECONFIG:${KUBECONFIG}"
echo

if [[ -n "${mac_lan_ip}" ]]; then
  echo "LAN URL:"
  echo "  ${SCHEME}://${mac_lan_ip}:${LOCAL_PORT}/"
else
  echo "LAN URL:"
  echo "  ${SCHEME}://<this-mac-lan-ip>:${LOCAL_PORT}/"
fi

echo
exec kubectl port-forward \
  --address "${BIND_ADDRESS}" \
  "service/${SERVICE_NAME}" \
  -n "${NAMESPACE}" \
  "${LOCAL_PORT}:${REMOTE_PORT}"
