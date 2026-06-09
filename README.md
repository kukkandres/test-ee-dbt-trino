# dbt + Trino local lakehouse test setup

Local smoke stack for developing and testing [dbt](https://www.getdbt.com/) models against **Trino** with **MinIO** (S3), **Parquet** sources (Hive catalog), and **Iceberg** tables.

## Architecture

| Component | Purpose |
|-----------|---------|
| **MinIO** | S3-compatible object storage (`lakehouse-raw`, `lakehouse-warehouse`) |
| **Hive Metastore** | Table metadata for Hive + Iceberg catalogs |
| **Trino** | SQL engine (`hive` catalog for Parquet, `iceberg` catalog for Iceberg) |
| **dbt-trino** | Transformations across mesh projects |

### dbt Mesh (common → central → sub-units)

| Project | Path | Role | Upstream |
|---------|------|------|----------|
| **ee_common** | `dbt_common/` | Shared sources from S3, staging, common gold marts | Sources (Hive/Iceberg) |
| **ee_central** | `dbt_central/` | Centrally managed medallion (bronze/silver/gold tables on S3) | `../dbt_common` via `packages.yml` |
| **ee_sub_unit_1** | `dbt_sub_unit_1/` | Enterprise sub-unit models (e.g. marketing) | `../dbt_common` + `../dbt_central` |

```
S3 sources ──► dbt_common (ee_common)
                    │
                    ▼
              dbt_central (ee_central) — medallion bronze → silver → gold
                    │
                    ▼
              dbt_sub_unit_1 (ee_sub_unit_1)
```

Public gold marts in common and central are `access: public`. Projects use `restrict-access: true` so downstream can only `ref()` public models. `ee_common` also lists children in `packages.yml` for unified `dbt docs`.

### Where dbt stores data

Trino/Starburst does not store table files on the engine. **Views** materialize as metastore-only objects; **tables** in `ee_common` marts and `ee_central` medallion layers write physical Iceberg data to MinIO. Source and bronze data live on MinIO:

- Parquet: `s3://lakehouse-raw/parquet/...`
- Iceberg: `s3://lakehouse-warehouse/...`

Use `+materialized: table` in `dbt_project.yml` to write physical Iceberg tables under the warehouse path.

## Prerequisites

- Docker Desktop (or Docker Engine + Compose)
- Python 3.11+
- [k3d](https://k3d.io/) and `kubectl` (for Kubernetes orchestration only)

## Quick start (smoke test)

```bash
chmod +x scripts/smoke.sh
./scripts/smoke.sh
```

This will:

1. Start MinIO, MariaDB, Hive Metastore, and Trino
2. Upload Parquet fixtures to MinIO
3. Run `sql/bootstrap.sql` (Hive external tables + Iceberg CTAS)
4. Run `dbt debug` and `dbt run`

## Manual steps

```bash
docker compose up -d

python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

export S3_ENDPOINT=http://localhost:9000
python scripts/seed_data.py

docker exec trino trino -f /sql/bootstrap.sql

cd dbt_common
export DBT_PROFILES_DIR=$(pwd)
dbt debug
dbt run

cd ../dbt_central
export DBT_PROFILES_DIR=$(pwd)
dbt deps
dbt debug
dbt run

cd ../dbt_sub_unit_1
export DBT_PROFILES_DIR=$(pwd)
dbt deps
dbt debug
dbt run
```

## dbt docs (full mesh)

Generate documentation from **ee_common** (`dbt_common`). It installs central and sub-unit projects as packages, so one docs site includes models from all projects and cross-package lineage.

Models must exist in Trino first — run `dbt run` in each project (see [Manual steps](#manual-steps) or `./scripts/smoke.sh`) before generating docs.

```bash
source .venv/bin/activate   # from repo root

cd dbt_common
export DBT_PROFILES_DIR=$(pwd)
# For full mesh docs, add central + sub_unit to packages.yml first, then:
dbt deps
dbt docs generate
dbt docs serve --port 8081
```

Open http://localhost:8081. Use port **8081** because Trino already uses **8080**.

To share docs without a local server:

```bash
dbt docs generate --static
open target/static_index.html
```

Artifacts are written to `dbt_common/target/` (`manifest.json`, `catalog.json`, `index.html`).

## Services

| Service | URL |
|---------|-----|
| Trino UI | http://localhost:8080 |
| dbt docs | http://localhost:8081 (after `dbt docs serve --port 8081`) |
| MinIO API | http://localhost:9000 |
| MinIO Console | http://localhost:9001 (user `minio` / `minio123`) |

## dbt sources

| Source | Trino relation |
|--------|----------------|
| `raw_lake.orders` | `hive.raw.orders` (Parquet on S3) |
| `bronze_lake.customers` | `iceberg.bronze.customers` (Iceberg) |

## k3d orchestration (local prod emulation)

Run Airflow on a local k3d cluster and execute dbt in ephemeral pods — similar to production where orchestration runs on Kubernetes, dbt runs in a CI-built image, and connection settings come from ConfigMaps/Secrets. The lakehouse stack (Trino, MinIO, HMS) stays on docker-compose; dbt pods reach Trino via `host.k3d.internal`.

### Architecture

| Component | Where | Purpose |
|-----------|-------|---------|
| MinIO, HMS, Trino | docker-compose | Data plane |
| Airflow scheduler + webserver | k3d | Always-on orchestration |
| dbt-mesh-runner image | k3d local registry (`:5050`) | Packs all three projects; `dbt deps` baked in at image build |
| Postgres | k3d | Airflow metadata database |
| Ephemeral dbt pod | k3d (per DAG run) | Runs full mesh, deleted after finish |
| `dbt-profiles` ConfigMap | k3d | Injects `profiles.yml` per project |
| `dbt-env` Secret | k3d | `TRINO_HOST`, `TRINO_PORT`, `DBT_TARGET` |

### One-shot smoke test

```bash
chmod +x k3d/*.sh scripts/*.sh
./scripts/k3d-smoke.sh
```

This will:

1. Start and bootstrap the docker-compose lakehouse (seed + `bootstrap.sql`)
2. Create the k3d cluster (if missing) with a local registry on port `5050`
3. Deploy Airflow, ConfigMaps, Secrets, and the dbt runner image
4. Trigger the `dbt_mesh_run` DAG and wait for success

Airflow UI: http://localhost:8088 (user `admin` / `admin`)

### Manual setup

```bash
# Lakehouse must be running and bootstrapped first (see Quick start)

./k3d/cluster-create.sh
./k3d/deploy.sh

# Trigger from CLI
kubectl exec -n data-platform deployment/airflow-scheduler -- \
  airflow dags trigger dbt_mesh_run
```

### Iterative dev loop

After changing dbt models:

```bash
./scripts/build-dbt-image.sh
kubectl exec -n data-platform deployment/airflow-scheduler -- \
  airflow dags trigger dbt_mesh_run
```

Or trigger from the Airflow UI.

After changing `packages.yml` (local mesh or dbt Hub packages), refresh locks locally, commit, and rebuild:

```bash
cd dbt_central && dbt deps && cd ../dbt_sub_unit_1 && dbt deps && cd ..
./scripts/build-dbt-image.sh
```

`dbt_packages/` are resolved during `docker build` (CI has internet). Runtime pods only need Trino connectivity — no dbt Hub access.

### Updating connection settings

Profiles are **not** baked into the dbt image. Edit the ConfigMap or Secret, apply, and re-trigger:

```bash
kubectl apply -f k3d/manifests/dbt-profiles-configmap.yaml
# edit k3d/manifests/dbt-env-secret.yaml (copy from .example on first deploy)
kubectl apply -f k3d/manifests/dbt-env-secret.yaml
```

For Starburst-like targets, set `TRINO_HOST` to your remote host and add `STARburst_PASSWORD` to the secret; update profile targets in the ConfigMap if needed.

### Teardown

```bash
./k3d/cluster-delete.sh
docker compose down
```

### Production mapping

| Local k3d | Production |
|-----------|------------|
| k3d local registry (`k3d-ee-registry.localhost:5050` in-cluster) | Internal container registry (ECR, GCR, Harbor) |
| `build-dbt-image.sh` (`dbt deps` at build time) | CI pipeline baking `dbt_packages/` into the runner image |
| `dbt_mesh_run` DAG + `KubernetesPodOperator` | Airflow on K8s spawning ephemeral dbt pods |
| `dbt-profiles` ConfigMap + `dbt-env` Secret | Platform-managed config injection |
| `host.k3d.internal:8080` | Remote Starburst / Trino endpoint |

## Starburst (production)

Use the same dbt projects with `dbt_common/profiles.yml` (and central/sub-unit profiles) pointed at your Starburst host and catalogs. Only connection settings change; storage remains on your object store + catalog (Glue/HMS/Nessie).

## Troubleshooting

- **Trino cannot read S3**: Confirm MinIO is up and credentials in `docker/trino/etc/catalog/*.properties` match `minio` / `minio123`.
- **Metastore connection errors**: Hive Metastore may need one restart on first boot (`docker compose restart hive-metastore`). Wait until `docker exec trino trino --execute "SHOW CATALOGS"` succeeds before bootstrap.
- **Bootstrap `No FileSystem for scheme "s3"`**: Use `s3a://` paths in `sql/bootstrap.sql` (already configured).
- **dbt cannot connect**: Ensure `TRINO_HOST=localhost` and port `8080` are exposed; set `DBT_PROFILES_DIR` to the relevant project directory (e.g. `dbt_common/`).
- **Orphan `metastore-ready` container**: Run `docker compose up -d --remove-orphans` after pulling latest compose changes.
