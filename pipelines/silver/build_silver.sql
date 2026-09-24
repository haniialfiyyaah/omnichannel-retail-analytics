-- One file. Python runs this whole file once.
-- Each source file has three steps:
--   1. Read the Bronze rows into a temporary table with plain column names.
--   2. Stack the rejection reasons and insert them once.
--   3. Keep the valid rows.
-- A temporary table lives only for this run. It is not a Silver table.
-- A valid duplicate order is not a rejection. One bad item does not reject its order.

BEGIN;

-- A blank clock time is a missing field. A present value that cannot be cast is unparseable.
CREATE OR REPLACE FUNCTION silver.parse_timestamptz(value TEXT)
RETURNS TIMESTAMPTZ
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
    IF value IS NULL OR btrim(value) = '' THEN
        RETURN NULL;
    END IF;
    RETURN btrim(value)::timestamptz;
EXCEPTION
    WHEN OTHERS THEN
        RETURN NULL;
END;
$$;

-- A second run replaces the previous Silver rows.
DELETE FROM silver.orders;
DELETE FROM silver.order_items;
DELETE FROM silver.rejected_records
WHERE source_file IN ('operational/orders.json', 'operational/order_items.json');

-- Step 1. Read operational/orders.json.
CREATE TEMP TABLE order_rows ON COMMIT DROP AS
SELECT
    bronze_row_id,
    source_file,
    source_line_number,
    pipeline_run_id,
    NULLIF(btrim(payload->>'order_id'), '') AS order_id,
    NULLIF(btrim(payload->>'customer_id'), '') AS customer_id,
    NULLIF(btrim(payload->>'ordered_at_utc'), '') AS ordered_at_text,
    NULLIF(btrim(payload->>'updated_at_utc'), '') AS updated_at_text,
    silver.parse_timestamptz(payload->>'ordered_at_utc') AS ordered_at_utc,
    silver.parse_timestamptz(payload->>'updated_at_utc') AS updated_at_utc,
    NULLIF(btrim(payload->>'sales_channel'), '') AS sales_channel,
    NULLIF(btrim(payload->>'store_id'), '') AS store_id,
    NULLIF(btrim(payload->>'status'), '') AS status,
    NULLIF(btrim(payload->>'shipping_revenue'), '') AS shipping_revenue_text
FROM bronze.raw_records
WHERE source_file = 'operational/orders.json';

-- Step 2. Stack every order reason, then write that list once.
INSERT INTO silver.rejected_records (
    bronze_row_id,
    source_file,
    source_record_id,
    rejection_reason,
    pipeline_run_id
)
SELECT bronze_row_id, source_file, order_id, rejection_reason, pipeline_run_id
FROM (
    SELECT
        bronze_row_id,
        source_file,
        order_id,
        'missing_required_field' AS rejection_reason,
        pipeline_run_id
    FROM order_rows
    WHERE order_id IS NULL
       OR customer_id IS NULL
       OR ordered_at_text IS NULL
       OR updated_at_text IS NULL
       OR sales_channel IS NULL
       OR status IS NULL
       OR shipping_revenue_text IS NULL

    UNION ALL

    SELECT bronze_row_id, source_file, order_id, 'unparseable_timestamp', pipeline_run_id
    FROM order_rows
    WHERE (ordered_at_text IS NOT NULL AND ordered_at_utc IS NULL)
       OR (updated_at_text IS NOT NULL AND updated_at_utc IS NULL)

    UNION ALL

    SELECT orders.bronze_row_id, orders.source_file, orders.order_id, 'missing_customer', orders.pipeline_run_id
    FROM order_rows AS orders
    WHERE orders.customer_id IS NOT NULL
      AND NOT EXISTS (
          SELECT 1
          FROM bronze.raw_records AS customers
          WHERE customers.source_file = 'operational/customers.json'
            AND customers.payload->>'customer_id' = orders.customer_id
      )

    UNION ALL

    SELECT orders.bronze_row_id, orders.source_file, orders.order_id, 'missing_sales_channel', orders.pipeline_run_id
    FROM order_rows AS orders
    WHERE orders.sales_channel IS NOT NULL
      AND NOT EXISTS (
          SELECT 1
          FROM bronze.raw_records AS channels
          WHERE channels.source_file = 'operational/sales_channels.json'
            AND channels.payload->>'channel_id' = orders.sales_channel
      )

    UNION ALL

    -- A blank store_id is a digital order. Only a filled unknown store is rejected.
    SELECT orders.bronze_row_id, orders.source_file, orders.order_id, 'missing_store', orders.pipeline_run_id
    FROM order_rows AS orders
    WHERE orders.store_id IS NOT NULL
      AND NOT EXISTS (
          SELECT 1
          FROM bronze.raw_records AS stores
          WHERE stores.source_file = 'operational/stores.json'
            AND stores.payload->>'store_id' = orders.store_id
      )
) AS order_rejections;

-- Step 3. Keep one winner per order_id. Rejected copies are skipped.
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
SELECT DISTINCT ON (order_id)
    order_id,
    customer_id,
    ordered_at_utc,
    updated_at_utc,
    sales_channel,
    store_id,
    status,
    shipping_revenue_text::numeric(14, 2),
    bronze_row_id,
    pipeline_run_id
FROM order_rows
WHERE bronze_row_id NOT IN (
    SELECT bronze_row_id
    FROM silver.rejected_records
    WHERE source_file = 'operational/orders.json'
)
ORDER BY
    order_id,
    updated_at_utc DESC,
    source_line_number DESC;

-- Step 1. Read operational/order_items.json.
CREATE TEMP TABLE item_rows ON COMMIT DROP AS
SELECT
    bronze_row_id,
    source_file,
    source_line_number,
    pipeline_run_id,
    NULLIF(btrim(payload->>'order_item_id'), '') AS order_item_id,
    NULLIF(btrim(payload->>'order_id'), '') AS order_id,
    NULLIF(btrim(payload->>'product_id'), '') AS product_id,
    (payload->>'quantity')::numeric AS quantity,
    (payload->>'unit_price')::numeric(14, 2) AS unit_price,
    (payload->>'item_discount_amount')::numeric(14, 2) AS item_discount_amount
FROM bronze.raw_records
WHERE source_file = 'operational/order_items.json';

-- Step 2. Stack every item reason, then write that list once.
INSERT INTO silver.rejected_records (
    bronze_row_id,
    source_file,
    source_record_id,
    rejection_reason,
    pipeline_run_id
)
SELECT bronze_row_id, source_file, order_item_id, rejection_reason, pipeline_run_id
FROM (
    SELECT
        bronze_row_id,
        source_file,
        order_item_id,
        'negative_quantity' AS rejection_reason,
        pipeline_run_id
    FROM item_rows
    WHERE quantity < 0

    UNION ALL

    SELECT
        items.bronze_row_id,
        items.source_file,
        items.order_item_id,
        'missing_product',
        items.pipeline_run_id
    FROM item_rows AS items
    WHERE NOT EXISTS (
        SELECT 1
        FROM bronze.raw_records AS products
        WHERE products.source_file = 'operational/products.json'
          AND products.payload->>'product_id' = items.product_id
    )
) AS item_rejections;

-- Step 3. Keep items that were not rejected and whose order was kept.
INSERT INTO silver.order_items (
    order_item_id,
    order_id,
    product_id,
    quantity,
    unit_price,
    item_discount_amount,
    bronze_row_id,
    pipeline_run_id
)
SELECT DISTINCT ON (order_item_id)
    order_item_id,
    order_id,
    product_id,
    quantity::integer,
    unit_price,
    item_discount_amount,
    bronze_row_id,
    pipeline_run_id
FROM item_rows
WHERE order_id IN (SELECT order_id FROM silver.orders)
  AND bronze_row_id NOT IN (
      SELECT bronze_row_id
      FROM silver.rejected_records
      WHERE source_file = 'operational/order_items.json'
  )
ORDER BY
    order_item_id,
    source_line_number DESC;

COMMIT;
