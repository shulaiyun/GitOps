#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
VALUES_DIR="${ROOT}/k8s/bootstrap/values"
MANIFESTS_DIR="${ROOT}/k8s/bootstrap/manifests"

for cmd in kubectl helm curl envsubst git; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "$cmd is required" >&2
    exit 1
  fi
done

export PLATFORM_GIT_REPO="${PLATFORM_GIT_REPO:-}"
export PLATFORM_GIT_REVISION="${PLATFORM_GIT_REVISION:-main}"
export GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-change-me-now}"
export BOOTSTRAP_PROFILE="${BOOTSTRAP_PROFILE:-full}"
export BOOTSTRAP_OBSERVABILITY="${BOOTSTRAP_OBSERVABILITY:-}"
export BOOTSTRAP_ROOT_APP="${BOOTSTRAP_ROOT_APP:-}"

if [[ -z "${PLATFORM_GIT_REPO}" ]] && git -C "${ROOT}" remote get-url origin >/dev/null 2>&1; then
  export PLATFORM_GIT_REPO="$(git -C "${ROOT}" remote get-url origin)"
fi

if [[ "${BOOTSTRAP_PROFILE}" == "mac-learning" ]]; then
  export BOOTSTRAP_OBSERVABILITY="${BOOTSTRAP_OBSERVABILITY:-0}"
  export BOOTSTRAP_ROOT_APP="${BOOTSTRAP_ROOT_APP:-0}"
else
  export BOOTSTRAP_OBSERVABILITY="${BOOTSTRAP_OBSERVABILITY:-1}"
  export BOOTSTRAP_ROOT_APP="${BOOTSTRAP_ROOT_APP:-1}"
fi

kubectl apply -f "${MANIFESTS_DIR}/namespaces.yaml"

kubectl apply -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.0/standard-install.yaml"

kubectl apply --server-side --force-conflicts -n argocd -f "https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"

helm repo add jetstack https://charts.jetstack.io >/dev/null 2>&1 || true
helm repo add external-secrets https://charts.external-secrets.io >/dev/null 2>&1 || true
helm repo add traefik https://traefik.github.io/charts >/dev/null 2>&1 || true
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo add grafana https://grafana.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update

helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --set crds.enabled=true

helm upgrade --install external-secrets external-secrets/external-secrets \
  --namespace external-secrets

helm upgrade --install traefik traefik/traefik \
  --namespace traefik \
  -f "${VALUES_DIR}/traefik-values.yaml"

if [[ "${BOOTSTRAP_OBSERVABILITY}" == "1" ]]; then
  helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
    --namespace observability \
    -f "${VALUES_DIR}/kube-prometheus-stack-values.yaml" \
    --set grafana.adminPassword="${GRAFANA_ADMIN_PASSWORD}"

  helm upgrade --install loki grafana/loki \
    --namespace observability \
    -f "${VALUES_DIR}/loki-values.yaml"
else
  echo "BOOTSTRAP_OBSERVABILITY=${BOOTSTRAP_OBSERVABILITY}; skipping kube-prometheus-stack and Loki."
fi

if [[ "${BOOTSTRAP_ROOT_APP}" == "1" && -n "${PLATFORM_GIT_REPO}" ]]; then
  envsubst <"${MANIFESTS_DIR}/root-application.template.yaml" | kubectl apply -f -
elif [[ "${BOOTSTRAP_ROOT_APP}" != "1" ]]; then
  echo "BOOTSTRAP_ROOT_APP=${BOOTSTRAP_ROOT_APP}; skipping root Argo CD application bootstrap."
else
  echo "PLATFORM_GIT_REPO is not set; skipping root Argo CD application bootstrap."
fi

kubectl get pods -A
