#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE_FILE="$ROOT_DIR/k8s/bootstrap/manifests/sloth-cloud-api-lab-application.template.yaml"
OUTPUT_FILE="${1:-}"

repo_url="${PLATFORM_GIT_REPO:-}"
if [ -z "$repo_url" ] && git -C "$ROOT_DIR" remote get-url origin >/dev/null 2>&1; then
  repo_url="$(git -C "$ROOT_DIR" remote get-url origin)"
fi

if [ -z "$repo_url" ]; then
  echo "PLATFORM_GIT_REPO is not set and no origin remote is configured." >&2
  exit 1
fi

revision="${PLATFORM_GIT_REVISION:-$(git -C "$ROOT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)}"

PLATFORM_GIT_REPO="$repo_url" PLATFORM_GIT_REVISION="$revision" ruby -e '
  template = File.read(ARGV[0])
  rendered = template
    .gsub("${PLATFORM_GIT_REPO}", ENV.fetch("PLATFORM_GIT_REPO"))
    .gsub("${PLATFORM_GIT_REVISION}", ENV.fetch("PLATFORM_GIT_REVISION"))
  print(rendered)
' "$TEMPLATE_FILE" > "${OUTPUT_FILE:-/dev/stdout}"
