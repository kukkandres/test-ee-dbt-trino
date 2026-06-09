#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
K3D_DIR="${ROOT}/k3d"
NAMESPACE="${NAMESPACE:-data-platform}"

if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "kubectl cannot reach a cluster. Run k3d/cluster-create.sh first." >&2
  exit 1
fi

echo "Applying Kubernetes manifests..."
kubectl apply -f "${K3D_DIR}/manifests/namespace.yaml"

SECRET_FILE="${K3D_DIR}/manifests/dbt-env-secret.yaml"
if [ ! -f "${SECRET_FILE}" ]; then
  echo "Creating dbt-env secret from example..."
  cp "${K3D_DIR}/manifests/dbt-env-secret.yaml.example" "${SECRET_FILE}"
fi

kubectl apply -f "${K3D_DIR}/manifests/dbt-profiles-configmap.yaml"
kubectl apply -f "${SECRET_FILE}"
kubectl apply -f "${K3D_DIR}/manifests/postgres.yaml"
kubectl apply -f "${K3D_DIR}/manifests/airflow-rbac.yaml"
kubectl apply -f "${K3D_DIR}/manifests/airflow-configmap.yaml"

echo "Waiting for Postgres..."
kubectl rollout status deployment/postgres -n "${NAMESPACE}" --timeout=120s

echo "Initializing Airflow database..."
kubectl delete job airflow-init -n "${NAMESPACE}" --ignore-not-found
kubectl apply -f "${K3D_DIR}/manifests/airflow-init-job.yaml"
kubectl wait --for=condition=complete job/airflow-init -n "${NAMESPACE}" --timeout=300s

echo "Syncing Airflow DAGs..."
kubectl create configmap airflow-dags \
  --from-file="${K3D_DIR}/dags/" \
  --namespace="${NAMESPACE}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f "${K3D_DIR}/manifests/airflow-deployment.yaml"
kubectl apply -f "${K3D_DIR}/manifests/airflow-service.yaml"

echo "Building and pushing dbt runner image..."
"${ROOT}/scripts/build-dbt-image.sh"

echo "Waiting for Airflow pods..."
kubectl rollout status deployment/airflow-scheduler -n "${NAMESPACE}" --timeout=300s
kubectl rollout status deployment/airflow-webserver -n "${NAMESPACE}" --timeout=300s

echo "Deploy complete."
echo "  Airflow UI: http://localhost:${AIRFLOW_UI_PORT:-8088}"
echo "  Trigger DAG: dbt_mesh_run"
