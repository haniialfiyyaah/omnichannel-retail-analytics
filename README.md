# Omnichannel Retail Analytics

A local data pipeline for an omnichannel retailer. Orders, payments, refunds, returns, support contacts, web activity, inventory, and campaign spend start as raw files. The pipeline loads them into PostgreSQL as Bronze, Silver, and Gold. A provided NL-to-SQL engine then answers questions from Gold and shows a chart and a table.

This repo does not rebuild the engine, the UI, or the Gold table contract. It builds the path those tools read from.

## The point

The source data is messy: duplicate orders, split payments, partial refunds, mixed timezones, missing products, and inventory days that never arrived. The engine can only see Gold. If Gold is wrong, a question still returns a chart, and the chart is wrong. Bronze keeps the original records, Silver rejects bad rows and says why, Gold totals each fact once, and the checks stop the run when those totals do not add up.

The assignment brief is [instruction_brief.md](instruction_brief.md). Table names, grains, and metric formulas are fixed in `[database/schemas/gold.sql](database/schemas/gold.sql)`.

## Pipeline

```mermaid
flowchart TD
  raw["data/raw"]
  bronze["Bronze"]
  silver["Silver"]
  gate["Quality gate"]
  gold["Gold"]
  validate["Validate Gold"]
  ui["Engine and UI"]

  raw --> bronze --> silver --> gate --> gold --> validate --> ui
```

One trigger of `[dags/dag.py](dags/dag.py)` runs these tasks in order. Each task starts only after the one above it succeeds. `quality_gate` stops the run before `build_gold` when Silver fails. `validate_gold` runs after Gold exists, because it compares Gold totals with Silver. The engine and UI are not tasks in this DAG. They start after the run is green.

| Task                 | What it does                                                       |
| -------------------- | ------------------------------------------------------------------ |
| `validate_raw_files` | Checks the JSON and CSV files under `data/raw`                     |
| `initialize_schemas` | Creates Bronze, Silver, Gold, and `ops` if they are missing        |
| `load_bronze`        | Creates one `pipeline_run_id` and reloads Bronze                   |
| `build_silver`       | Rebuilds Silver from that Bronze                                   |
| `quality_gate`       | Checks Silver and records the result in `ops`                      |
| `build_gold`         | Rebuilds the five Gold tables                                      |
| `validate_gold`      | Compares Gold with Silver and sets the run to `passed` or `failed` |

A second trigger uses a new `pipeline_run_id` and replaces each layer instead of appending a copy.

| Database           | What it holds                                   |
| ------------------ | ----------------------------------------------- |
| `retail_analytics` | Bronze, Silver, Gold, and `ops`                 |
| `airflow`          | Airflow run history on the same Postgres server |

Bronze and Silver stay on this machine. They are not loaded into Neon.

## Layers

### 1. Raw files and schemas

`validate_raw_files` checks that the JSON and CSV files are under `data/raw`. `initialize_schemas` creates the empty Bronze, Silver, Gold, and `ops` tables when they are missing. `manifest.json` is not required.

### 2. Bronze

Bronze is source evidence. Each record becomes one row in `bronze.raw_records`. The payload stays JSON, including duplicates and invalid values. Nothing is joined or totaled. Loading a file again deletes that file's previous rows and inserts them again.

### 3. Silver

Silver reads Bronze and writes typed tables.

- Timestamps that carry a timezone are stored in UTC.
- A repeated `order_id` or `event_id` keeps one winner. The losing copy stays in Bronze and is also written to `silver.rejected_records` with a reason, such as `duplicate_order_id`.
- An item with a negative quantity or an unknown product is rejected and does not enter `silver.order_items`.
- Customer profile and product category history is kept as versions.
- A missing inventory day stays missing. It is not filled with zero.

### 4. Quality gate

The gate runs after Silver and before Gold. It checks Silver only:

- `silver.orders` has rows.
- A duplicate order is in `silver.rejected_records` and is not stored twice.
- A rejected item is absent from `silver.order_items`.

A failure is stored in `ops.quality_checks`. Airflow does not start `build_gold`.

### 5. Gold

Gold reads Silver only. Amounts are aggregated to the table grain before any join, so a promotion or campaign cannot multiply units or revenue.

| Table                    | One row per                            |
| ------------------------ | -------------------------------------- |
| `order_360`              | order                                  |
| `customer_daily`         | customer and day                       |
| `product_daily`          | product and day                        |
| `channel_campaign_daily` | day, channel, and campaign             |
| `executive_kpis_daily`   | day, summed from the other Gold tables |

`net_revenue` = gross merchandise value − promotion discount + shipping − completed refunds.

### 6. Validate Gold

These checks compare Gold with Silver after Gold has been built:

- order count
- net revenue
- completed refunds
- captured payments
- item revenue
- daily order totals

Results are written to `ops.quality_checks` on the same `pipeline_run_id`. They cannot run on an empty Gold table. The order-count check would fail, and Gold would never load.

### 7. Engine and UI

A question goes from the Streamlit page to the API. The API writes a read-only `SELECT` on `gold.*`, runs it, and the UI draws a chart and a table from the same rows. Bronze and Silver are not queried.

## Run it

### Setup

Put the raw files in `data/raw/` (`operational`, `events`, `inventory`, `reference`).

Create `.env` for commands on your Mac. Do not commit it.

```text
ANALYTICS_DB_TARGET=local
LOCAL_DATABASE_URL=postgresql://retail:retail@localhost:5432/retail_analytics
NL2SQL_PROVIDER=openai
OPENAI_API_KEY=
OPENAI_BASE_URL=https://api.openai.com/v1
OPENAI_MODEL=gpt-4.1-mini
NL2SQL_MAX_ROWS=100
```

`LOCAL_DATABASE_URL` uses `localhost` because those commands run on the Mac. Inside Compose, the API and Airflow use host `postgres`. The provider and API key are read from `.env` when the API container starts.

### Pipeline

```bash
docker-compose up -d postgres airflow-init airflow-webserver airflow-scheduler
docker-compose ps
```

`airflow-init` should be exited with code 0. `postgres` should be healthy.

Open [http://localhost:8080](http://localhost:8080) and sign in as `admin` / `admin`. Trigger **retail_analytics_pipeline**.

A good run:

- all seven tasks are green
- `ops.pipeline_runs` has a new row with status `passed`

### UI

Start this after Gold exists.

```bash
docker-compose up -d --force-recreate nl2sql-api analytics-ui
```

Open [http://localhost:8501](http://localhost:8501). Ask a question. The page shows SQL, a chart, and a table.

## Evidence

| File                                                                   | What it shows                              |
| ---------------------------------------------------------------------- | ------------------------------------------ |
| [evidence/airflow_run.png](evidence/airflow_run.png)                   | A green DAG run                            |
| [evidence/sample_engine_queries.md](evidence/sample_engine_queries.md) | Questions, SQL, and the charts the UI drew |
