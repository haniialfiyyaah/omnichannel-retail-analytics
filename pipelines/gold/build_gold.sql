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

COMMIT;
