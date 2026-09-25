# Presentation

10–15 minutes, including questions. Talk for about 6 minutes, demo for about 3, and leave the rest for questions. If the slot is only 10 minutes, skip the profile-history and missing-inventory lines on slide 5.

Build the slides from this page. Each block is one slide: what is on the screen, what you say, and what you do. The Say lines are the speech. Timing, what to remember, and likely questions are at the bottom.

The required order is Pendahuluan (slides 1–2), Solusi & Teknis (slides 3–7), live demo (slide 8), then Evaluasi (slide 9). Slide 10 is the close.

| Required part                                 | Slides | Status  |
| --------------------------------------------- | ------ | ------- |
| Pendahuluan: background and the problem       | 1–2    | Covered |
| Solusi & Teknis: approach, architecture, flow | 3–7    | Covered |
| Live demo                                     | 8      | Covered |
| Evaluasi: obstacles and what comes next       | 9      | Covered |

Before you start, have these open:

- The slide deck.
- Airflow at [http://localhost:8080](http://localhost:8080), on a green run of `retail_analytics_pipeline`.
- The UI at [http://localhost:8501](http://localhost:8501).
- `evidence/airflow_run.png` if the live DAG is slow to load.

## 1. Title

**On the slide**

- Title: Omnichannel Retail Analytics
- One line: raw files to a Gold layer the engine can question
- Your name

**Say**

I built the data path for an omnichannel retailer. Orders, payments, refunds, inventory, and campaign spend start as raw files. They end in PostgreSQL Gold. The NL-to-SQL engine and the UI were already provided. I did not rebuild them.

**Do**

Stand on this slide. Do not open the demo yet.

## 2. The point

**On the slide**

- Three short lines, not a paragraph:
  - The source data is messy.
  - The engine can only read Gold.
  - A wrong Gold layer still draws a chart.
- No screenshot.

**Say**

The files have duplicate orders, split payments, partial refunds, mixed timezones, missing products, and inventory days that never arrived. The engine never sees Bronze or Silver. If Gold is wrong, the UI still shows a chart, and that chart is wrong. The pipeline exists so the chart matches the source.

**Do**

Point at the third line when you say the chart can be wrong.

## 3. The flow

**On the slide**

- One diagram, left to right:

```text
data/raw → Bronze → Silver → quality gate → Gold → validate Gold → UI
```

- Nothing else. No SQL.

**Say**

Raw files land in Bronze unchanged. Silver types them, keeps one winner for a duplicate, and records the loser with a reason. The quality gate checks Silver and can stop Gold. Gold builds five tables. Validate Gold compares those totals with Silver. Only then does the UI ask a question.

**Do**

Move your hand along the diagram once. Do not explain every table yet.

## 4. Airflow tasks

**On the slide**

- The seven task names, in order:
  1. `validate_raw_files`
  2. `initialize_schemas`
  3. `load_bronze`
  4. `build_silver`
  5. `quality_gate`
  6. `build_gold`
  7. `validate_gold`
- One note: a failed `quality_gate` does not start `build_gold`.
- Optional picture: `evidence/airflow_run.png`, small, in the corner.

**Say**

Airflow runs these seven tasks from `dags/dag.py`. Each task waits for the one above it. `load_bronze` creates one `pipeline_run_id` for the whole run. If the Silver gate fails, Gold does not build. `validate_gold` has to run after Gold, because it compares Gold totals with Silver. An empty Gold table would fail that check. A second trigger uses a new run id and replaces each layer. It does not append a copy.

**Do**

If the corner picture is there, point at `quality_gate` and then `build_gold`. Stay on the slide. The live Airflow screen is the demo.

## 5. What we clean

**On the slide**

- Title: What we clean
- Five reasons written to `silver.rejected_records`:
  - `duplicate_order_id`
  - `duplicate_event_id`
  - `duplicate_order_item_id`
  - `negative_quantity`
  - `missing_product`
- One line under the list: the winner stays in Silver. The loser stays in Bronze too.

**Say**

Bronze keeps every source record. Silver is the cleanup. A repeated order, event, or item keeps one winner. The losing copy is stored in `rejected_records` with that reason. An item with a negative quantity, or a product that is not in the product file, is rejected and does not enter `order_items`. Profile and category history is not a rejection. Those rows stay as versions. A missing inventory day is not filled with zero, and it is not a rejection either.

**Do**

Point at `duplicate_order_id` and `missing_product`. Do not open the database.

## 6. What we check

**On the slide**

- Two groups.

Before Gold, the quality gate:

- Orders loaded
- Duplicate order rejected, and not stored twice
- Rejected item absent from `order_items`

After Gold, validate Gold:

- Order count
- Net revenue
- Completed refunds
- Captured payments
- Item revenue
- Daily order totals

**Say**

The gate before Gold looks only at Silver. It checks that orders loaded, that the duplicate order was rejected, and that a rejected item is not in `order_items`. It does not recheck every rejection reason. If this gate fails, Gold does not build. After Gold exists, six checks compare Gold totals with Silver. Same order count, same net revenue, same completed refunds, same captured payments, same item revenue, and the same daily order total. Those six cannot run first. An empty Gold table would fail the order count.

**Do**

Point at the before-Gold group, then the after-Gold group.

## 7. Gold

**On the slide**

- A five-row table:

| Table                    | One row per                |
| ------------------------ | -------------------------- |
| `order_360`              | order                      |
| `customer_daily`         | customer and day           |
| `product_daily`          | product and day            |
| `channel_campaign_daily` | day, channel, and campaign |
| `executive_kpis_daily`   | day                        |

- One formula: `net_revenue` = gross merchandise value − promotion discount + shipping − completed refunds.

**Say**

Gold reads Silver only. Each table has one grain. Money is summed to that grain before any join, so a promotion or a campaign cannot double the revenue. The discount in net revenue is the promotion total only. Completed refunds are the only refunds that reduce it. `executive_kpis_daily` reads the other Gold tables. It does not add the raw events again.

**Do**

Point at the formula, then at `executive_kpis_daily`.

## 8. Demo

**On the slide**

- Two lines only:
  - Airflow: seven green tasks
  - UI: one question, then the chart, the table, and the SQL

**Say**

I will show a finished run, then one question against local Gold.

**Do**

1. Switch to Airflow. Show `retail_analytics_pipeline` with all seven tasks green. Say the name of `quality_gate` and `validate_gold` as you point at them. If the UI is slow, use `evidence/airflow_run.png`.
2. Switch to [http://localhost:8501](http://localhost:8501).
3. Ask, exactly: `Show me net revenue trend for the last 30 days`
4. Wait for the chart and the table.
5. Open **Show SQL and provenance** and read the table name `gold.executive_kpis_daily`.
6. Say: this query did not touch Bronze or Silver.

Come back to the slides. Do not ask a second question unless someone requests it.

## 9. Evaluasi

**On the slide**

- Title: Refunds have no product id
- Two lines:
  - A refund event names the order, not the product.
  - `product_daily` counts that product’s units on any refunded order, so a partial refund in a multi-product order is overstated.
- Two cues under that:
  - Hard part: The contract names the tables. It does not say which copy wins.
  - Next: a product id on the refund, and checks for cases this file does not contain.

**Say**

This is the limit I would fix next. Refund events do not carry a product id, so I cannot know which item was refunded. On `product_daily`, refunded units are the product’s quantity on orders that have a completed refund. If an order has two products and only one was refunded, both products can look refunded. The order-level refund total in `order_360` is still the completed refund amount. The weak spot is the product split.

The hard part was the rules the brief does not spell out. The Gold contract fixes the table names, the grains, and net revenue. It does not say which copy wins when an order is repeated, whether a missing inventory day is zero, or whether profile history is a duplicate. I read the raw files and chose those rules. Every run applies the same rules. Next I would put a product id on refunds, so `product_daily` can split a partial refund instead of marking every product on that order. I would also add checks for assumed cases this file does not contain, such as an order with no customer or a clock that cannot be parsed. On this extract those checks would reject nothing.

**Do**

Stay on the slide. Do not open SQL. Point at the refund lines, then at the two cues.

## 10. Close

**On the slide**

- Main point: The chart matches the source.
- Bronze keeps every raw record.
- Silver keeps one winner and records the loser.
- Gold sums the money before any join.
- The checks compare Silver totals with Gold before a question.
- Thank you.

**Say**

The chart matches the source. Bronze keeps every raw record. Silver keeps one winner and records the loser. Gold sums the money before any join. The checks compare Silver totals with Gold before anyone asks a question. I can take questions.

**Do**

Stop sharing the demo. Leave this slide up for questions.

## Timing

| Slide           | Time  | What you are doing                               |
| --------------- | ----- | ------------------------------------------------ |
| 1 Title         | 20s   | Who you are and what you built                   |
| 2 The point     | 30s   | Why a wrong Gold layer is dangerous              |
| 3 The flow      | 25s   | One pass along the diagram                       |
| 4 Airflow       | 40s   | Seven tasks, and that a failed gate blocks Gold  |
| 5 What we clean | 40s   | Winner stays, loser is recorded                  |
| 6 What we check | 45s   | Three checks before Gold, six after              |
| 7 Gold          | 35s   | Five grains and the net-revenue formula          |
| 8 Demo          | 3 min | Green DAG, then one question                     |
| 9 Evaluasi      | 40s   | Refund limit, then the rules the brief left open |
| 10 Close        | 30s   | Main point, then the four details                |

## Remember

- You built the path. You did not build the engine, the UI, or `gold.sql`.
- Two databases on the same server: `retail_analytics` holds Bronze, Silver, Gold, and `ops`. `airflow` is only Airflow’s task history.
- A green gate means the run is still `running`. Only `validate_gold` sets `passed`.
- Winner rule, if they push: latest timestamp, then the later line in the file. Status words are not ranked. The word `DUPLICATE` in the source id is not a rule.
- Discount in net revenue is the promotion total only. Do not also subtract the item discount. Only `REFUND_COMPLETED` reduces revenue. Only `PAYMENT_CAPTURED` counts as captured.
- `revenue_match` can pass while Silver is still wrong, because both sides are built from Silver. The gate is what stops a bad Silver row from becoming Gold.
- `manifest.json` is in the written brief and was not in this download. `validate_raw_files` checks the data files. If asked, say that and stop.
- Do not quote row counts unless they ask. If they do: one duplicate order, 2,006 duplicate events, one negative quantity, three missing products. `order_360` has 10,000 rows. Net revenue on this database is `13,466,989.83`.
- Airflow login is `admin` / `admin`. If the live DAG is slow, use `evidence/airflow_run.png`.
- Demo question, exact wording: `Show me net revenue trend for the last 30 days`. The table is `gold.executive_kpis_daily`. Do not ask a second question unless someone requests it.

## If they ask

**Why does the later line win, not the first?** The sort is latest `updated_at_utc`, then the higher line number. On `ORD-000001` the clocks match and the business fields match, so Gold is the same either way.

**Why not trust the row labeled DUPLICATE?** That word is only in `source_row_id`. Silver does not store that column and does not look for the word.

**What if the quality gate fails?** The run is marked `failed` in `ops.pipeline_runs`, and Airflow does not start `build_gold`.

**Why are there only three checks before Gold?** Those three can be answered from Silver alone: orders exist, no order is stored twice, and a rejected item is absent. Refunds, captured payments, and net revenue need the Gold tables, so they run in `validate_gold`.

**How do you avoid double-counting revenue?** Sum each fact to its grain before joining promotions, campaigns, inventory, or events. One order can have several promotions. Joining first would repeat the order’s money.

**Why is a missing inventory day not zero?** Zero would mean the store counted the stock and had none. A missing snapshot means that day never arrived. `stockout_flag` is true only when a snapshot exists and available quantity is 0.

**Are profile changes duplicates?** No. Every customer-profile and product-category version stays. A repeated `order_id` or `event_id` is the duplicate.

**Is a second payment on the same order a duplicate?** No. Payments are deduped by `event_id`. Several payments on one order are split payments and all stay.

**What does a rerun do?** A new trigger gets a new `pipeline_run_id` and replaces Bronze, Silver, and Gold. It does not stack a second copy. A retry of the same run deletes that step’s old check rows and inserts them again.

**Why can the chart still be wrong?** The engine only reads `gold.*`. If Gold were built from bad Silver and the checks were skipped, the UI would still draw the chart. The checks are what stop that run.

**What was the hard part?** The Gold contract fixes the table names, the grains, and net revenue. It does not say which copy wins when an order is repeated, whether a missing inventory day is zero, or whether profile history is a duplicate. Those rules were chosen by reading the raw files, then every run applies the same rules.

**What would you change next?** Add a product id to refund events, then allocate refunded units on `product_daily` to that product. Today a partial refund on a multi-product order can mark every product on the order as refunded. The order total in `order_360` is still the completed refund amount. Also add checks for assumed cases this file does not contain, such as an order with no customer or a clock that cannot be parsed. On this extract those checks would reject nothing.
