#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-eesti-energia}"
REGISTRY_NAME="${REGISTRY_NAME:-eesti-energia-registry.localhost}"
REGISTRY_PORT="${REGISTRY_PORT:-5050}"
AIRFLOW_UI_PORT="${AIRFLOW_UI_PORT:-8088}"

if ! command -v k3d >/dev/null 2>&1; then
  echo "k3d is required. Install from https://k3d.io/" >&2
  exit 1
fi

if k3d cluster list | grep -q "^${CLUSTER_NAME} "; then
  echo "Cluster '${CLUSTER_NAME}' already exists. Skipping creation."
  exit 0
fi

if ! k3d registry list | grep -q "${REGISTRY_NAME}"; then
  echo "Creating registry ${REGISTRY_NAME} on port ${REGISTRY_PORT}..."
  k3d registry create "${REGISTRY_NAME}" --port "${REGISTRY_PORT}"
fi

REGISTRY_CONTAINER="k3d-${REGISTRY_NAME}"

echo "Creating cluster ${CLUSTER_NAME}..."
k3d cluster create "${CLUSTER_NAME}" \
  --registry-use "${REGISTRY_CONTAINER}:${REGISTRY_PORT}" \
  --port "${AIRFLOW_UI_PORT}:30080@loadbalancer"

echo "Cluster '${CLUSTER_NAME}' is ready."
echo "  Registry: ${REGISTRY_NAME}:${REGISTRY_PORT}"
echo "  Airflow UI (after deploy): http://localhost:${AIRFLOW_UI_PORT}"
