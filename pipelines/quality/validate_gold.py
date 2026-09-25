"""Validate Gold totals against Silver after Gold is built.

Each check compares two totals. This is the step that sets the run to passed
or failed. A failed check is stored in ops.quality_checks and this module exits
so a later pipeline step can stop.
"""

from __future__ import annotations

import logging
import sys
import uuid
from pathlib import Path
from typing import Any

from shared.db import connect

logger = logging.getLogger(__name__)

SQL_PATH = Path(__file__).with_name("validate_gold.sql")

# These names must match the DELETE and INSERT lists in validate_gold.sql.
GOLD_CHECKS = (
    "order_grain",
    "revenue_match",
    "refund_match",
    "captured_match",
    "item_revenue_match",
    "daily_orders_match",
)


def validate_gold(pipeline_run_id: str | None = None) -> list[tuple[str, str]]:
    """Record the six Gold checks and return each check name with its status."""
    run_id = pipeline_run_id or str(uuid.uuid4())
    check_sql = SQL_PATH.read_text(encoding="utf-8").replace("{{pipeline_run_id}}", run_id)
    with connect("local") as connection:
        logger.info("Recording Gold validation %s", run_id)
        connection.execute(
            """
            INSERT INTO ops.pipeline_runs (pipeline_run_id, status)
            VALUES (%s, 'running')
            ON CONFLICT (pipeline_run_id) DO UPDATE
            SET status = 'running', finished_at = NULL, error_message = NULL
            """,
            (run_id,),
        )
        connection.execute(check_sql)
        results = _results_for(connection, run_id, GOLD_CHECKS)
        failed = [name for name, status in results if status != "passed"]
        if failed:
            connection.execute(
                """
                UPDATE ops.pipeline_runs
                SET status = 'failed',
                    finished_at = now(),
                    error_message = %s
                WHERE pipeline_run_id = %s
                """,
                ("failed: " + ", ".join(failed), run_id),
            )
        else:
            connection.execute(
                """
                UPDATE ops.pipeline_runs
                SET status = 'passed', finished_at = now()
                WHERE pipeline_run_id = %s
                """,
                (run_id,),
            )
    return results


def _results_for(
    connection: Any, run_id: str, check_names: tuple[str, ...]
) -> list[tuple[str, str]]:
    """Return one status per check this step owns. A missing row counts as failed."""
    placeholders = ", ".join("%s" for _ in check_names)
    rows = connection.execute(
        f"""
        SELECT check_name, status
        FROM ops.quality_checks
        WHERE pipeline_run_id = %s
          AND check_name IN ({placeholders})
        ORDER BY check_name
        """,
        (run_id, *check_names),
    ).fetchall()
    found = {str(name): str(status) for name, status in rows}
    return [(name, found.get(name, "failed")) for name in check_names]


def main() -> None:
    """Validate Gold and stop when any check fails."""
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    results = validate_gold()
    for check_name, status in results:
        print(f"{check_name} {status}")
    if any(status != "passed" for _, status in results):
        sys.exit(1)


if __name__ == "__main__":
    main()
