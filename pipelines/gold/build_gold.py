"""Run the Gold SQL against local Postgres.

The order grain and money rules stay in build_gold.sql. This module opens the
local database and sends that file to Postgres.
"""

from __future__ import annotations

import logging
from pathlib import Path

from shared.db import apply_sql_file, connect

logger = logging.getLogger(__name__)

SQL_PATH = Path(__file__).with_name("build_gold.sql")


def build_gold() -> list[tuple[str, int]]:
    """Apply build_gold.sql and return the order_360 and Silver order counts."""
    # "local" is required. connect() with no argument opens the Neon demo.
    with connect("local") as connection:
        logger.info("Applying %s", SQL_PATH.name)
        apply_sql_file(connection, SQL_PATH)
        rows = connection.execute(
            """
            SELECT 'gold.order_360' AS label, count(*) AS row_count
            FROM gold.order_360
            UNION ALL
            SELECT 'gold.customer_daily', count(*)
            FROM gold.customer_daily
            UNION ALL
            SELECT 'gold.product_daily', count(*)
            FROM gold.product_daily
            UNION ALL
            SELECT 'gold.channel_campaign_daily', count(*)
            FROM gold.channel_campaign_daily
            UNION ALL
            SELECT 'silver.orders', count(*)
            FROM silver.orders
            ORDER BY label
            """
        ).fetchall()
    return [(str(label), int(row_count)) for label, row_count in rows]


def main() -> None:
    """Run the Gold order_360 load and print the row counts."""
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    for label, row_count in build_gold():
        print(f"{label} {row_count}")


if __name__ == "__main__":
    main()
