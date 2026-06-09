"""
Run the full dbt mesh (common -> central -> sub_unit_1) in an ephemeral pod.

Prerequisite: docker-compose lakehouse stack is up and bootstrapped
(seed_data.py + sql/bootstrap.sql) before triggering this DAG.
"""

from datetime import datetime

from airflow import DAG
from airflow.providers.cncf.kubernetes.operators.pod import KubernetesPodOperator
from airflow.providers.cncf.kubernetes.secret import Secret
from kubernetes.client import models as k8s

NAMESPACE = "data-platform"
DBT_IMAGE = "k3d-ee-registry.localhost:5050/dbt-mesh-runner:latest"

profile_volume = k8s.V1Volume(
    name="dbt-profiles",
    config_map=k8s.V1ConfigMapVolumeSource(name="dbt-profiles"),
)

profile_mounts = [
    k8s.V1VolumeMount(
        name="dbt-profiles",
        mount_path="/etc/dbt/profiles/dbt_common/profiles.yml",
        sub_path="ee_common_profiles.yml",
        read_only=True,
    ),
    k8s.V1VolumeMount(
        name="dbt-profiles",
        mount_path="/etc/dbt/profiles/dbt_central/profiles.yml",
        sub_path="ee_central_profiles.yml",
        read_only=True,
    ),
    k8s.V1VolumeMount(
        name="dbt-profiles",
        mount_path="/etc/dbt/profiles/dbt_sub_unit_1/profiles.yml",
        sub_path="ee_sub_unit_1_profiles.yml",
        read_only=True,
    ),
]

dbt_secrets = [
    Secret("env", "TRINO_HOST", "dbt-env", "TRINO_HOST"),
    Secret("env", "TRINO_PORT", "dbt-env", "TRINO_PORT"),
    Secret("env", "DBT_TARGET", "dbt-env", "DBT_TARGET"),
]

with DAG(
    dag_id="dbt_mesh_run",
    description="Run dbt mesh across all projects in an ephemeral pod",
    schedule=None,
    start_date=datetime(2024, 1, 1),
    catchup=False,
    tags=["dbt", "mesh", "k3d"],
) as dag:
    run_dbt_mesh = KubernetesPodOperator(
        task_id="run_dbt_mesh",
        name="dbt-mesh-run",
        namespace=NAMESPACE,
        image=DBT_IMAGE,
        image_pull_policy="Always",
        service_account_name="airflow",
        in_cluster=True,
        get_logs=True,
        is_delete_operator_pod=True,
        on_finish_action="delete_pod",
        startup_timeout_seconds=300,
        secrets=dbt_secrets,
        volumes=[profile_volume],
        volume_mounts=profile_mounts,
        env_vars={"DBT_PROFILES_ROOT": "/etc/dbt/profiles"},
    )
