-- Fill silver.orders and silver.order_items from bronze.raw_records.
-- A rejected item stays out of silver.order_items. Its order stays in silver.orders.
-- Duplicate copies stay in Bronze. They are not rejections.

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

-- Replace the previous item load and its rejection reasons.
DELETE FROM silver.order_items;
DELETE FROM silver.rejected_records
WHERE source_file = 'operational/order_items.json';

-- A negative quantity rejects that item row only.
INSERT INTO silver.rejected_records (
    bronze_row_id,
    source_file,
    source_record_id,
    rejection_reason,
    pipeline_run_id
)
SELECT
    bronze_row_id,
    source_file,
    payload->>'order_item_id',
    'negative_quantity',
    pipeline_run_id
FROM bronze.raw_records
WHERE source_file = 'operational/order_items.json'
  AND (payload->>'quantity')::numeric < 0;

-- A product id that is not in the products file rejects that item row only.
INSERT INTO silver.rejected_records (
    bronze_row_id,
    source_file,
    source_record_id,
    rejection_reason,
    pipeline_run_id
)
SELECT
    items.bronze_row_id,
    items.source_file,
    items.payload->>'order_item_id',
    'missing_product',
    items.pipeline_run_id
FROM bronze.raw_records AS items
WHERE items.source_file = 'operational/order_items.json'
  AND NOT EXISTS (
      SELECT 1
      FROM bronze.raw_records AS products
      WHERE products.source_file = 'operational/products.json'
        AND products.payload->>'product_id' = items.payload->>'product_id'
  );

-- Keep item rows that were not rejected. One row per order_item_id.
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
SELECT DISTINCT ON (payload->>'order_item_id')
    payload->>'order_item_id',
    payload->>'order_id',
    payload->>'product_id',
    (payload->>'quantity')::integer,
    (payload->>'unit_price')::numeric(14, 2),
    (payload->>'item_discount_amount')::numeric(14, 2),
    bronze_row_id,
    pipeline_run_id
FROM bronze.raw_records
WHERE source_file = 'operational/order_items.json'
  AND bronze_row_id NOT IN (
      SELECT bronze_row_id
      FROM silver.rejected_records
      WHERE source_file = 'operational/order_items.json'
  )
ORDER BY
    payload->>'order_item_id',
    source_line_number DESC;

-- One row per customer_id. A repeated id keeps the higher source_line_number.
DELETE FROM silver.customers;

INSERT INTO silver.customers (
    customer_id,
    city_id,
    customer_segment,
    created_at_utc,
    bronze_row_id,
    pipeline_run_id
)
SELECT DISTINCT ON (payload->>'customer_id')
    payload->>'customer_id',
    payload->>'city_id',
    payload->>'customer_segment',
    (payload->>'created_at_utc')::timestamptz,
    bronze_row_id,
    pipeline_run_id
FROM bronze.raw_records
WHERE source_file = 'operational/customers.json'
ORDER BY
    payload->>'customer_id',
    source_line_number DESC;

-- Keep every profile version. A repeated customer_id is a second version, not a duplicate.
DELETE FROM silver.customer_profiles;

INSERT INTO silver.customer_profiles (
    profile_row_id,
    customer_id,
    city_id,
    customer_segment,
    valid_from_utc,
    valid_to_utc,
    bronze_row_id,
    pipeline_run_id
)
SELECT
    payload->>'source_row_id',
    payload->>'customer_id',
    payload->>'city_id',
    payload->>'customer_segment',
    (payload->>'valid_from_utc')::timestamptz,
    (payload->>'valid_to_utc')::timestamptz,
    bronze_row_id,
    pipeline_run_id
FROM bronze.raw_records
WHERE source_file = 'operational/customer_profiles.json';

-- Keep every address row, including its valid_from and valid_to window.
DELETE FROM silver.customer_addresses;

INSERT INTO silver.customer_addresses (
    address_id,
    customer_id,
    city_id,
    valid_from_utc,
    valid_to_utc,
    bronze_row_id,
    pipeline_run_id
)
SELECT
    payload->>'address_id',
    payload->>'customer_id',
    payload->>'city_id',
    (payload->>'valid_from_utc')::timestamptz,
    (payload->>'valid_to_utc')::timestamptz,
    bronze_row_id,
    pipeline_run_id
FROM bronze.raw_records
WHERE source_file = 'operational/customer_addresses.json';

COMMIT;
