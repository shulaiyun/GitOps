#!/usr/bin/env bash

set -euo pipefail

SOURCE_IMAGE="${SOURCE_IMAGE:-sloth-cloud-sloth-cloud-web:latest}"
FALLBACK_SOURCE_IMAGE="${FALLBACK_SOURCE_IMAGE:-slothcloud-sloth-cloud-web:latest}"
TARGET_IMAGE="${TARGET_IMAGE:-sloth-cloud-web:dev}"
K3D_CLUSTER="${K3D_CLUSTER:-sloth-lab}"

if ! docker image inspect "$SOURCE_IMAGE" >/dev/null 2>&1; then
  if docker image inspect "$FALLBACK_SOURCE_IMAGE" >/dev/null 2>&1; then
    SOURCE_IMAGE="$FALLBACK_SOURCE_IMAGE"
  else
    echo "Source image not found: $SOURCE_IMAGE or $FALLBACK_SOURCE_IMAGE" >&2
    echo "Build or start the Compose sloth-cloud-web service first, then retry." >&2
    exit 1
  fi
fi

if ! k3d cluster list "$K3D_CLUSTER" >/dev/null 2>&1; then
  echo "k3d cluster not found: $K3D_CLUSTER" >&2
  exit 1
fi

docker tag "$SOURCE_IMAGE" "$TARGET_IMAGE"
k3d image import "$TARGET_IMAGE" -c "$K3D_CLUSTER"

echo "Imported $TARGET_IMAGE into k3d cluster $K3D_CLUSTER."
