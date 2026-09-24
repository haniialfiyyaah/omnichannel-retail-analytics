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


def build_silver() -> int:
    """Apply build_silver.sql and return how many orders Silver kept."""
    # "local" is required. connect() with no argument opens the Neon demo.
    with connect("local") as connection:
        logger.info("Applying %s", SQL_PATH.name)
        apply_sql_file(connection, SQL_PATH)
        row = connection.execute("SELECT count(*) FROM silver.orders").fetchone()
    return int(row[0])


def main() -> None:
    """Run the Silver orders load and print the kept row count."""
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    print(f"silver.orders {build_silver()}")


if __name__ == "__main__":
    main()
