-- Fill silver.orders from bronze.raw_records.
-- This slice loads orders only. Other Silver tables are later slices.
-- Duplicate order_id copies stay in Bronze. They are not rejections.

BEGIN;

-- Replace the previous orders load so a second run does not hit the primary key.
DELETE FROM silver.orders;

-- DISTINCT ON keeps the first row for each order_id after the ORDER BY.
-- Latest updated_at_utc wins. A tie keeps the higher source_line_number.
INSERT INTO silver.orders (
    order_id,
    customer_id,
    ordered_at_utc,
    updated_at_utc,
    sales_channel,
    store_id,
    status,
    shipping_revenue,
    bronze_row_id,
    pipeline_run_id
)
SELECT DISTINCT ON (payload->>'order_id')
    payload->>'order_id',
    payload->>'customer_id',
    (payload->>'ordered_at_utc')::timestamptz,
    (payload->>'updated_at_utc')::timestamptz,
    payload->>'sales_channel',
    NULLIF(payload->>'store_id', ''),
    payload->>'status',
    (payload->>'shipping_revenue')::numeric(14, 2),
    bronze_row_id,
    pipeline_run_id
FROM bronze.raw_records
WHERE source_file = 'operational/orders.json'
ORDER BY
    payload->>'order_id',
    (payload->>'updated_at_utc')::timestamptz DESC,
    source_line_number DESC;

COMMIT;
