#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OS_NAME="$(uname -s)"
ARCH_NAME="$(uname -m)"
REMOTE_URL=""
BRANCH_NAME=""

if git -C "$ROOT_DIR" remote get-url origin >/dev/null 2>&1; then
  REMOTE_URL="$(git -C "$ROOT_DIR" remote get-url origin)"
fi

if git -C "$ROOT_DIR" rev-parse --abbrev-ref HEAD >/dev/null 2>&1; then
  BRANCH_NAME="$(git -C "$ROOT_DIR" rev-parse --abbrev-ref HEAD)"
fi

echo "Platform Control K3s preflight"
echo "OS: ${OS_NAME}"
echo "Arch: ${ARCH_NAME}"
echo "Branch: ${BRANCH_NAME:-unknown}"
echo "Git remote (GitOps source): ${REMOTE_URL:-not configured}"
echo

if [ "${OS_NAME}" = "Linux" ]; then
  echo "Host role: Linux lab node candidate"
else
  echo "Host role: control workstation only"
  echo "Reason: K3s (lightweight Kubernetes) install script in this repo is intended for Linux, not ${OS_NAME}."
fi

echo
for cmd in git curl envsubst kubectl helm; do
  if command -v "$cmd" >/dev/null 2>&1; then
    printf "[ok] %s -> %s\n" "$cmd" "$(command -v "$cmd")"
  else
    printf "[missing] %s\n" "$cmd"
  fi
done

echo
if [ -n "${REMOTE_URL}" ]; then
  echo "Root Argo CD manifest preview:"
  bash "${ROOT_DIR}/scripts/render_root_application.sh" | sed -n '1,20p'
else
  echo "Root Argo CD manifest preview skipped because the Git remote is not configured."
fi
