# Study notes

Personal notes for understanding and defending this milestone. This file is not part of the GitHub submission.

The slides and what to say are in `presentation.md`. This page is the rules behind those slides.

## The point

Raw files are messy. The NL-to-SQL engine can only read Gold. If Gold is wrong, the UI still draws a chart, and the chart is wrong. Bronze keeps the original rows. Silver cleans them and records why a row was dropped. Gold totals each fact once. The checks stop the run when those totals do not agree.

I did not rebuild the engine, the UI, or `database/schemas/gold.sql`. The pipeline is the path those tools read from.

## Where the rules come from

The rules were chosen by profiling this `data/raw` in `notebooks/01_explore_raw.ipynb`. The SQL does not list `ORD-000001` or this file’s totals. Every run reads whatever Bronze loaded and applies the same rules.

A problem this extract never showed has no extra check. A missing customer on an order would still be loaded. A later copy with a different status would be kept, because that is already the duplicate rule.

## The flow

```text
data/raw → Bronze → Silver → quality gate → Gold → validate Gold → UI
```

Airflow task order in `dags/dag.py`:

1. `validate_raw_files` — the JSON and CSV files exist. `manifest.json` is not required.
2. `initialize_schemas` — create Bronze, Silver, Gold, and `ops` if they are missing.
3. `load_bronze` — one new `pipeline_run_id` for the whole run.
4. `build_silver` — rebuild Silver from Bronze.
5. `quality_gate` — Silver only. A failure stops Gold. A pass leaves the run `running`.
6. `build_gold` — rebuild the five Gold tables from Silver.
7. `validate_gold` — compare Gold with Silver. This step sets the run to `passed` or `failed`.

Each task waits for the one above it. A second trigger uses a new run id and replaces each layer. It does not append a second copy of Bronze, Silver, or Gold.

## Two databases

| Database           | What it holds                                           |
| ------------------ | ------------------------------------------------------- |
| `retail_analytics` | Bronze, Silver, Gold, and `ops`                         |
| `airflow`          | Airflow’s own task history, on the same Postgres server |

The requirement “record pipeline metadata” means `ops` in `retail_analytics`, not Airflow’s internal tables.

`ops.pipeline_runs` is one row per run: status, start, finish, error. `ops.quality_checks` is one row per check.

Local Postgres is the only place the pipeline writes. Neon is the instructor’s Gold sample. Bronze and Silver are never uploaded there.

From the Mac, `LOCAL_DATABASE_URL` uses `localhost`. Inside Docker, Airflow and the API use host `postgres`. The UI does not connect to Postgres. It calls the API at `http://nl2sql-api:8000`.

## manifest.json

Leave it out. It is metadata from the data generator: checksums, row counts, and the list of injected problems. It is not an order or an event. Bronze skips that filename. The instructor said to skip it, and this download does not include it. The written brief still shows the filename. If asked: the brief lists it, the file was not in the download, and `validate_raw_files` checks the data files.

## Bronze

One table, `bronze.raw_records`. Every JSON or CSV record becomes one row. The payload stays JSON. Duplicates and bad values stay. Bronze does not join, dedupe, or calculate metrics.

Columns that matter: `source_file`, `source_line_number` (position in the file, starting at 1), `source_record_id`, `payload`, `row_checksum`, `pipeline_run_id`.

Loading a file again deletes that file’s previous rows, then inserts the current file. A rerun does not stack a second copy.

`source_line_number` is not a column in the raw JSON. Pandas index 0 is line 1.

## Silver: who wins

Silver does not mix columns from two copies. Every business column on the stored row comes from the winning copy.

| Kind                                               | Identity                 | Winner                                                                                                   |
| -------------------------------------------------- | ------------------------ | -------------------------------------------------------------------------------------------------------- |
| Order                                              | `order_id`               | Later `updated_at_utc`. If the clock ties, the later line in the file (`source_line_number` descending). |
| Event (payment, refund, return, support, web)      | `event_id`               | Later `occurred_at_utc`, then the later line.                                                            |
| Item                                               | `order_item_id`          | After rejecting bad items, the later line.                                                               |
| Customer, product, store, channel, promotion, city | that id                  | One row. A repeated id keeps the later line.                                                             |
| Profile, category                                  | version row              | Every version stays. A repeated customer or product is history, not a duplicate.                         |
| Address                                            | `address_id`             | Kept, with `valid_from` / `valid_to`.                                                                    |
| Order promotion                                    | promotion row            | Several promotions on one order stay.                                                                    |
| Inventory                                          | observed day             | A missing day is not inserted and is not zero.                                                           |
| Campaign spend                                     | day + campaign + channel | One row. Spend is stored once.                                                                           |

`DISTINCT ON` keeps the first row after the sort. “First after the sort” means the latest update, then the later line. It does not mean the first line in the file.

Status words are not ranked. `FULFILLED` is not more true than `PLACED`. The later clock is the copy we store. We do not prove that copy is factually correct. We trust the source clock, then the file order.

`source_row_id` is not the tie-break, and it is not a `silver.orders` column.

### The one duplicate order

`ORD-000001` is in `operational/orders.json` twice.

|                 | Line 1                                                                                                                | Line 10001                 |
| --------------- | --------------------------------------------------------------------------------------------------------------------- | -------------------------- |
| `source_row_id` | `ORDER-ROW-0000001`                                                                                                   | `ORDER-ROW-DUPLICATE-0001` |
| Everything else | `CUST-01757`, ordered `2026-08-20T06:16:00Z`, updated `2026-08-20T23:16:00Z`, `MOBILE_APP`, `PLACED`, shipping `12.0` | same values                |

The clocks match, so line 10001 wins. Line 1 is `duplicate_order_id`. The word `DUPLICATE` in the id only marks the extra copy. Silver stores the same customer, channel, status, and shipping either way. Gold does not change for this order.

A repeated `order_id` on payments is several payments. It is not deduped. A repeated `event_id` is the duplicate.

## Silver: what is rejected

The loser stays in Bronze and is also written to `silver.rejected_records`.

| Reason                    | This extract |
| ------------------------- | ------------ |
| `duplicate_order_id`      | 1            |
| `duplicate_event_id`      | 2006         |
| `duplicate_order_item_id` | 0            |
| `negative_quantity`       | 1            |
| `missing_product`         | 3            |

A rejected item does not enter `silver.order_items`. Its order still stays in `silver.orders`.

These are not rejections:

- Empty `store_id` on a digital order stays null.
- Empty web `campaign_id` stays null.
- Empty support reason stays null.
- Profile and category extra rows are versions.
- A missing inventory day is left missing. It is not filled with zero.

There is no minimum `null_pct` that means failure. `null_pct` in the notebook is only the share of empty cells. Empty is a problem only when that field is required for the row to mean anything.

Order-level checks for a missing customer, a bad timestamp, or a missing channel were designed and then removed. They are not in the SQL.

## Business date

A timestamp that has `Z` or a numeric offset is converted to UTC. The business date is that UTC calendar day. A date-only field stays a calendar date. It is not shifted through a timezone.

## Gold

Gold reads Silver only. Sum a fact to its grain before joining promotions, campaigns, inventory, or events. A join before the sum would multiply the money.

Do not edit `gold.sql` names, columns, grains, or types.

| Table                    | One row means                  | This extract |
| ------------------------ | ------------------------------ | ------------ |
| `order_360`              | one order                      | 10000        |
| `customer_daily`         | one customer on one UTC day    | 12520        |
| `product_daily`          | one product on one UTC day     | 7200         |
| `channel_campaign_daily` | one day, channel, and campaign | 2616         |
| `executive_kpis_daily`   | one day                        | 90           |

### Money

`net_revenue` = gross merchandise value − promotion discount + shipping − completed refund.

- Gross merchandise value is `quantity * unit_price` on kept items.
- Discount is the sum of `silver.order_promotions.discount_amount` only. Do not also subtract `item_discount_amount`.
- Shipping comes from the order.
- `refunded_amount` is `REFUND_COMPLETED` only. `REFUND_ISSUED` stays out.
- `captured_payment_amount` is `PAYMENT_CAPTURED` only. `PAYMENT_AUTHORIZED` and `PAYMENT_FAILED` stay out.

On this database the Silver rebuild of that formula and `SUM(gold.order_360.net_revenue)` are both `13466989.83`.

### Labels Gold fills in

`gold.sql` does not list these words. The build sets them.

- `payment_status`: `CAPTURED` when captured amount > 0, otherwise `NOT_CAPTURED`.
- `return_status`: `RETURNED` when any return event exists, otherwise `NO_RETURN`.
- `first_order_flag`: the customer’s earliest `ordered_at_utc`. A tie keeps the smaller `order_id`.

### customer_daily

One customer per UTC date. A support-only day still gets a row, with zero money and a null active channel. Active channel is the channel with the most orders that day. A tie sorts the channel name first. `new_customer_flag` when the day is their first order date. `repeat_customer_flag` when they already had an earlier order.

### product_daily

Units, order count, and gross are summed from kept items before inventory or promotions are joined. Net revenue is the order’s net revenue times that product’s share of the order’s gross. A missing inventory day stays null. `stockout_flag` is true only when a snapshot exists and the summed available quantity is 0. Category is the product-category version that contains the start of that UTC day. `promotion_count` is a separate aggregate. It is not joined into the money sum.

### channel_campaign_daily

One campaign per order: the earliest web event on that order that has a `campaign_id`. This extract has no order with two campaigns. Spend is summed once per day, channel, and campaign. ROAS is attributed net revenue / spend. Spend of 0 makes ROAS null. `conversion_rate` is attributed orders / distinct web sessions, and null when there are no sessions.

### executive_kpis_daily

Reads the Gold tables that are already summed. It does not add the raw events again.

- AOV = net revenue / orders, otherwise 0.
- Refund rate = orders with a completed refund / orders with a captured payment. An unpaid order is on neither side.
- Return rate = orders with a return / all `order_360` rows that day.
- Repeat customer rate = ordering customers already flagged repeat / ordering customers.
- Stockout rate = products flagged stockout / products whose stockout flag is not null.
- Active customers = customers with `order_count` > 0.
- Support contact rate = support contacts / orders.
- Freshness is the latest `ingested_at_utc` across payment, refund, return, support, and web events.
- The date spine is order dates plus `product_daily` dates.

## The limit to defend

Refund events name the order, not the product. `product_daily` refunded units are that product’s quantity on orders whose `refunded_amount` > 0. A partial refund on a multi-product order overstates refunded units. The order total in `order_360` is still the completed refund amount.

## Quality checks

Both steps only read data and write a result into `ops`. Neither one changes Bronze, Silver, or Gold.

### Before Gold: `quality_gate`

This runs after Silver and before Gold. It looks only at Silver.

1. It marks this `pipeline_run_id` as `running` in `ops.pipeline_runs`.
2. It deletes any earlier rows for these three check names on that same run, then inserts them again.
3. It reads the three new rows.

| Check                      | What it counts                                                                   | Pass                                                                            |
| -------------------------- | -------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| `silver_orders_loaded`     | rows in `silver.orders`                                                          | the count is greater than 0                                                     |
| `duplicate_order_rejected` | orders stored twice, and rows with reason `duplicate_order_id`                   | no order is stored twice, and at least one losing copy is in `rejected_records` |
| `rejected_item_absent`     | `order_items` whose id was rejected for `negative_quantity` or `missing_product` | that count is 0                                                                 |

These three are the stop signal.

- `silver_orders_loaded` stops the run when Silver has no orders. Building Gold from an empty order table would produce empty totals.
- `duplicate_order_rejected` stops the run when one `order_id` is stored twice. Gold is one row per order, so a repeated order would be counted twice. It also requires the losing copy to be in `rejected_records`. On this extract that losing copy is the one extra order.
- `rejected_item_absent` stops the run when an item rejected for `negative_quantity` or `missing_product` is still in `silver.order_items`. Those rows would be added into gross revenue.

The other cleanup still happens in `build_silver`. Duplicate events are written to `rejected_records` there. The gate does not count them again. Refunds, captured payments, and net revenue are checked later in `validate_gold`, because those checks need the Gold tables, which do not exist yet.

If any of the three fails, the run is set to `failed` and Airflow does not start `build_gold`. If all three pass, the run stays `running`. Gold has not been built yet, so this step does not say the pipeline passed.

### Then Gold is built

`build_gold` fills the five Gold tables, including `order_360.net_revenue`. That happens only after the gate passes.

### After Gold: `validate_gold`

This runs after Gold exists. It compares totals. It does not rebuild Silver or Gold.

1. It marks the same run `running` again.
2. It deletes any earlier rows for these six check names, then inserts them again.
3. It reads those six rows. The three gate rows stay.

| Check                | Expected                                                                          | Observed                                   |
| -------------------- | --------------------------------------------------------------------------------- | ------------------------------------------ |
| `order_grain`        | count of `silver.orders`                                                          | count of `gold.order_360`                  |
| `revenue_match`      | item gross − promotion discount + shipping − completed refunds, added from Silver | `SUM(gold.order_360.net_revenue)`          |
| `refund_match`       | sum of Silver `REFUND_COMPLETED`                                                  | sum of Gold `refunded_amount`              |
| `captured_match`     | sum of Silver `PAYMENT_CAPTURED`                                                  | sum of Gold `captured_payment_amount`      |
| `item_revenue_match` | sum of Silver `quantity * unit_price`                                             | sum of Gold gross merchandise value        |
| `daily_orders_match` | count of `gold.order_360`                                                         | sum of `executive_kpis_daily.total_orders` |

`SUM(gold.order_360.net_revenue)` is the net revenue column `build_gold` already stored, added across every order. `revenue_match` only reads Silver to add the expected number. A `failed` row does not update Silver. It means the Gold formula does not match that Silver total, so the fix is in `build_gold.sql`, then run the pipeline again. Silver can still be wrong while this check passes, because both numbers are built from the same Silver tables.

`daily_orders_match` is Gold against Gold. It catches a daily rollup that dropped or doubled orders.

If any of the six fails, the run is set to `failed`. If all six pass, this is the step that sets the run to `passed` and fills `finished_at`.

A retry deletes that step’s check names for the same `pipeline_run_id`, then inserts them again. An old `failed` row does not stay and fail the new attempt. A brand-new DAG trigger gets a new run id, so the previous run’s rows stay as history.

## What a question does

Natural language goes to the API. The API writes a read-only `SELECT` on `gold.*`, runs it on local Gold, and the UI draws the chart and the table from the same rows. Open **Show SQL and provenance** to name the Gold table. The question does not read Bronze or Silver.

Demo question, exact wording: `Show me net revenue trend for the last 30 days`. The table is `gold.executive_kpis_daily`.

Login for Airflow is `admin` / `admin` at [http://localhost:8080](http://localhost:8080). The UI is [http://localhost:8501](http://localhost:8501). Start the UI only after Gold exists.

## If they ask

- **Why the later line, not the first?** The sort is latest `updated_at_utc`, then higher `source_line_number`. On `ORD-000001` the clocks match and the business fields match, so the stored order is the same.
- **Why not trust the row labeled DUPLICATE?** That word is only in `source_row_id`. Silver does not store that column. The pipeline does not look for the word.
- **Does this only work on today’s file?** The rules were chosen from this extract. They are not hardcoded to these ids. A new kind of problem has no extra check.
- **Why is the manifest missing?** Metadata only, not in the download, instructor said skip it.
- **Why can the chart be wrong?** The engine only sees Gold. The checks exist so Gold matches Silver before anyone asks a question.
