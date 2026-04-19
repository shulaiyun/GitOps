#!/usr/bin/env bash

set -euo pipefail

CLUSTER_NAME="${K3D_CLUSTER_NAME:-sloth-lab}"
AGENTS="${K3D_AGENTS:-1}"
HTTP_PORT="${K3D_HTTP_PORT:-16080}"
HTTPS_PORT="${K3D_HTTPS_PORT:-16443}"
CONTEXT_NAME="k3d-${CLUSTER_NAME}"

for cmd in docker kubectl k3d; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "$cmd is required" >&2
    exit 1
  fi
done

if ! docker info >/dev/null 2>&1; then
  echo "Docker is not reachable. Start Colima or your Docker runtime first." >&2
  exit 1
fi

if k3d cluster list | awk 'NR > 1 {print $1}' | grep -Fxq "$CLUSTER_NAME"; then
  echo "k3d cluster ${CLUSTER_NAME} already exists"
else
  k3d cluster create "$CLUSTER_NAME" \
    --servers 1 \
    --agents "$AGENTS" \
    --wait \
    --port "${HTTP_PORT}:80@loadbalancer" \
    --port "${HTTPS_PORT}:443@loadbalancer" \
    --k3s-arg "--disable=traefik@server:0"
fi

kubectl config use-context "$CONTEXT_NAME" >/dev/null
kubectl cluster-info
kubectl get nodes -o wide
