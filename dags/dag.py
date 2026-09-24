"""Airflow entrypoint for the local Bronze, Silver, and Gold pipeline.

One DAG run creates one pipeline_run_id. A failed quality gate stops Gold.
"""

from __future__ import annotations

import uuid
from datetime import datetime
from pathlib import Path

from airflow import DAG
from airflow.operators.python import PythonOperator

PROJECT_ROOT = Path("/opt/airflow/project")
RAW_DIR = PROJECT_ROOT / "data" / "raw"
SCHEMA_DIR = PROJECT_ROOT / "database" / "schemas"
SCHEMA_FILES = ("bronze.sql", "silver.sql", "gold.sql", "ops.sql")


def validate_raw_files() -> None:
    """Fail when an expected source file is missing. manifest.json is skipped."""
    from pipelines.bronze.build_bronze import RECORD_ID_FIELDS

    missing = [name for name in RECORD_ID_FIELDS if not (RAW_DIR / name).is_file()]
    if missing:
        raise FileNotFoundError("missing raw files: " + ", ".join(missing))


def initialize_schemas() -> None:
    """Create empty Bronze, Silver, Gold, and ops tables when they are absent."""
    from shared.db import apply_sql_file, connect

    with connect("local") as connection:
        for name in SCHEMA_FILES:
            apply_sql_file(connection, SCHEMA_DIR / name)


def load_bronze() -> str:
    """Load data/raw and return the run id later tasks must reuse."""
    from pipelines.bronze.build_bronze import load_bronze as load_bronze_files

    pipeline_run_id = str(uuid.uuid4())
    load_bronze_files(RAW_DIR, pipeline_run_id)
    return pipeline_run_id


def build_silver() -> None:
    """Build Silver from the Bronze rows already stored for this database."""
    from pipelines.silver.build_silver import build_silver as build_silver_tables

    build_silver_tables()


def run_quality_gate(ti: object) -> None:
    """Check Silver. A failure is stored in ops and stops build_gold."""
    from pipelines.quality.quality_gate import quality_gate

    results = quality_gate(_pipeline_run_id(ti))
    _require_passed(results)


def build_gold() -> None:
    """Build Gold only after the quality gate has passed."""
    from pipelines.gold.build_gold import build_gold as build_gold_tables

    build_gold_tables()


def run_validate_gold(ti: object) -> None:
    """Compare Gold totals with Silver and record the final run status."""
    from pipelines.quality.validate_gold import validate_gold

    results = validate_gold(_pipeline_run_id(ti))
    _require_passed(results)


def _pipeline_run_id(ti: object) -> str:
    """Read the id returned by load_bronze so every layer shares one run."""
    pull = getattr(ti, "xcom_pull")
    pipeline_run_id = pull(task_ids="load_bronze")
    if not pipeline_run_id:
        raise RuntimeError("load_bronze did not return a pipeline_run_id")
    return str(pipeline_run_id)


def _require_passed(results: list[tuple[str, str]]) -> None:
    """Turn a failed check into a failed Airflow task."""
    failed = [name for name, status in results if status != "passed"]
    if failed:
        raise RuntimeError("failed: " + ", ".join(failed))


with DAG(
    dag_id="retail_analytics_pipeline",
    start_date=datetime(2026, 1, 1),
    schedule=None,
    catchup=False,
    max_active_runs=1,
) as dag:
    validate_raw_files_task = PythonOperator(
        task_id="validate_raw_files",
        python_callable=validate_raw_files,
    )
    initialize_schemas_task = PythonOperator(
        task_id="initialize_schemas",
        python_callable=initialize_schemas,
    )
    load_bronze_task = PythonOperator(
        task_id="load_bronze",
        python_callable=load_bronze,
    )
    build_silver_task = PythonOperator(
        task_id="build_silver",
        python_callable=build_silver,
    )
    quality_gate_task = PythonOperator(
        task_id="quality_gate",
        python_callable=run_quality_gate,
    )
    build_gold_task = PythonOperator(
        task_id="build_gold",
        python_callable=build_gold,
    )
    validate_gold_task = PythonOperator(
        task_id="validate_gold",
        python_callable=run_validate_gold,
    )

    (
        validate_raw_files_task
        >> initialize_schemas_task
        >> load_bronze_task
        >> build_silver_task
        >> quality_gate_task
        >> build_gold_task
        >> validate_gold_task
    )
