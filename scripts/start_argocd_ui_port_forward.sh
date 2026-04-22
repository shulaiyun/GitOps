#!/usr/bin/env bash

set -euo pipefail

PORT="${ARGOCD_UI_PORT:-19080}"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required" >&2
  exit 1
fi

if ! kubectl get ns argocd >/dev/null 2>&1; then
  echo "argocd namespace not found in the current cluster context" >&2
  exit 1
fi

if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "Port $PORT is already in use. Pick another one with ARGOCD_UI_PORT=<port>." >&2
  exit 1
fi

cat <<EOF
Argo CD UI tunnel is starting.
Keep this terminal window open while you use the page.

URL: https://127.0.0.1:$PORT
Password command: bash k8s/bootstrap/scripts/show-argocd-admin-password.sh

Stop later with: Ctrl+C
EOF

exec kubectl -n argocd port-forward svc/argocd-server "${PORT}:80"
