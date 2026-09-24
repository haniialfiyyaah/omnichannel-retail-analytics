-- Bronze stores source evidence. Rows are not deduped or turned into metrics here.
-- One table holds every raw file. source_file tells which file a row came from.

CREATE SCHEMA IF NOT EXISTS bronze;

CREATE TABLE IF NOT EXISTS bronze.raw_records (
    -- Surrogate key so two copies of the same order can both be stored.
    bronze_row_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    -- Relative path under data/raw, for example operational/orders.json.
    source_file TEXT NOT NULL,
    source_line_number INTEGER NOT NULL,
    -- Id inside the payload, such as order_id or event_id. Repeats are allowed.
    source_record_id TEXT,
    -- Original row, unchanged. CSV rows are stored as JSON objects too.
    payload JSONB NOT NULL,
    row_checksum TEXT NOT NULL,
    pipeline_run_id TEXT NOT NULL,
    ingested_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
