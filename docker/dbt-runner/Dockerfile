FROM python:3.11-slim

WORKDIR /workspace

RUN apt-get update \
    && apt-get install -y --no-install-recommends git \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir \
    "dbt-core>=1.8,<2.0" \
    "dbt-trino>=1.8,<2.0"

COPY dbt /workspace/dbt
COPY dbt_analytics /workspace/dbt_analytics
COPY dbt_parent /workspace/dbt_parent

# Resolve packages at image build time (CI has internet for dbt Hub).
# Local mesh packages resolve via sibling paths; hub packages use package-lock.yml.
WORKDIR /workspace/dbt_analytics
RUN dbt deps

WORKDIR /workspace/dbt_parent
RUN dbt deps

WORKDIR /workspace
COPY docker/dbt-runner/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
