# Timing and speech

10–15 minutes, including questions. Talk for about 6 minutes. Demo for about 3. Leave the rest for questions.

If the slot is only 10 minutes, skip the profile-history and missing-inventory lines on slide 5. Keep the duplicate order and the missing product.

Have these open before you start:

| Ready      | Where                                                                                                        |
| ---------- | ------------------------------------------------------------------------------------------------------------ |
| Slide deck | This talk                                                                                                    |
| Airflow    | [localhost:8080](http://localhost:8080) — green run of `retail_analytics_pipeline` — login `admin` / `admin` |
| UI         | [localhost:8501](http://localhost:8501)                                                                      |
| Backup     | `evidence/airflow_run.png` if the live DAG is slow                                                           |

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
| 10 Close        | 15s   | Local Postgres, then questions                   |

---

## 1 · Title

**20 seconds**

> I built the data path for an omnichannel retailer. Orders, payments, refunds, inventory, and campaign spend start as raw files. They end in PostgreSQL Gold. The NL-to-SQL engine and the UI were already provided. I did not rebuild them.

Stand on this slide. Do not open the demo yet.

---

## 2 · The point

**30 seconds**

> The files have duplicate orders, split payments, partial refunds, mixed timezones, missing products, and inventory days that never arrived. The engine never sees Bronze or Silver. If Gold is wrong, the UI still shows a chart, and that chart is wrong. The pipeline exists so the chart matches the source.

Point at the third line when you say the chart can be wrong.

---

## 3 · The flow

**25 seconds**

> Raw files land in Bronze unchanged. Silver types them, keeps one winner for a duplicate, and records the loser with a reason. The quality gate checks Silver and can stop Gold. Gold builds five tables. Validate Gold compares those totals with Silver. Only then does the UI ask a question.

Move your hand along the diagram once. Do not explain every table yet.

---

## 4 · Airflow tasks

**40 seconds**

> Airflow runs these seven tasks from `dags/dag.py`. Each task waits for the one above it. `load_bronze` creates one `pipeline_run_id` for the whole run. If the Silver gate fails, Gold does not build. `validate_gold` has to run after Gold, because it compares Gold totals with Silver. An empty Gold table would fail that check. A second trigger uses a new run id and replaces each layer. It does not append a copy.

If the corner picture is there, point at `quality_gate` and then `build_gold`. Stay on the slide. The live Airflow screen is the demo.

---

## 5 · What we clean

**40 seconds**

> Bronze keeps every source record. Silver is the cleanup. A repeated order, event, or item keeps one winner. The losing copy is stored in `rejected_records` with that reason. An item with a negative quantity, or a product that is not in the product file, is rejected and does not enter `order_items`. Profile and category history is not a rejection. Those rows stay as versions. A missing inventory day is not filled with zero, and it is not a rejection either.

Point at `duplicate_order_id` and `missing_product`. Do not open the database.

On a 10-minute slot, stop after the missing product. Skip profile history and the missing inventory day.

---

## 6 · What we check

**45 seconds**

> The gate before Gold looks only at Silver. It checks that orders loaded, that the duplicate order was rejected, and that a rejected item is not in `order_items`. It does not recheck every rejection reason. If this gate fails, Gold does not build. After Gold exists, six checks compare Gold totals with Silver. Same order count, same net revenue, same completed refunds, same captured payments, same item revenue, and the same daily order total. Those six cannot run first. An empty Gold table would fail the order count.

Point at the before-Gold group, then the after-Gold group.

---

## 7 · Gold

**35 seconds**

> Gold reads Silver only. Each table has one grain. Money is summed to that grain before any join, so a promotion or a campaign cannot double the revenue. The discount in net revenue is the promotion total only. Completed refunds are the only refunds that reduce it. `executive_kpis_daily` reads the other Gold tables. It does not add the raw events again.

Point at the formula, then at `executive_kpis_daily`.

---

## 8 · Demo

**3 minutes**

> I will show a finished run, then one question against local Gold.

1. Switch to Airflow. Show `retail_analytics_pipeline` with all seven tasks green. Say the name of `quality_gate` and `validate_gold` as you point at them. If the screen is slow, use `evidence/airflow_run.png`.
2. Switch to [localhost:8501](http://localhost:8501).
3. Ask, exactly: `Show me net revenue trend for the last 30 days`
4. Wait for the chart and the table.
5. Open **Show SQL and provenance** and read `gold.executive_kpis_daily`.
6. Say: this query did not touch Bronze or Silver.

Come back to the slides. Do not ask a second question unless someone requests it.

---

## 9 · Evaluasi

**40 seconds**

> This is the limit I would fix next. Refund events do not carry a product id, so I cannot know which item was refunded. On `product_daily`, refunded units are the product’s quantity on orders that have a completed refund. If an order has two products and only one was refunded, both products can look refunded. The order-level refund total in `order_360` is still the completed refund amount. The weak spot is the product split.

> The hard part was the rules the brief does not spell out. The Gold contract fixes the table names, the grains, and net revenue. It does not say which copy wins when an order is repeated, whether a missing inventory day is zero, or whether profile history is a duplicate. I read the raw files and chose those rules. Every run applies the same rules. Next I would put a product id on refunds, so `product_daily` can split a partial refund instead of marking every product on that order. I would also add checks for assumed cases this file does not contain, such as an order with no customer or a clock that cannot be parsed. On this extract those checks would reject nothing.

Stay on the slide. Do not open SQL. Point at the refund lines, then at the two cues.

---

## 10 · Close

**15 seconds**

> The pipeline runs on my machine. Neon stays the instructor sample. I can take questions.

Stop sharing the demo. Leave this slide up for questions.
