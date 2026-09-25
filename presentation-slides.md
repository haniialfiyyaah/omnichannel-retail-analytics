# Slide design

What appears on each slide. Speech and timing are in [presentation-speech.md](presentation-speech.md).

Pendahuluan is slides 1–2. Solusi & Teknis is slides 3–7. The live demo is slide 8. Evaluasi is slide 9. Slide 10 is the close.

| Part                                           | Slides | Status  |
| ---------------------------------------------- | ------ | ------- |
| Pendahuluan — background and the problem       | 1–2    | Covered |
| Solusi & Teknis — approach, architecture, flow | 3–7    | Covered |
| Live demo                                      | 8      | Covered |
| Evaluasi — obstacles and what comes next       | 9      | Covered |

---

## 1 · Title

**Pendahuluan**

|       |                                                   |
| ----- | ------------------------------------------------- |
| Title | Omnichannel Retail Analytics                      |
| Line  | raw files to a Gold layer the engine can question |
| Name  | Your name                                         |

---

## 2 · The point

**Pendahuluan**

Three short lines. No paragraph. No screenshot.

1. The source data is messy.
2. The engine can only read Gold.
3. A wrong Gold layer still draws a chart.

---

## 3 · The flow

**Solusi & Teknis**

One diagram, left to right. Nothing else. No SQL.

```text
data/raw  →  Bronze  →  Silver  →  quality gate  →  Gold  →  validate Gold  →  UI
```

---

## 4 · Airflow tasks

**Solusi & Teknis**

Seven task names, in order. One note under the list. Optional: `evidence/airflow_run.png`, small, in the corner.

| #   | Task                 |
| --- | -------------------- |
| 1   | `validate_raw_files` |
| 2   | `initialize_schemas` |
| 3   | `load_bronze`        |
| 4   | `build_silver`       |
| 5   | `quality_gate`       |
| 6   | `build_gold`         |
| 7   | `validate_gold`      |

> A failed `quality_gate` does not start `build_gold`.

---

## 5 · What we clean

**Solusi & Teknis**

Title: **What we clean**

Five reasons written to `silver.rejected_records`:

| Reason                    |
| ------------------------- |
| `duplicate_order_id`      |
| `duplicate_event_id`      |
| `duplicate_order_item_id` |
| `negative_quantity`       |
| `missing_product`         |

> The winner stays in Silver. The loser stays in Bronze too.

---

## 6 · What we check

**Solusi & Teknis**

Two groups.

**Before Gold — the quality gate**

- Orders loaded
- Duplicate order rejected, and not stored twice
- Rejected item absent from `order_items`

**After Gold — validate Gold**

- Order count
- Net revenue
- Completed refunds
- Captured payments
- Item revenue
- Daily order totals

---

## 7 · Gold

**Solusi & Teknis**

| Table                    | One row per                |
| ------------------------ | -------------------------- |
| `order_360`              | order                      |
| `customer_daily`         | customer and day           |
| `product_daily`          | product and day            |
| `channel_campaign_daily` | day, channel, and campaign |
| `executive_kpis_daily`   | day                        |

> `net_revenue` = gross merchandise value − promotion discount + shipping − completed refunds

---

## 8 · Demo

**Live demo**

Two lines only.

- Airflow: seven green tasks
- UI: one question, then the chart, the table, and the SQL

---

## 9 · Evaluasi

**Evaluasi**

Title: **Refunds have no product id**

- A refund event names the order, not the product.
- `product_daily` counts that product’s units on any refunded order, so a partial refund in a multi-product order is overstated.

| Cue       | Line                                                                         |
| --------- | ---------------------------------------------------------------------------- |
| Hard part | The contract names the tables. It does not say which copy wins.              |
| Next      | A product id on the refund, and checks for cases this file does not contain. |

---

## 10 · Close

- Local PostgreSQL holds Bronze, Silver, Gold, and `ops`.
- Airflow’s own history is a separate database on that same server.
- Bronze and Silver are not uploaded to Neon.
- Thank you.
