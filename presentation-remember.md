# Remember

Facts to keep in your head. Say a row count only if someone asks for it.

| Topic                 | Keep this                                                                                                                                                           |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| What you built        | The path. You did not build the engine, the UI, or `gold.sql`.                                                                                                      |
| Two databases         | `retail_analytics` holds Bronze, Silver, Gold, and `ops`. `airflow` is only Airflow’s task history, on the same server.                                             |
| When a run passes     | A green gate means the run is still `running`. Only `validate_gold` sets `passed`.                                                                                  |
| Who wins a duplicate  | Latest timestamp, then the later line in the file. Status words are not ranked. The word `DUPLICATE` in the source id is not a rule.                                |
| Net revenue           | Discount is the promotion total only. Do not also subtract the item discount. Only `REFUND_COMPLETED` reduces revenue. Only `PAYMENT_CAPTURED` counts as captured.  |
| A passing money check | `revenue_match` can pass while Silver is still wrong, because both sides are built from Silver. The gate is what stops a bad Silver row from becoming Gold.         |
| Manifest              | `manifest.json` is in the written brief and was not in this download. `validate_raw_files` checks the data files. If asked, say that and stop.                      |
| Counts, only if asked | 1 duplicate order, 2,006 duplicate events, 1 negative quantity, 3 missing products. `order_360` has 10,000 rows. Net revenue is `13,466,989.83`.                    |
| Demo setup            | Airflow login is `admin` / `admin`. If the live DAG is slow, use `evidence/airflow_run.png`.                                                                        |
| Demo question         | Exact wording: `Show me net revenue trend for the last 30 days`. The table is `gold.executive_kpis_daily`. Do not ask a second question unless someone requests it. |
