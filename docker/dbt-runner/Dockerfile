FROM python:3.11-slim

WORKDIR /workspace

RUN apt-get update \
    && apt-get install -y --no-install-recommends git \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir \
    "dbt-core>=1.8,<2.0" \
    "dbt-trino>=1.8,<2.0"

COPY dbt_common /workspace/dbt_common
COPY dbt_central /workspace/dbt_central
COPY dbt_sub_unit_1 /workspace/dbt_sub_unit_1

# Resolve packages at image build time (CI has internet for dbt Hub).
WORKDIR /workspace/dbt_central
RUN dbt deps

WORKDIR /workspace/dbt_sub_unit_1
RUN dbt deps

WORKDIR /workspace
COPY docker/dbt-runner/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
