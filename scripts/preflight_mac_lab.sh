#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HTTP_PORT="${K3D_HTTP_PORT:-16080}"
HTTPS_PORT="${K3D_HTTPS_PORT:-16443}"

check_port() {
  local port="$1"

  if lsof -nP -iTCP:"${port}" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "[used] port ${port}"
  else
    echo "[free] port ${port}"
  fi
}

echo "Platform Control macOS lab preflight"
echo "OS: $(uname -s)"
echo "Arch: $(uname -m)"
echo "Git remote: $(git -C "$ROOT_DIR" remote get-url origin 2>/dev/null || echo not-configured)"
echo

for cmd in brew colima docker kubectl helm k3d envsubst git; do
  if command -v "$cmd" >/dev/null 2>&1; then
    printf "[ok] %s -> %s\n" "$cmd" "$(command -v "$cmd")"
  else
    printf "[missing] %s\n" "$cmd"
  fi
done

echo
if command -v colima >/dev/null 2>&1; then
  colima status || true
fi

echo
if command -v docker >/dev/null 2>&1; then
  docker context ls
fi

echo
echo "Suggested k3d ingress ports:"
check_port "$HTTP_PORT"
check_port "$HTTPS_PORT"

echo
if command -v kubectl >/dev/null 2>&1; then
  kubectl config get-contexts || true
fi

echo
if git -C "$ROOT_DIR" remote get-url origin >/dev/null 2>&1; then
  echo "Root Argo CD manifest preview:"
  bash "${ROOT_DIR}/scripts/render_root_application.sh" | sed -n '1,20p'
fi
