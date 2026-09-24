"""Run the quality gate on Silver before Gold is built.

A failed check is stored in ops.quality_checks and this module exits so Gold
does not run.
"""

from __future__ import annotations

import logging
import sys
import uuid
from pathlib import Path

from shared.db import connect

logger = logging.getLogger(__name__)

SQL_PATH = Path(__file__).with_name("quality_gate.sql")


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
            """,
            (run_id,),
        )
        connection.execute(check_sql)
        rows = connection.execute(
            """
            SELECT check_name, status
            FROM ops.quality_checks
            WHERE pipeline_run_id = %s
            ORDER BY check_name
            """,
            (run_id,),
        ).fetchall()
        failed = [str(name) for name, status in rows if status != "passed"]
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
    return [(str(name), str(status)) for name, status in rows]


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
