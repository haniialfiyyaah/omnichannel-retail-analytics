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

COMMIT;
