#!/usr/bin/env bash

set -euo pipefail

NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
DEPLOYMENT="${ARGOCD_SERVER_DEPLOYMENT:-argocd-server}"
SECRET_NAME="${ARGOCD_SECRET_NAME:-argocd-secret}"
INITIAL_SECRET_NAME="${ARGOCD_INITIAL_SECRET_NAME:-argocd-initial-admin-secret}"
NEW_PASSWORD="${1:-${ARGOCD_NEW_PASSWORD:-}}"

if [[ -z "${NEW_PASSWORD}" ]]; then
  read -r -s -p "New Argo CD admin password: " NEW_PASSWORD
  echo
  read -r -s -p "Repeat new password: " NEW_PASSWORD_REPEAT
  echo

  if [[ "${NEW_PASSWORD}" != "${NEW_PASSWORD_REPEAT}" ]]; then
    echo "Passwords do not match." >&2
    exit 1
  fi
fi

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required" >&2
  exit 1
fi

echo "Generating bcrypt hash inside the Argo CD server container..."
password_hash="$(kubectl exec -n "${NAMESPACE}" "deploy/${DEPLOYMENT}" -- \
  argocd account bcrypt --password "${NEW_PASSWORD}")"

password_mtime="$(date -u +%FT%TZ)"

echo "Patching ${SECRET_NAME} in namespace ${NAMESPACE}..."
kubectl -n "${NAMESPACE}" patch secret "${SECRET_NAME}" \
  -p "{\"stringData\": {\"admin.password\": \"${password_hash}\", \"admin.passwordMtime\": \"${password_mtime}\"}}"

if kubectl -n "${NAMESPACE}" get secret "${INITIAL_SECRET_NAME}" >/dev/null 2>&1; then
  echo "Deleting ${INITIAL_SECRET_NAME} so the old initial password is not left behind..."
  kubectl -n "${NAMESPACE}" delete secret "${INITIAL_SECRET_NAME}"
fi

echo
echo "Argo CD admin password updated."
echo "You can now log in with:"
echo "  username: admin"
echo "  password: <the new password you just set>"
