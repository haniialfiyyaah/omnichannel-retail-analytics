#!/usr/bin/env bash
# Install the pipeline driver, then start Airflow.
# The official image does not include pg8000, which the local pipeline uses.
set -euo pipefail

pip install --quiet 'pg8000>=1.31,<2' 'python-dotenv>=1.0,<2'

if [[ "${1:-}" == "init" ]]; then
  python - <<'PY'
import pg8000.dbapi

import os

connection = pg8000.dbapi.connect(
    user=os.environ.get("POSTGRES_USER", "retail"),
    password=os.environ.get("POSTGRES_PASSWORD", "retail"),
    host="postgres",
    port=int(os.environ.get("POSTGRES_PORT", "5432")),
    database=os.environ.get("POSTGRES_DB", "retail_analytics"),
)
connection.autocommit = True
cursor = connection.cursor()
cursor.execute("SELECT 1 FROM pg_database WHERE datname = 'airflow'")
if cursor.fetchone() is None:
    cursor.execute("CREATE DATABASE airflow")
connection.close()
PY
  airflow db migrate
  airflow users create \
    --username admin \
    --firstname Admin \
    --lastname User \
    --role Admin \
    --email admin@example.com \
    --password admin || true
  exit 0
fi

exec airflow "$@"
