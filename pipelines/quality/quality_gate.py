"""Run the quality gate on Silver before Gold is built.

A failed check is stored in ops.quality_checks and this module exits so Gold
does not run. A pass leaves ops.pipeline_runs.status as running. validate_gold
is the step that marks the run passed.
"""

from __future__ import annotations

import logging
import sys
import uuid
from pathlib import Path
from typing import Any

from shared.db import connect

logger = logging.getLogger(__name__)

SQL_PATH = Path(__file__).with_name("quality_gate.sql")

# These names must match the DELETE and INSERT lists in quality_gate.sql.
GATE_CHECKS = (
    "silver_orders_loaded",
    "duplicate_order_rejected",
    "rejected_item_absent",
)


def quality_gate(pipeline_run_id: str | None = None) -> list[tuple[str, str]]:
    """Record the Silver checks and return each check name with its status."""
    run_id = pipeline_run_id or str(uuid.uuid4())
    check_sql = SQL_PATH.read_text(encoding="utf-8").replace("{{pipeline_run_id}}", run_id)
    with connect("local") as connection:
        logger.info("Recording quality gate %s", run_id)
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
        results = _results_for(connection, run_id, GATE_CHECKS)
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
            # Gold has not run yet. Leaving status running avoids a passed run
            # when build_gold fails before validate_gold can record it.
            logger.info("Quality gate passed for %s; run stays running", run_id)
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
    """Run the quality gate and stop when any check fails."""
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    results = quality_gate()
    for check_name, status in results:
        print(f"{check_name} {status}")
    if any(status != "passed" for _, status in results):
        sys.exit(1)


if __name__ == "__main__":
    main()
