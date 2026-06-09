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

run_project "dbt_common" "dbt_common"
run_project "dbt_central" "dbt_central"
run_project "dbt_sub_unit_1" "dbt_sub_unit_1"

echo "dbt mesh run completed successfully."
