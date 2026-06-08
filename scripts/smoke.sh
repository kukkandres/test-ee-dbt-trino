#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

wait_for() {
  local name="$1"
  local url="$2"
  local max="${3:-60}"
  local i=0
  echo "Waiting for ${name}..."
  until curl -sf "$url" >/dev/null 2>&1; do
    i=$((i + 1))
    if [ "$i" -ge "$max" ]; then
      echo "Timed out waiting for ${name} at ${url}" >&2
      exit 1
    fi
    sleep 2
  done
  echo "${name} is ready."
}

echo "Starting Docker stack..."
docker compose up -d --remove-orphans

wait_for "MinIO" "http://localhost:9000/minio/health/live" 60
wait_for "Trino" "http://localhost:8080/v1/info" 120

echo "Waiting for Hive Metastore via Trino..."
for i in $(seq 1 60); do
  if docker exec trino trino --execute "SHOW CATALOGS" >/dev/null 2>&1; then
    echo "Trino and metastore are ready."
    break
  fi
  if [ "$i" -eq 60 ]; then
    echo "Timed out waiting for Trino/HMS." >&2
    exit 1
  fi
  sleep 3
done

if [ ! -d ".venv" ]; then
  python3 -m venv .venv
fi
# shellcheck disable=SC1091
source .venv/bin/activate
pip install -q -r requirements.txt

export S3_ENDPOINT="${S3_ENDPOINT:-http://localhost:9000}"
export MINIO_ACCESS_KEY="${MINIO_ACCESS_KEY:-minio}"
export MINIO_SECRET_KEY="${MINIO_SECRET_KEY:-minio123}"

echo "Seeding Parquet fixtures to MinIO..."
python scripts/seed_data.py

echo "Bootstrapping Trino catalogs..."
docker exec trino trino -f /sql/bootstrap.sql

echo "Running dbt smoke tests..."
cd dbt
export DBT_PROFILES_DIR="${DBT_PROFILES_DIR:-$(pwd)}"
dbt debug
dbt run

echo "Smoke test completed successfully."
