#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

export BOOTSTRAP_PROFILE="mac-learning"
export BOOTSTRAP_OBSERVABILITY="${BOOTSTRAP_OBSERVABILITY:-0}"
export BOOTSTRAP_ROOT_APP="${BOOTSTRAP_ROOT_APP:-0}"

bash "${ROOT}/k8s/bootstrap/scripts/bootstrap-platform.sh"
