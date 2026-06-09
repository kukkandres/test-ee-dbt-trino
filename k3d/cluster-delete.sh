#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-ee}"
REGISTRY_NAME="${REGISTRY_NAME:-ee-registry.localhost}"

if k3d cluster list | grep -q "^${CLUSTER_NAME} "; then
  echo "Deleting cluster ${CLUSTER_NAME}..."
  k3d cluster delete "${CLUSTER_NAME}"
fi

REGISTRY_CONTAINER="k3d-${REGISTRY_NAME}"
if docker ps -a --format '{{.Names}}' | grep -q "^${REGISTRY_CONTAINER}$"; then
  echo "Deleting registry ${REGISTRY_NAME}..."
  k3d registry delete "${REGISTRY_NAME}"
fi

echo "Cleanup complete."
