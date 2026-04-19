#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
CONFIG_FILE="${ROOT}/k8s/bootstrap/config/k3s-config.yaml"

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required" >&2
  exit 1
fi

if command -v k3s >/dev/null 2>&1; then
  echo "k3s already installed"
else
  export INSTALL_K3S_CHANNEL="${INSTALL_K3S_CHANNEL:-stable}"
  export K3S_CONFIG_FILE="${CONFIG_FILE}"
  curl -sfL https://get.k3s.io | sh -
fi

if ! command -v kubectl >/dev/null 2>&1; then
  sudo ln -sf /usr/local/bin/k3s /usr/local/bin/kubectl
fi

if ! command -v helm >/dev/null 2>&1; then
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

kubectl version --client
helm version
