# Questions they are likely to ask

Short answers. Stop after the answer.

---

### Why does the later line win, not the first?

The sort is latest `updated_at_utc`, then the higher line number. On `ORD-000001` the clocks match and the business fields match, so Gold is the same either way.

### Why not trust the row labeled DUPLICATE?

That word is only in `source_row_id`. Silver does not store that column and does not look for the word.

### What if the quality gate fails?

The run is marked `failed` in `ops.pipeline_runs`, and Airflow does not start `build_gold`.

### Why are there only three checks before Gold?

Those three can be answered from Silver alone: orders exist, no order is stored twice, and a rejected item is absent. Refunds, captured payments, and net revenue need the Gold tables, so they run in `validate_gold`.

### How do you avoid double-counting revenue?

Sum each fact to its grain before joining promotions, campaigns, inventory, or events. One order can have several promotions. Joining first would repeat the order’s money.

### Why is a missing inventory day not zero?

Zero would mean the store counted the stock and had none. A missing snapshot means that day never arrived. `stockout_flag` is true only when a snapshot exists and available quantity is 0.

### Are profile changes duplicates?

Every customer-profile and product-category version stays. A repeated `order_id` or `event_id` is the duplicate.

### Is a second payment on the same order a duplicate?

Payments are deduped by `event_id`. Several payments on one order are split payments and all stay.

### What does a rerun do?

A new trigger gets a new `pipeline_run_id` and replaces Bronze, Silver, and Gold. It does not stack a second copy. A retry of the same run deletes that step’s old check rows and inserts them again.

### Why can the chart still be wrong?

The engine only reads `gold.*`. If Gold were built from bad Silver and the checks were skipped, the UI would still draw the chart. The checks are what stop that run.

### What was the hard part?

The Gold contract fixes the table names, the grains, and net revenue. It does not say which copy wins when an order is repeated, whether a missing inventory day is zero, or whether profile history is a duplicate. Those rules were chosen by reading the raw files, then every run applies the same rules.

### What would you change next?

Add a product id to refund events, then allocate refunded units on `product_daily` to that product. Today a partial refund on a multi-product order can mark every product on the order as refunded. The order total in `order_360` is still the completed refund amount. Also add checks for assumed cases this file does not contain, such as an order with no customer or a clock that cannot be parsed. On this extract those checks would reject nothing.
