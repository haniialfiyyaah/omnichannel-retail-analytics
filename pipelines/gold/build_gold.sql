-- Fill gold.order_360 from Silver. One row per order_id.
-- Each money amount is summed on its own grain, then joined to the order.
-- gold.sql is not changed by this file.

BEGIN;

DELETE FROM gold.order_360;

INSERT INTO gold.order_360 (
    order_id,
    customer_id,
    order_date,
    sales_channel,
    store_id,
    gross_merchandise_value,
    discount_amount,
    shipping_revenue,
    captured_payment_amount,
    refunded_amount,
    net_revenue,
    item_count,
    unit_quantity,
    order_status,
    payment_status,
    return_status,
    promotion_count,
    first_order_flag,
    pipeline_run_id
)
SELECT
    orders.order_id,
    orders.customer_id,
    (orders.ordered_at_utc AT TIME ZONE 'UTC')::date AS order_date,
    orders.sales_channel,
    orders.store_id,
    COALESCE(items.gross_merchandise_value, 0),
    COALESCE(promotions.discount_amount, 0),
    orders.shipping_revenue,
    COALESCE(payments.captured_payment_amount, 0),
    COALESCE(refunds.refunded_amount, 0),
    COALESCE(items.gross_merchandise_value, 0)
        - COALESCE(promotions.discount_amount, 0)
        + orders.shipping_revenue
        - COALESCE(refunds.refunded_amount, 0) AS net_revenue,
    COALESCE(items.item_count, 0),
    COALESCE(items.unit_quantity, 0),
    orders.status AS order_status,
    CASE
        WHEN COALESCE(payments.captured_payment_amount, 0) > 0 THEN 'CAPTURED'
        ELSE 'NOT_CAPTURED'
    END AS payment_status,
    CASE
        WHEN COALESCE(returns.return_count, 0) > 0 THEN 'RETURNED'
        ELSE 'NO_RETURN'
    END AS return_status,
    COALESCE(promotions.promotion_count, 0),
    orders.order_rank = 1 AS first_order_flag,
    orders.pipeline_run_id
FROM (
    SELECT
        order_id,
        customer_id,
        ordered_at_utc,
        sales_channel,
        store_id,
        status,
        shipping_revenue,
        pipeline_run_id,
        ROW_NUMBER() OVER (
            PARTITION BY customer_id
            ORDER BY ordered_at_utc, order_id
        ) AS order_rank
    FROM silver.orders
) AS orders
LEFT JOIN (
    SELECT
        order_id,
        SUM(quantity * unit_price) AS gross_merchandise_value,
        COUNT(*) AS item_count,
        SUM(quantity) AS unit_quantity
    FROM silver.order_items
    GROUP BY order_id
) AS items ON items.order_id = orders.order_id
LEFT JOIN (
    SELECT
        order_id,
        SUM(discount_amount) AS discount_amount,
        COUNT(*) AS promotion_count
    FROM silver.order_promotions
    GROUP BY order_id
) AS promotions ON promotions.order_id = orders.order_id
LEFT JOIN (
    SELECT
        order_id,
        SUM(amount) FILTER (WHERE event_type = 'PAYMENT_CAPTURED') AS captured_payment_amount
    FROM silver.payment_events
    GROUP BY order_id
) AS payments ON payments.order_id = orders.order_id
LEFT JOIN (
    SELECT
        order_id,
        SUM(amount) FILTER (WHERE event_type = 'REFUND_COMPLETED') AS refunded_amount
    FROM silver.refund_events
    GROUP BY order_id
) AS refunds ON refunds.order_id = orders.order_id
LEFT JOIN (
    SELECT
        order_id,
        COUNT(*) AS return_count
    FROM silver.return_events
    GROUP BY order_id
) AS returns ON returns.order_id = orders.order_id;

-- One row per customer and business date.
-- Order money comes from gold.order_360, already summed per order.
DELETE FROM gold.customer_daily;

INSERT INTO gold.customer_daily (
    customer_id,
    metric_date,
    order_count,
    unit_quantity,
    gross_revenue,
    net_revenue,
    refund_amount,
    return_count,
    support_contacts,
    active_channel,
    new_customer_flag,
    repeat_customer_flag,
    pipeline_run_id
)
SELECT
    days.customer_id,
    days.metric_date,
    COALESCE(order_days.order_count, 0),
    COALESCE(order_days.unit_quantity, 0),
    COALESCE(order_days.gross_revenue, 0),
    COALESCE(order_days.net_revenue, 0),
    COALESCE(order_days.refund_amount, 0),
    COALESCE(order_days.return_count, 0),
    COALESCE(support_days.support_contacts, 0),
    channels.sales_channel,
    days.metric_date = first_orders.first_order_date AS new_customer_flag,
    first_orders.first_order_date IS NOT NULL
        AND days.metric_date > first_orders.first_order_date AS repeat_customer_flag,
    COALESCE(order_days.pipeline_run_id, support_days.pipeline_run_id)
FROM (
    SELECT customer_id, order_date AS metric_date
    FROM gold.order_360
    UNION
    SELECT
        customer_id,
        (occurred_at_utc AT TIME ZONE 'UTC')::date
    FROM silver.support_events
) AS days
LEFT JOIN (
    SELECT
        customer_id,
        order_date AS metric_date,
        COUNT(*) AS order_count,
        SUM(unit_quantity) AS unit_quantity,
        SUM(gross_merchandise_value) AS gross_revenue,
        SUM(net_revenue) AS net_revenue,
        SUM(refunded_amount) AS refund_amount,
        COUNT(*) FILTER (WHERE return_status = 'RETURNED') AS return_count,
        MAX(pipeline_run_id) AS pipeline_run_id
    FROM gold.order_360
    GROUP BY customer_id, order_date
) AS order_days
    ON order_days.customer_id = days.customer_id
    AND order_days.metric_date = days.metric_date
LEFT JOIN (
    SELECT
        customer_id,
        (occurred_at_utc AT TIME ZONE 'UTC')::date AS metric_date,
        COUNT(*) AS support_contacts,
        MAX(pipeline_run_id) AS pipeline_run_id
    FROM silver.support_events
    GROUP BY customer_id, (occurred_at_utc AT TIME ZONE 'UTC')::date
) AS support_days
    ON support_days.customer_id = days.customer_id
    AND support_days.metric_date = days.metric_date
LEFT JOIN (
    SELECT DISTINCT ON (customer_id, order_date)
        customer_id,
        order_date AS metric_date,
        sales_channel
    FROM (
        SELECT customer_id, order_date, sales_channel, COUNT(*) AS order_count
        FROM gold.order_360
        GROUP BY customer_id, order_date, sales_channel
    ) AS channel_counts
    ORDER BY customer_id, order_date, order_count DESC, sales_channel
) AS channels
    ON channels.customer_id = days.customer_id
    AND channels.metric_date = days.metric_date
LEFT JOIN (
    SELECT customer_id, MIN(order_date) AS first_order_date
    FROM gold.order_360
    GROUP BY customer_id
) AS first_orders ON first_orders.customer_id = days.customer_id;

-- One row per product and business date.
-- Item money is summed per product before it is joined to inventory or category.
DELETE FROM gold.product_daily;

INSERT INTO gold.product_daily (
    product_id,
    metric_date,
    active_category,
    units_sold,
    order_count,
    gross_revenue,
    net_revenue,
    refunded_units,
    available_inventory,
    reserved_inventory,
    stockout_flag,
    promotion_count,
    pipeline_run_id
)
SELECT
    days.product_id,
    days.metric_date,
    categories.category_name,
    COALESCE(sales.units_sold, 0),
    COALESCE(sales.order_count, 0),
    COALESCE(sales.gross_revenue, 0),
    COALESCE(sales.net_revenue, 0),
    COALESCE(sales.refunded_units, 0),
    inventory.available_inventory,
    inventory.reserved_inventory,
    CASE
        WHEN inventory.product_id IS NULL THEN NULL
        WHEN inventory.available_inventory = 0 THEN TRUE
        ELSE FALSE
    END AS stockout_flag,
    COALESCE(product_promotions.promotion_count, 0),
    COALESCE(sales.pipeline_run_id, inventory.pipeline_run_id)
FROM (
    SELECT product_id, metric_date FROM (
        SELECT DISTINCT
            items.product_id,
            orders.order_date AS metric_date
        FROM silver.order_items AS items
        JOIN gold.order_360 AS orders ON orders.order_id = items.order_id
        UNION
        SELECT DISTINCT product_id, snapshot_date
        FROM silver.inventory_snapshots
    ) AS product_days
) AS days
LEFT JOIN (
    SELECT
        lines.product_id,
        lines.metric_date,
        SUM(lines.quantity) AS units_sold,
        COUNT(DISTINCT lines.order_id) AS order_count,
        SUM(lines.line_amount) AS gross_revenue,
        SUM(lines.allocated_net_revenue) AS net_revenue,
        SUM(lines.refunded_units) AS refunded_units,
        MAX(lines.pipeline_run_id) AS pipeline_run_id
    FROM (
        SELECT
            items.product_id,
            items.order_id,
            orders.order_date AS metric_date,
            items.quantity,
            items.quantity * items.unit_price AS line_amount,
            CASE
                WHEN SUM(items.quantity * items.unit_price) OVER (PARTITION BY items.order_id) = 0 THEN 0
                ELSE orders.net_revenue
                    * (items.quantity * items.unit_price)
                    / SUM(items.quantity * items.unit_price) OVER (PARTITION BY items.order_id)
            END AS allocated_net_revenue,
            CASE
                WHEN orders.refunded_amount > 0 THEN items.quantity
                ELSE 0
            END AS refunded_units,
            orders.pipeline_run_id
        FROM silver.order_items AS items
        JOIN gold.order_360 AS orders ON orders.order_id = items.order_id
    ) AS lines
    GROUP BY lines.product_id, lines.metric_date
) AS sales
    ON sales.product_id = days.product_id
    AND sales.metric_date = days.metric_date
LEFT JOIN (
    SELECT
        product_id,
        snapshot_date AS metric_date,
        SUM(available_quantity) AS available_inventory,
        SUM(reserved_quantity) AS reserved_inventory,
        MAX(pipeline_run_id) AS pipeline_run_id
    FROM silver.inventory_snapshots
    GROUP BY product_id, snapshot_date
) AS inventory
    ON inventory.product_id = days.product_id
    AND inventory.metric_date = days.metric_date
LEFT JOIN (
    SELECT
        items.product_id,
        orders.order_date AS metric_date,
        COUNT(DISTINCT promotions.promotion_id) AS promotion_count
    FROM silver.order_items AS items
    JOIN gold.order_360 AS orders ON orders.order_id = items.order_id
    JOIN silver.order_promotions AS promotions ON promotions.order_id = items.order_id
    GROUP BY items.product_id, orders.order_date
) AS product_promotions
    ON product_promotions.product_id = days.product_id
    AND product_promotions.metric_date = days.metric_date
LEFT JOIN LATERAL (
    SELECT category_name
    FROM silver.product_categories AS category_rows
    WHERE category_rows.product_id = days.product_id
      AND category_rows.valid_from_utc <= (days.metric_date::timestamp AT TIME ZONE 'UTC')
      AND (days.metric_date::timestamp AT TIME ZONE 'UTC') < category_rows.valid_to_utc
    ORDER BY category_rows.valid_from_utc DESC
    LIMIT 1
) AS categories ON TRUE;

-- One row per date, channel, and campaign.
-- Order money is summed once per order, then grouped. Spend is stored once.
DELETE FROM gold.channel_campaign_daily;

INSERT INTO gold.channel_campaign_daily (
    metric_date,
    sales_channel,
    campaign_id,
    campaign_spend,
    attributed_orders,
    attributed_customers,
    gross_revenue,
    net_revenue,
    refunds,
    roas,
    conversion_rate,
    pipeline_run_id
)
SELECT
    keys.metric_date,
    keys.sales_channel,
    keys.campaign_id,
    COALESCE(spend.campaign_spend, 0),
    COALESCE(attributed.attributed_orders, 0),
    COALESCE(attributed.attributed_customers, 0),
    COALESCE(attributed.gross_revenue, 0),
    COALESCE(attributed.net_revenue, 0),
    COALESCE(attributed.refunds, 0),
    CASE
        WHEN COALESCE(spend.campaign_spend, 0) = 0 THEN NULL
        ELSE COALESCE(attributed.net_revenue, 0) / spend.campaign_spend
    END AS roas,
    CASE
        WHEN COALESCE(sessions.session_count, 0) = 0 THEN NULL
        ELSE COALESCE(attributed.attributed_orders, 0)::numeric / sessions.session_count
    END AS conversion_rate,
    COALESCE(attributed.pipeline_run_id, spend.pipeline_run_id, sessions.pipeline_run_id)
FROM (
    SELECT spend_date AS metric_date, channel AS sales_channel, campaign_id
    FROM silver.campaign_spend
    UNION
    SELECT order_date, sales_channel, campaign_id
    FROM gold.order_360 AS orders
    JOIN (
        SELECT DISTINCT ON (order_id)
            order_id,
            campaign_id
        FROM silver.web_events
        WHERE campaign_id IS NOT NULL
        ORDER BY order_id, occurred_at_utc, event_id
    ) AS order_campaign ON order_campaign.order_id = orders.order_id
    UNION
    SELECT
        (occurred_at_utc AT TIME ZONE 'UTC')::date,
        channel,
        campaign_id
    FROM silver.web_events
    WHERE campaign_id IS NOT NULL
) AS keys
LEFT JOIN (
    SELECT
        orders.order_date AS metric_date,
        orders.sales_channel,
        order_campaign.campaign_id,
        COUNT(*) AS attributed_orders,
        COUNT(DISTINCT orders.customer_id) AS attributed_customers,
        SUM(orders.gross_merchandise_value) AS gross_revenue,
        SUM(orders.net_revenue) AS net_revenue,
        SUM(orders.refunded_amount) AS refunds,
        MAX(orders.pipeline_run_id) AS pipeline_run_id
    FROM gold.order_360 AS orders
    JOIN (
        SELECT DISTINCT ON (order_id)
            order_id,
            campaign_id
        FROM silver.web_events
        WHERE campaign_id IS NOT NULL
        ORDER BY order_id, occurred_at_utc, event_id
    ) AS order_campaign ON order_campaign.order_id = orders.order_id
    GROUP BY orders.order_date, orders.sales_channel, order_campaign.campaign_id
) AS attributed
    ON attributed.metric_date = keys.metric_date
    AND attributed.sales_channel = keys.sales_channel
    AND attributed.campaign_id = keys.campaign_id
LEFT JOIN (
    SELECT
        spend_date AS metric_date,
        channel AS sales_channel,
        campaign_id,
        SUM(spend_amount) AS campaign_spend,
        MAX(pipeline_run_id) AS pipeline_run_id
    FROM silver.campaign_spend
    GROUP BY spend_date, channel, campaign_id
) AS spend
    ON spend.metric_date = keys.metric_date
    AND spend.sales_channel = keys.sales_channel
    AND spend.campaign_id = keys.campaign_id
LEFT JOIN (
    SELECT
        (occurred_at_utc AT TIME ZONE 'UTC')::date AS metric_date,
        channel AS sales_channel,
        campaign_id,
        COUNT(DISTINCT session_id) AS session_count,
        MAX(pipeline_run_id) AS pipeline_run_id
    FROM silver.web_events
    WHERE campaign_id IS NOT NULL
    GROUP BY (occurred_at_utc AT TIME ZONE 'UTC')::date, channel, campaign_id
) AS sessions
    ON sessions.metric_date = keys.metric_date
    AND sessions.sales_channel = keys.sales_channel
    AND sessions.campaign_id = keys.campaign_id;

-- One row per business date. Rates use the order and product rows already summed.
DELETE FROM gold.executive_kpis_daily;

INSERT INTO gold.executive_kpis_daily (
    metric_date,
    total_orders,
    gross_revenue,
    net_revenue,
    average_order_value,
    refund_rate,
    return_rate,
    repeat_customer_rate,
    stockout_rate,
    active_customers,
    support_contact_rate,
    data_freshness_utc,
    pipeline_run_id
)
SELECT
    days.metric_date,
    COALESCE(orders.total_orders, 0),
    COALESCE(orders.gross_revenue, 0),
    COALESCE(orders.net_revenue, 0),
    CASE
        WHEN COALESCE(orders.total_orders, 0) = 0 THEN 0
        ELSE orders.net_revenue / orders.total_orders
    END AS average_order_value,
    CASE
        WHEN COALESCE(orders.captured_orders, 0) = 0 THEN 0
        ELSE orders.refunded_orders::numeric / orders.captured_orders
    END AS refund_rate,
    CASE
        WHEN COALESCE(orders.total_orders, 0) = 0 THEN 0
        ELSE orders.returned_orders::numeric / orders.total_orders
    END AS return_rate,
    CASE
        WHEN COALESCE(customers.ordering_customers, 0) = 0 THEN 0
        ELSE customers.repeat_customers::numeric / customers.ordering_customers
    END AS repeat_customer_rate,
    CASE
        WHEN COALESCE(products.snapshot_products, 0) = 0 THEN 0
        ELSE products.stockout_products::numeric / products.snapshot_products
    END AS stockout_rate,
    COALESCE(customers.ordering_customers, 0) AS active_customers,
    CASE
        WHEN COALESCE(orders.total_orders, 0) = 0 THEN 0
        ELSE COALESCE(customers.support_contacts, 0)::numeric / orders.total_orders
    END AS support_contact_rate,
    freshness.latest_ingested_at_utc,
    COALESCE(orders.pipeline_run_id, products.pipeline_run_id, freshness.pipeline_run_id)
FROM (
    SELECT order_date AS metric_date FROM gold.order_360
    UNION
    SELECT metric_date FROM gold.product_daily
) AS days
LEFT JOIN (
    SELECT
        order_date AS metric_date,
        COUNT(*) AS total_orders,
        SUM(gross_merchandise_value) AS gross_revenue,
        SUM(net_revenue) AS net_revenue,
        COUNT(*) FILTER (WHERE refunded_amount > 0) AS refunded_orders,
        COUNT(*) FILTER (WHERE payment_status = 'CAPTURED') AS captured_orders,
        COUNT(*) FILTER (WHERE return_status = 'RETURNED') AS returned_orders,
        MAX(pipeline_run_id) AS pipeline_run_id
    FROM gold.order_360
    GROUP BY order_date
) AS orders ON orders.metric_date = days.metric_date
LEFT JOIN (
    SELECT
        metric_date,
        COUNT(*) FILTER (WHERE order_count > 0) AS ordering_customers,
        COUNT(*) FILTER (WHERE order_count > 0 AND repeat_customer_flag) AS repeat_customers,
        SUM(support_contacts) AS support_contacts
    FROM gold.customer_daily
    GROUP BY metric_date
) AS customers ON customers.metric_date = days.metric_date
LEFT JOIN (
    SELECT
        metric_date,
        COUNT(*) FILTER (WHERE stockout_flag IS NOT NULL) AS snapshot_products,
        COUNT(*) FILTER (WHERE stockout_flag) AS stockout_products,
        MAX(pipeline_run_id) AS pipeline_run_id
    FROM gold.product_daily
    GROUP BY metric_date
) AS products ON products.metric_date = days.metric_date
CROSS JOIN (
    SELECT
        MAX(ingested_at_utc) AS latest_ingested_at_utc,
        MAX(pipeline_run_id) AS pipeline_run_id
    FROM (
        SELECT ingested_at_utc, pipeline_run_id FROM silver.payment_events
        UNION ALL
        SELECT ingested_at_utc, pipeline_run_id FROM silver.refund_events
        UNION ALL
        SELECT ingested_at_utc, pipeline_run_id FROM silver.return_events
        UNION ALL
        SELECT ingested_at_utc, pipeline_run_id FROM silver.support_events
        UNION ALL
        SELECT ingested_at_utc, pipeline_run_id FROM silver.web_events
    ) AS ingested
) AS freshness;

COMMIT;
