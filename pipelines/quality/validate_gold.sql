-- Record six Gold reconciliation checks for one pipeline run.
-- {{pipeline_run_id}} is replaced by the Python runner.
-- These statements do not change Bronze, Silver, or Gold.
-- This runs after Gold exists. The quality gate before Gold is quality_gate.sql.

INSERT INTO ops.quality_checks (
    pipeline_run_id, check_name, status, expected_value, observed_value
)
SELECT
    '{{pipeline_run_id}}',
    'order_grain',
    CASE WHEN expected_value = observed_value THEN 'passed' ELSE 'failed' END,
    expected_value,
    observed_value
FROM (
    SELECT
        (SELECT count(*) FROM silver.orders)::numeric AS expected_value,
        (SELECT count(*) FROM gold.order_360)::numeric AS observed_value
) AS totals;

INSERT INTO ops.quality_checks (
    pipeline_run_id, check_name, status, expected_value, observed_value
)
SELECT
    '{{pipeline_run_id}}',
    'revenue_match',
    CASE WHEN expected_value = observed_value THEN 'passed' ELSE 'failed' END,
    expected_value,
    observed_value
FROM (
    SELECT
        SUM(gross_merchandise_value - discount_amount + shipping_revenue - refunded_amount) AS expected_value,
        SUM(net_revenue) AS observed_value
    FROM gold.order_360
) AS totals;

INSERT INTO ops.quality_checks (
    pipeline_run_id, check_name, status, expected_value, observed_value
)
SELECT
    '{{pipeline_run_id}}',
    'refund_match',
    CASE WHEN expected_value = observed_value THEN 'passed' ELSE 'failed' END,
    expected_value,
    observed_value
FROM (
    SELECT
        (
            SELECT COALESCE(SUM(amount), 0)
            FROM silver.refund_events
            WHERE event_type = 'REFUND_COMPLETED'
        ) AS expected_value,
        (SELECT COALESCE(SUM(refunded_amount), 0) FROM gold.order_360) AS observed_value
) AS totals;

INSERT INTO ops.quality_checks (
    pipeline_run_id, check_name, status, expected_value, observed_value
)
SELECT
    '{{pipeline_run_id}}',
    'captured_match',
    CASE WHEN expected_value = observed_value THEN 'passed' ELSE 'failed' END,
    expected_value,
    observed_value
FROM (
    SELECT
        (
            SELECT COALESCE(SUM(amount), 0)
            FROM silver.payment_events
            WHERE event_type = 'PAYMENT_CAPTURED'
        ) AS expected_value,
        (SELECT COALESCE(SUM(captured_payment_amount), 0) FROM gold.order_360) AS observed_value
) AS totals;

INSERT INTO ops.quality_checks (
    pipeline_run_id, check_name, status, expected_value, observed_value
)
SELECT
    '{{pipeline_run_id}}',
    'item_revenue_match',
    CASE WHEN expected_value = observed_value THEN 'passed' ELSE 'failed' END,
    expected_value,
    observed_value
FROM (
    SELECT
        (SELECT COALESCE(SUM(quantity * unit_price), 0) FROM silver.order_items) AS expected_value,
        (SELECT COALESCE(SUM(gross_merchandise_value), 0) FROM gold.order_360) AS observed_value
) AS totals;

INSERT INTO ops.quality_checks (
    pipeline_run_id, check_name, status, expected_value, observed_value
)
SELECT
    '{{pipeline_run_id}}',
    'daily_orders_match',
    CASE WHEN expected_value = observed_value THEN 'passed' ELSE 'failed' END,
    expected_value,
    observed_value
FROM (
    SELECT
        (SELECT count(*) FROM gold.order_360)::numeric AS expected_value,
        (SELECT COALESCE(SUM(total_orders), 0) FROM gold.executive_kpis_daily) AS observed_value
) AS totals;
