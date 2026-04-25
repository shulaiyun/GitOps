#!/usr/bin/env bash

set -euo pipefail

SOURCE_IMAGE="${SOURCE_IMAGE:-slothcloud-sloth-cloud-api}"
TARGET_IMAGE="${TARGET_IMAGE:-sloth-cloud-api-lab:dev}"
K3D_CLUSTER="${K3D_CLUSTER:-sloth-lab}"

if ! docker image inspect "$SOURCE_IMAGE" >/dev/null 2>&1; then
  echo "Source image not found: $SOURCE_IMAGE" >&2
  echo "Build or start the Compose sloth-cloud-api service first, then retry." >&2
  exit 1
fi

if ! k3d cluster list "$K3D_CLUSTER" >/dev/null 2>&1; then
  echo "k3d cluster not found: $K3D_CLUSTER" >&2
  exit 1
fi

docker tag "$SOURCE_IMAGE" "$TARGET_IMAGE"
k3d image import "$TARGET_IMAGE" -c "$K3D_CLUSTER"

echo "Imported $TARGET_IMAGE into k3d cluster $K3D_CLUSTER."
