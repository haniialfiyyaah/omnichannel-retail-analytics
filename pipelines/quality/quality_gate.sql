-- Record the quality gate for one pipeline run.
-- {{pipeline_run_id}} is replaced by the Python runner.
-- These checks read Silver only. They run before Gold is built.
-- These statements do not change Bronze, Silver, or Gold.

INSERT INTO ops.quality_checks (
    pipeline_run_id, check_name, status, expected_value, observed_value
)
SELECT
    '{{pipeline_run_id}}',
    'silver_orders_loaded',
    CASE WHEN observed_value > 0 THEN 'passed' ELSE 'failed' END,
    1,
    observed_value
FROM (
    SELECT count(*)::numeric AS observed_value
    FROM silver.orders
) AS totals;

-- Pass when no order_id is stored twice and the losing copy is in rejected_records.
-- expected_value 1 means both parts are true. observed_value is 1 only then.
INSERT INTO ops.quality_checks (
    pipeline_run_id, check_name, status, expected_value, observed_value
)
SELECT
    '{{pipeline_run_id}}',
    'duplicate_order_rejected',
    CASE WHEN expected_value = observed_value THEN 'passed' ELSE 'failed' END,
    expected_value,
    observed_value
FROM (
    SELECT
        1::numeric AS expected_value,
        CASE
            WHEN duplicate_orders = 0 AND rejected_duplicates > 0 THEN 1
            ELSE 0
        END::numeric AS observed_value
    FROM (
        SELECT
            (
                SELECT count(*)
                FROM (
                    SELECT order_id
                    FROM silver.orders
                    GROUP BY order_id
                    HAVING count(*) > 1
                ) AS duplicated_orders
            ) AS duplicate_orders,
            (
                SELECT count(*)
                FROM silver.rejected_records
                WHERE rejection_reason = 'duplicate_order_id'
            ) AS rejected_duplicates
    ) AS counts
) AS totals;

INSERT INTO ops.quality_checks (
    pipeline_run_id, check_name, status, expected_value, observed_value
)
SELECT
    '{{pipeline_run_id}}',
    'rejected_item_absent',
    CASE WHEN expected_value = observed_value THEN 'passed' ELSE 'failed' END,
    expected_value,
    observed_value
FROM (
    SELECT
        0::numeric AS expected_value,
        (
            SELECT count(*)::numeric
            FROM silver.order_items AS items
            WHERE items.order_item_id IN (
                SELECT source_record_id
                FROM silver.rejected_records
                WHERE rejection_reason IN ('negative_quantity', 'missing_product')
            )
        ) AS observed_value
) AS totals;
