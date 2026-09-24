-- Fill silver.orders and silver.order_items from bronze.raw_records.
-- A rejected item stays out of silver.order_items. Its order stays in silver.orders.
-- A losing duplicate stays in Bronze and is also written to silver.rejected_records.

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

-- The order copy that lost is recorded. The winner stays in silver.orders.
DELETE FROM silver.rejected_records
WHERE source_file = 'operational/orders.json';

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
    payload->>'order_id',
    'duplicate_order_id',
    pipeline_run_id
FROM bronze.raw_records
WHERE source_file = 'operational/orders.json'
  AND bronze_row_id NOT IN (SELECT bronze_row_id FROM silver.orders);

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

-- An item copy that lost, and was not already rejected, is recorded.
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
    'duplicate_order_item_id',
    pipeline_run_id
FROM bronze.raw_records
WHERE source_file = 'operational/order_items.json'
  AND bronze_row_id NOT IN (SELECT bronze_row_id FROM silver.order_items)
  AND bronze_row_id NOT IN (
      SELECT bronze_row_id
      FROM silver.rejected_records
      WHERE source_file = 'operational/order_items.json'
  );

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

-- One row per product_id.
DELETE FROM silver.products;

INSERT INTO silver.products (
    product_id,
    product_name,
    sku,
    unit_price,
    bronze_row_id,
    pipeline_run_id
)
SELECT
    payload->>'product_id',
    payload->>'product_name',
    payload->>'sku',
    (payload->>'unit_price')::numeric(14, 2),
    bronze_row_id,
    pipeline_run_id
FROM bronze.raw_records
WHERE source_file = 'operational/products.json';

-- Keep every category version. A repeated product_id is a second version, not a duplicate.
DELETE FROM silver.product_categories;

INSERT INTO silver.product_categories (
    category_row_id,
    product_id,
    category_id,
    category_name,
    valid_from_utc,
    valid_to_utc,
    bronze_row_id,
    pipeline_run_id
)
SELECT
    payload->>'source_row_id',
    payload->>'product_id',
    payload->>'category_id',
    payload->>'category_name',
    (payload->>'valid_from_utc')::timestamptz,
    (payload->>'valid_to_utc')::timestamptz,
    bronze_row_id,
    pipeline_run_id
FROM bronze.raw_records
WHERE source_file = 'operational/product_categories.json';

-- One row per store_id.
DELETE FROM silver.stores;

INSERT INTO silver.stores (
    store_id,
    store_name,
    city_id,
    location_type,
    bronze_row_id,
    pipeline_run_id
)
SELECT
    payload->>'store_id',
    payload->>'store_name',
    payload->>'city_id',
    payload->>'location_type',
    bronze_row_id,
    pipeline_run_id
FROM bronze.raw_records
WHERE source_file = 'operational/stores.json';

-- One row per channel_id.
DELETE FROM silver.sales_channels;

INSERT INTO silver.sales_channels (
    channel_id,
    channel_name,
    bronze_row_id,
    pipeline_run_id
)
SELECT
    payload->>'channel_id',
    payload->>'channel_name',
    bronze_row_id,
    pipeline_run_id
FROM bronze.raw_records
WHERE source_file = 'operational/sales_channels.json';

-- One row per promotion_id. Dates stay calendar dates.
DELETE FROM silver.promotions;

INSERT INTO silver.promotions (
    promotion_id,
    promotion_code,
    promotion_type,
    discount_rate,
    start_date,
    end_date,
    bronze_row_id,
    pipeline_run_id
)
SELECT
    payload->>'promotion_id',
    payload->>'promotion_code',
    payload->>'promotion_type',
    (payload->>'discount_rate')::numeric(8, 4),
    (payload->>'start_date')::date,
    (payload->>'end_date')::date,
    bronze_row_id,
    pipeline_run_id
FROM bronze.raw_records
WHERE source_file = 'operational/promotions.json';

-- Keep every order-promotion row. Several promotions on one order stay.
DELETE FROM silver.order_promotions;

INSERT INTO silver.order_promotions (
    promotion_row_id,
    order_id,
    promotion_id,
    discount_amount,
    bronze_row_id,
    pipeline_run_id
)
SELECT
    payload->>'source_row_id',
    payload->>'order_id',
    payload->>'promotion_id',
    (payload->>'discount_amount')::numeric(14, 2),
    bronze_row_id,
    pipeline_run_id
FROM bronze.raw_records
WHERE source_file = 'operational/order_promotions.json';

-- One winner per event_id. Latest occurred_at_utc wins, then the higher source line.
-- A repeated order_id is another payment and stays.
DELETE FROM silver.payment_events;

INSERT INTO silver.payment_events (
    event_id,
    event_type,
    occurred_at_utc,
    ingested_at_utc,
    order_id,
    payment_id,
    amount,
    bronze_row_id,
    pipeline_run_id
)
SELECT DISTINCT ON (payload->>'event_id')
    payload->>'event_id',
    payload->>'event_type',
    (payload->>'occurred_at_utc')::timestamptz,
    (payload->>'ingested_at_utc')::timestamptz,
    payload->'payload'->>'order_id',
    payload->'payload'->>'payment_id',
    (payload->'payload'->>'amount')::numeric(14, 2),
    bronze_row_id,
    pipeline_run_id
FROM bronze.raw_records
WHERE source_file = 'events/payment_events.json'
ORDER BY
    payload->>'event_id',
    (payload->>'occurred_at_utc')::timestamptz DESC,
    source_line_number DESC;

DELETE FROM silver.rejected_records
WHERE source_file = 'events/payment_events.json';

INSERT INTO silver.rejected_records (
    bronze_row_id, source_file, source_record_id, rejection_reason, pipeline_run_id
)
SELECT bronze_row_id, source_file, payload->>'event_id', 'duplicate_event_id', pipeline_run_id
FROM bronze.raw_records
WHERE source_file = 'events/payment_events.json'
  AND bronze_row_id NOT IN (SELECT bronze_row_id FROM silver.payment_events);

-- One winner per event_id. A repeated refund_id is another stage and stays.
DELETE FROM silver.refund_events;

INSERT INTO silver.refund_events (
    event_id,
    event_type,
    occurred_at_utc,
    ingested_at_utc,
    order_id,
    refund_id,
    amount,
    bronze_row_id,
    pipeline_run_id
)
SELECT DISTINCT ON (payload->>'event_id')
    payload->>'event_id',
    payload->>'event_type',
    (payload->>'occurred_at_utc')::timestamptz,
    (payload->>'ingested_at_utc')::timestamptz,
    payload->'payload'->>'order_id',
    payload->'payload'->>'refund_id',
    (payload->'payload'->>'amount')::numeric(14, 2),
    bronze_row_id,
    pipeline_run_id
FROM bronze.raw_records
WHERE source_file = 'events/refund_events.json'
ORDER BY
    payload->>'event_id',
    (payload->>'occurred_at_utc')::timestamptz DESC,
    source_line_number DESC;

DELETE FROM silver.rejected_records
WHERE source_file = 'events/refund_events.json';

INSERT INTO silver.rejected_records (
    bronze_row_id, source_file, source_record_id, rejection_reason, pipeline_run_id
)
SELECT bronze_row_id, source_file, payload->>'event_id', 'duplicate_event_id', pipeline_run_id
FROM bronze.raw_records
WHERE source_file = 'events/refund_events.json'
  AND bronze_row_id NOT IN (SELECT bronze_row_id FROM silver.refund_events);

-- One winner per return event_id.
DELETE FROM silver.return_events;

INSERT INTO silver.return_events (
    event_id,
    event_type,
    occurred_at_utc,
    ingested_at_utc,
    order_id,
    return_id,
    bronze_row_id,
    pipeline_run_id
)
SELECT DISTINCT ON (payload->>'event_id')
    payload->>'event_id',
    payload->>'event_type',
    (payload->>'occurred_at_utc')::timestamptz,
    (payload->>'ingested_at_utc')::timestamptz,
    payload->'payload'->>'order_id',
    payload->'payload'->>'return_id',
    bronze_row_id,
    pipeline_run_id
FROM bronze.raw_records
WHERE source_file = 'events/return_events.json'
ORDER BY
    payload->>'event_id',
    (payload->>'occurred_at_utc')::timestamptz DESC,
    source_line_number DESC;

DELETE FROM silver.rejected_records
WHERE source_file = 'events/return_events.json';

INSERT INTO silver.rejected_records (
    bronze_row_id, source_file, source_record_id, rejection_reason, pipeline_run_id
)
SELECT bronze_row_id, source_file, payload->>'event_id', 'duplicate_event_id', pipeline_run_id
FROM bronze.raw_records
WHERE source_file = 'events/return_events.json'
  AND bronze_row_id NOT IN (SELECT bronze_row_id FROM silver.return_events);

-- One winner per support event_id. A blank reason is kept as null.
DELETE FROM silver.support_events;

INSERT INTO silver.support_events (
    event_id,
    event_type,
    occurred_at_utc,
    ingested_at_utc,
    order_id,
    customer_id,
    ticket_id,
    reason,
    bronze_row_id,
    pipeline_run_id
)
SELECT DISTINCT ON (payload->>'event_id')
    payload->>'event_id',
    payload->>'event_type',
    (payload->>'occurred_at_utc')::timestamptz,
    (payload->>'ingested_at_utc')::timestamptz,
    payload->'payload'->>'order_id',
    payload->'payload'->>'customer_id',
    payload->'payload'->>'ticket_id',
    NULLIF(payload->'payload'->>'reason', ''),
    bronze_row_id,
    pipeline_run_id
FROM bronze.raw_records
WHERE source_file = 'events/support_events.json'
ORDER BY
    payload->>'event_id',
    (payload->>'occurred_at_utc')::timestamptz DESC,
    source_line_number DESC;

DELETE FROM silver.rejected_records
WHERE source_file = 'events/support_events.json';

INSERT INTO silver.rejected_records (
    bronze_row_id, source_file, source_record_id, rejection_reason, pipeline_run_id
)
SELECT bronze_row_id, source_file, payload->>'event_id', 'duplicate_event_id', pipeline_run_id
FROM bronze.raw_records
WHERE source_file = 'events/support_events.json'
  AND bronze_row_id NOT IN (SELECT bronze_row_id FROM silver.support_events);

-- One winner per web event_id. A blank campaign_id is kept as null.
DELETE FROM silver.web_events;

INSERT INTO silver.web_events (
    event_id,
    event_type,
    occurred_at_utc,
    ingested_at_utc,
    order_id,
    customer_id,
    session_id,
    channel,
    campaign_id,
    bronze_row_id,
    pipeline_run_id
)
SELECT DISTINCT ON (payload->>'event_id')
    payload->>'event_id',
    payload->>'event_type',
    (payload->>'occurred_at_utc')::timestamptz,
    (payload->>'ingested_at_utc')::timestamptz,
    payload->'payload'->>'order_id',
    payload->'payload'->>'customer_id',
    payload->'payload'->>'session_id',
    payload->'payload'->>'channel',
    NULLIF(payload->'payload'->>'campaign_id', ''),
    bronze_row_id,
    pipeline_run_id
FROM bronze.raw_records
WHERE source_file = 'events/web_events.json'
ORDER BY
    payload->>'event_id',
    (payload->>'occurred_at_utc')::timestamptz DESC,
    source_line_number DESC;

DELETE FROM silver.rejected_records
WHERE source_file = 'events/web_events.json';

INSERT INTO silver.rejected_records (
    bronze_row_id, source_file, source_record_id, rejection_reason, pipeline_run_id
)
SELECT bronze_row_id, source_file, payload->>'event_id', 'duplicate_event_id', pipeline_run_id
FROM bronze.raw_records
WHERE source_file = 'events/web_events.json'
  AND bronze_row_id NOT IN (SELECT bronze_row_id FROM silver.web_events);

-- Keep observed inventory days only. A missing day is not inserted as quantity 0.
DELETE FROM silver.inventory_snapshots;

INSERT INTO silver.inventory_snapshots (
    product_id,
    location_id,
    snapshot_date,
    available_quantity,
    reserved_quantity,
    unit_cost,
    bronze_row_id,
    pipeline_run_id
)
SELECT
    payload->>'product_id',
    payload->>'location_id',
    (payload->>'snapshot_date')::date,
    (payload->>'available_quantity')::integer,
    (payload->>'reserved_quantity')::integer,
    (payload->>'unit_cost')::numeric(14, 2),
    bronze_row_id,
    pipeline_run_id
FROM bronze.raw_records
WHERE source_file = 'inventory/inventory_snapshots.csv';

-- One row per spend day, campaign, and channel.
DELETE FROM silver.campaign_spend;

INSERT INTO silver.campaign_spend (
    spend_date,
    campaign_id,
    channel,
    spend_amount,
    bronze_row_id,
    pipeline_run_id
)
SELECT
    (payload->>'spend_date')::date,
    payload->>'campaign_id',
    payload->>'channel',
    (payload->>'spend_amount')::numeric(14, 2),
    bronze_row_id,
    pipeline_run_id
FROM bronze.raw_records
WHERE source_file = 'reference/campaign_spend.csv';

-- One row per city_id.
DELETE FROM silver.cities;

INSERT INTO silver.cities (
    city_id,
    city_name,
    country,
    bronze_row_id,
    pipeline_run_id
)
SELECT
    payload->>'city_id',
    payload->>'city_name',
    payload->>'country',
    bronze_row_id,
    pipeline_run_id
FROM bronze.raw_records
WHERE source_file = 'reference/city_reference.json';

COMMIT;
