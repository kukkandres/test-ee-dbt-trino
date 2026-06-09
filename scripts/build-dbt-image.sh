#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGISTRY_HOST="${REGISTRY_HOST:-eesti-energia-registry.localhost:5050}"
REGISTRY_CLUSTER="${REGISTRY_CLUSTER:-k3d-eesti-energia-registry.localhost:5050}"
IMAGE_NAME="${IMAGE_NAME:-dbt-mesh-runner:latest}"

cd "${ROOT}"

# Image build runs `dbt deps` inside the Dockerfile; network access is required
# when packages.yml includes dbt Hub dependencies.
echo "Building dbt mesh runner image..."
docker build -f docker/dbt-runner/Dockerfile -t "${REGISTRY_HOST}/${IMAGE_NAME}" .

echo "Pushing to host registry (${REGISTRY_HOST})..."
docker push "${REGISTRY_HOST}/${IMAGE_NAME}"

echo "Tagging for in-cluster pulls (${REGISTRY_CLUSTER})..."
docker tag "${REGISTRY_HOST}/${IMAGE_NAME}" "${REGISTRY_CLUSTER}/${IMAGE_NAME}"
docker push "${REGISTRY_CLUSTER}/${IMAGE_NAME}"

echo "Image pushed:"
echo "  host:     ${REGISTRY_HOST}/${IMAGE_NAME}"
echo "  cluster:  ${REGISTRY_CLUSTER}/${IMAGE_NAME}"
