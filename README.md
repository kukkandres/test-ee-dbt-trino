# dbt + Trino local lakehouse test setup

Local smoke stack for developing and testing [dbt](https://www.getdbt.com/) models against **Trino** with **MinIO** (S3), **Parquet** sources (Hive catalog), and **Iceberg** tables.

## Architecture

| Component | Purpose |
|-----------|---------|
| **MinIO** | S3-compatible object storage (`lakehouse-raw`, `lakehouse-warehouse`) |
| **Hive Metastore** | Table metadata for Hive + Iceberg catalogs |
| **Trino** | SQL engine (`hive` catalog for Parquet, `iceberg` catalog for Iceberg) |
| **dbt-trino** | Transformations; default target schema `iceberg.dbt_dev` |

### dbt Mesh (parent + children)

| Project | Path | Role | Upstream |
|---------|------|------|----------|
| **eesti_energia** (child) | `dbt/` | Lakehouse layer — staging + public marts | Sources (Hive/Iceberg) |
| **eesti_energia_analytics** (child) | `dbt_analytics/` | Analytics layer — enriches lakehouse marts | `../dbt` via `packages.yml` |
| **eesti_energia_parent** (parent) | `dbt_parent/` | Reporting layer — final views for consumers | `../dbt` + `../dbt_analytics` via `packages.yml` |

```
dbt (lakehouse) ──► dbt_analytics ──► dbt_parent
       └──────────────────────────────────┘
```

Child marts are marked `access: public`; staging models stay `private`. Each child enforces mesh boundaries with `restrict-access: true`, so downstream projects can only `ref()` public models.

### Where dbt stores data

Trino/Starburst does not store table files on the engine. With the default **`view`** materialization, dbt creates views in `iceberg.dbt_dev` (metastore only). Source and Iceberg bronze data live on MinIO:

- Parquet: `s3://lakehouse-raw/parquet/...`
- Iceberg: `s3://lakehouse-warehouse/...`

Use `+materialized: table` in `dbt_project.yml` to write physical Iceberg tables under the warehouse path.

## Prerequisites

- Docker Desktop (or Docker Engine + Compose)
- Python 3.11+

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

cd dbt
export DBT_PROFILES_DIR=$(pwd)
dbt debug
dbt run

cd ../dbt_analytics
export DBT_PROFILES_DIR=$(pwd)
dbt deps
dbt debug
dbt run

cd ../dbt_parent
export DBT_PROFILES_DIR=$(pwd)
dbt deps
dbt debug
dbt run
```

## dbt docs (full mesh)

Generate documentation from the **parent** project (`dbt_parent`). It installs lakehouse and analytics as packages, so one docs site includes models from all three projects and their cross-package lineage.

Models must exist in Trino first — run `dbt run` in each project (see [Manual steps](#manual-steps) or `./scripts/smoke.sh`) before generating docs.

```bash
source .venv/bin/activate   # from repo root

cd dbt_parent
export DBT_PROFILES_DIR=$(pwd)
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

Artifacts are written to `dbt_parent/target/` (`manifest.json`, `catalog.json`, `index.html`).

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

## Starburst (production)

Use the same dbt project with `dbt/profiles.yml` pointed at your Starburst host and catalogs. Only connection settings change; storage remains on your object store + catalog (Glue/HMS/Nessie).

## Troubleshooting

- **Trino cannot read S3**: Confirm MinIO is up and credentials in `docker/trino/etc/catalog/*.properties` match `minio` / `minio123`.
- **Metastore connection errors**: Hive Metastore may need one restart on first boot (`docker compose restart hive-metastore`). Wait until `docker exec trino trino --execute "SHOW CATALOGS"` succeeds before bootstrap.
- **Bootstrap `No FileSystem for scheme "s3"`**: Use `s3a://` paths in `sql/bootstrap.sql` (already configured).
- **dbt cannot connect**: Ensure `TRINO_HOST=localhost` and port `8080` are exposed; set `DBT_PROFILES_DIR` to the `dbt/` directory.
- **Orphan `metastore-ready` container**: Run `docker compose up -d --remove-orphans` after pulling latest compose changes.
