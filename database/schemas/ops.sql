-- Ops stores pipeline runs and quality-check results.
-- A failed check is recorded here. The runner then stops before a later step.

CREATE SCHEMA IF NOT EXISTS ops;

CREATE TABLE IF NOT EXISTS ops.pipeline_runs (
    pipeline_run_id TEXT PRIMARY KEY,
    status TEXT NOT NULL,
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    finished_at TIMESTAMPTZ,
    error_message TEXT
);

-- One row per check in a run. expected_value and observed_value are the two totals compared.
CREATE TABLE IF NOT EXISTS ops.quality_checks (
    quality_check_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    pipeline_run_id TEXT NOT NULL,
    check_name TEXT NOT NULL,
    status TEXT NOT NULL,
    expected_value NUMERIC(18, 2) NOT NULL,
    observed_value NUMERIC(18, 2) NOT NULL,
    checked_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
