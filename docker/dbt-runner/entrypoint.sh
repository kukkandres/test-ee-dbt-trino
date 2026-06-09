#!/usr/bin/env bash
set -euo pipefail

WORKDIR="/workspace"
PROFILES_ROOT="${DBT_PROFILES_ROOT:-/etc/dbt/profiles}"

run_project() {
  local project_dir="$1"
  local profile_subdir="$2"

  echo "=== Running dbt in ${project_dir} ==="
  cd "${WORKDIR}/${project_dir}"
  export DBT_PROFILES_DIR="${PROFILES_ROOT}/${profile_subdir}"

  dbt debug
  dbt run
}

run_project "dbt" "dbt"
run_project "dbt_analytics" "dbt_analytics"
run_project "dbt_parent" "dbt_parent"

echo "dbt mesh run completed successfully."
