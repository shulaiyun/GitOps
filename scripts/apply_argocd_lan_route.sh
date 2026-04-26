#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
SERVICE_NAME="${ARGOCD_SERVICE_NAME:-argocd-server}"
GATEWAY_NAMESPACE="${GATEWAY_NAMESPACE:-traefik}"
GATEWAY_NAME="${GATEWAY_NAME:-traefik-gateway}"
ROUTE_NAME="${ARGOCD_LAN_ROUTE_NAME:-argocd-lan}"

if [[ -n "${ARGOCD_LAN_HOST:-}" ]]; then
  HOSTNAME_VALUE="${ARGOCD_LAN_HOST}"
else
  LOCAL_HOST_NAME="$(scutil --get LocalHostName 2>/dev/null || hostname -s)"
  HOSTNAME_VALUE="${LOCAL_HOST_NAME}.local"
fi

# Gateway API hostnames must be lowercase DNS names.
HOSTNAME_VALUE="$(printf '%s' "${HOSTNAME_VALUE}" | tr '[:upper:]' '[:lower:]')"

kubectl -n "${NAMESPACE}" apply -f - <<YAML
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: ${ROUTE_NAME}
  namespace: ${NAMESPACE}
spec:
  parentRefs:
    - name: ${GATEWAY_NAME}
      namespace: ${GATEWAY_NAMESPACE}
  hostnames:
    - ${HOSTNAME_VALUE}
  rules:
    - backendRefs:
        - name: ${SERVICE_NAME}
          port: 80
YAML

echo
echo "Argo CD LAN route is ready:"
echo "  http://${HOSTNAME_VALUE}:16080/"
echo
echo "Check route status:"
echo "  kubectl -n ${NAMESPACE} get httproute ${ROUTE_NAME} -o yaml | sed -n '1,160p'"
