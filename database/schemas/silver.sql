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

-- Every category version stays. product_id repeats when a product changes category.
CREATE TABLE IF NOT EXISTS silver.product_categories (
    category_row_id TEXT PRIMARY KEY,
    product_id TEXT NOT NULL,
    category_id TEXT NOT NULL,
    category_name TEXT NOT NULL,
    valid_from_utc TIMESTAMPTZ NOT NULL,
    valid_to_utc TIMESTAMPTZ NOT NULL,
    bronze_row_id BIGINT NOT NULL,
    pipeline_run_id TEXT NOT NULL
);

-- One row per store. A blank store_id on an order is still allowed.
CREATE TABLE IF NOT EXISTS silver.stores (
    store_id TEXT PRIMARY KEY,
    store_name TEXT NOT NULL,
    city_id TEXT NOT NULL,
    location_type TEXT NOT NULL,
    bronze_row_id BIGINT NOT NULL,
    pipeline_run_id TEXT NOT NULL
);

-- One row per sales channel. Orders store this value in sales_channel.
CREATE TABLE IF NOT EXISTS silver.sales_channels (
    channel_id TEXT PRIMARY KEY,
    channel_name TEXT NOT NULL,
    bronze_row_id BIGINT NOT NULL,
    pipeline_run_id TEXT NOT NULL
);

-- One row per promotion. start_date and end_date stay calendar dates.
CREATE TABLE IF NOT EXISTS silver.promotions (
    promotion_id TEXT PRIMARY KEY,
    promotion_code TEXT NOT NULL,
    promotion_type TEXT NOT NULL,
    discount_rate NUMERIC(8, 4) NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    bronze_row_id BIGINT NOT NULL,
    pipeline_run_id TEXT NOT NULL
);

-- One row per order-promotion link. An order can have more than one promotion.
CREATE TABLE IF NOT EXISTS silver.order_promotions (
    promotion_row_id TEXT PRIMARY KEY,
    order_id TEXT NOT NULL,
    promotion_id TEXT NOT NULL,
    discount_amount NUMERIC(14, 2) NOT NULL,
    bronze_row_id BIGINT NOT NULL,
    pipeline_run_id TEXT NOT NULL
);

-- One row per winning event_id. Several payments on one order stay.
CREATE TABLE IF NOT EXISTS silver.payment_events (
    event_id TEXT PRIMARY KEY,
    event_type TEXT NOT NULL,
    occurred_at_utc TIMESTAMPTZ NOT NULL,
    ingested_at_utc TIMESTAMPTZ NOT NULL,
    order_id TEXT NOT NULL,
    payment_id TEXT NOT NULL,
    amount NUMERIC(14, 2) NOT NULL,
    bronze_row_id BIGINT NOT NULL,
    pipeline_run_id TEXT NOT NULL
);
