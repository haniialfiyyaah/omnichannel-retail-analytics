-- Silver is the typed layer. It reads bronze.raw_records.
-- This file only creates empty tables. pipelines/silver/build_silver.sql fills them.

CREATE SCHEMA IF NOT EXISTS silver;

-- One row per Bronze row that Silver refuses to keep, with a reason.
CREATE TABLE IF NOT EXISTS silver.rejected_records (
    rejected_row_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    bronze_row_id BIGINT NOT NULL,
    source_file TEXT NOT NULL,
    source_record_id TEXT,
    rejection_reason TEXT NOT NULL,
    pipeline_run_id TEXT NOT NULL
);

-- One row per winning order_id. Duplicate copies stay in Bronze and are not rejections.
CREATE TABLE IF NOT EXISTS silver.orders (
    order_id TEXT PRIMARY KEY,
    customer_id TEXT NOT NULL,
    ordered_at_utc TIMESTAMPTZ NOT NULL,
    updated_at_utc TIMESTAMPTZ NOT NULL,
    sales_channel TEXT NOT NULL,
    -- Null when the order has no physical store.
    store_id TEXT,
    status TEXT NOT NULL,
    shipping_revenue NUMERIC(14, 2) NOT NULL,
    -- The Bronze row that won. The losing copies are not stored here.
    bronze_row_id BIGINT NOT NULL,
    pipeline_run_id TEXT NOT NULL
);

-- One row per order item that passed the checks. A rejected item does not remove its order.
CREATE TABLE IF NOT EXISTS silver.order_items (
    order_item_id TEXT PRIMARY KEY,
    order_id TEXT NOT NULL,
    product_id TEXT NOT NULL,
    quantity INTEGER NOT NULL,
    unit_price NUMERIC(14, 2) NOT NULL,
    item_discount_amount NUMERIC(14, 2) NOT NULL,
    bronze_row_id BIGINT NOT NULL,
    pipeline_run_id TEXT NOT NULL
);

-- One row per customer_id. Profile and address versions are later tables.
CREATE TABLE IF NOT EXISTS silver.customers (
    customer_id TEXT PRIMARY KEY,
    city_id TEXT NOT NULL,
    customer_segment TEXT NOT NULL,
    created_at_utc TIMESTAMPTZ NOT NULL,
    bronze_row_id BIGINT NOT NULL,
    pipeline_run_id TEXT NOT NULL
);

-- Every profile version stays. customer_id repeats when a customer has two versions.
CREATE TABLE IF NOT EXISTS silver.customer_profiles (
    profile_row_id TEXT PRIMARY KEY,
    customer_id TEXT NOT NULL,
    city_id TEXT NOT NULL,
    customer_segment TEXT NOT NULL,
    valid_from_utc TIMESTAMPTZ NOT NULL,
    valid_to_utc TIMESTAMPTZ NOT NULL,
    bronze_row_id BIGINT NOT NULL,
    pipeline_run_id TEXT NOT NULL
);

-- One address version per row. This file has one version per customer.
CREATE TABLE IF NOT EXISTS silver.customer_addresses (
    address_id TEXT PRIMARY KEY,
    customer_id TEXT NOT NULL,
    city_id TEXT NOT NULL,
    valid_from_utc TIMESTAMPTZ NOT NULL,
    valid_to_utc TIMESTAMPTZ NOT NULL,
    bronze_row_id BIGINT NOT NULL,
    pipeline_run_id TEXT NOT NULL
);

-- One row per product. Category versions are a later table.
CREATE TABLE IF NOT EXISTS silver.products (
    product_id TEXT PRIMARY KEY,
    product_name TEXT NOT NULL,
    sku TEXT NOT NULL,
    unit_price NUMERIC(14, 2) NOT NULL,
    bronze_row_id BIGINT NOT NULL,
    pipeline_run_id TEXT NOT NULL
);
