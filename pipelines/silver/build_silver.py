"""Run the Silver SQL against local Postgres.

The winner rule stays in build_silver.sql. This module does not read data/raw.
It opens the local database and sends that file to Postgres.
"""

from __future__ import annotations

import logging
from pathlib import Path

from shared.db import apply_sql_file, connect

logger = logging.getLogger(__name__)

# Same folder as this module, so the command works from any working directory.
SQL_PATH = Path(__file__).with_name("build_silver.sql")


def build_silver() -> list[tuple[str, int]]:
    """Apply build_silver.sql and return kept and rejected counts."""
    # "local" is required. connect() with no argument opens the Neon demo.
    with connect("local") as connection:
        logger.info("Applying %s", SQL_PATH.name)
        apply_sql_file(connection, SQL_PATH)
        rows = connection.execute(
            """
            SELECT label, row_count
            FROM (
                SELECT 'silver.orders' AS label, count(*) AS row_count
                FROM silver.orders
                UNION ALL
                SELECT 'silver.order_items', count(*)
                FROM silver.order_items
                UNION ALL
                SELECT 'silver.customers', count(*)
                FROM silver.customers
                UNION ALL
                SELECT 'silver.customer_profiles', count(*)
                FROM silver.customer_profiles
                UNION ALL
                SELECT 'silver.customer_addresses', count(*)
                FROM silver.customer_addresses
                UNION ALL
                SELECT 'silver.products', count(*)
                FROM silver.products
                UNION ALL
                SELECT 'silver.product_categories', count(*)
                FROM silver.product_categories
                UNION ALL
                SELECT 'silver.stores', count(*)
                FROM silver.stores
                UNION ALL
                SELECT 'silver.sales_channels', count(*)
                FROM silver.sales_channels
                UNION ALL
                SELECT 'silver.promotions', count(*)
                FROM silver.promotions
                UNION ALL
                SELECT 'silver.order_promotions', count(*)
                FROM silver.order_promotions
                UNION ALL
                SELECT 'silver.payment_events', count(*)
                FROM silver.payment_events
                UNION ALL
                SELECT 'silver.refund_events', count(*)
                FROM silver.refund_events
                UNION ALL
                SELECT 'silver.return_events', count(*)
                FROM silver.return_events
                UNION ALL
                SELECT 'silver.support_events', count(*)
                FROM silver.support_events
                UNION ALL
                SELECT 'silver.web_events', count(*)
                FROM silver.web_events
                UNION ALL
                SELECT 'silver.inventory_snapshots', count(*)
                FROM silver.inventory_snapshots
                UNION ALL
                SELECT 'silver.campaign_spend', count(*)
                FROM silver.campaign_spend
                UNION ALL
                SELECT 'silver.cities', count(*)
                FROM silver.cities
                UNION ALL
                SELECT 'rejected.' || rejection_reason, count(*)
                FROM silver.rejected_records
                GROUP BY rejection_reason
            ) AS counts
            ORDER BY label
            """
        ).fetchall()
    return [(str(label), int(row_count)) for label, row_count in rows]


def main() -> None:
    """Run the Silver load and print kept and rejected counts."""
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    for label, row_count in build_silver():
        print(f"{label} {row_count}")


if __name__ == "__main__":
    main()
