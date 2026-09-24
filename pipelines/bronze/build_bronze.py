"""Load every raw file into bronze.raw_records.

Each source record becomes one row. The payload is not cleaned. A repeated
business id stays repeated. Running this module again replaces the previous
rows for each file instead of appending a second copy.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import logging
import uuid
from pathlib import Path
from typing import Any, Iterator

from shared.db import connect

logger = logging.getLogger(__name__)

# Business id to copy into source_record_id. Other ids stay inside payload.
RECORD_ID_FIELDS = {
    "operational/orders.json": "order_id",
    "operational/order_items.json": "order_item_id",
    "operational/order_promotions.json": "source_row_id",
    "operational/customers.json": "customer_id",
    "operational/customer_profiles.json": "source_row_id",
    "operational/customer_addresses.json": "address_id",
    "operational/products.json": "product_id",
    "operational/product_categories.json": "source_row_id",
    "operational/promotions.json": "promotion_id",
    "operational/stores.json": "store_id",
    "operational/sales_channels.json": "channel_id",
    "events/payment_events.json": "event_id",
    "events/refund_events.json": "event_id",
    "events/return_events.json": "event_id",
    "events/support_events.json": "event_id",
    "events/web_events.json": "event_id",
    "inventory/inventory_snapshots.csv": "product_id",
    "reference/campaign_spend.csv": "campaign_id",
    "reference/city_reference.json": "city_id",
}

INSERT_SQL = """
INSERT INTO bronze.raw_records (
    source_file,
    source_line_number,
    source_record_id,
    payload,
    row_checksum,
    pipeline_run_id
) VALUES (%s, %s, %s, %s::jsonb, %s, %s)
"""

DELETE_SQL = "DELETE FROM bronze.raw_records WHERE source_file = %s"


def iter_records(path: Path) -> Iterator[dict[str, Any]]:
    """Yield one dict per record. JSON arrays and CSV rows are both records."""
    if path.suffix == ".json":
        rows = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(rows, list):
            raise ValueError(f"{path} must be a JSON array")
        yield from rows
        return
    with path.open(encoding="utf-8", newline="") as handle:
        yield from csv.DictReader(handle)


def record_id(relative_path: str, row: dict[str, Any]) -> str | None:
    """Return the business id for this file, or None when that field is empty."""
    field_name = RECORD_ID_FIELDS.get(relative_path)
    if field_name is None or row.get(field_name) in (None, ""):
        return None
    return str(row[field_name])


def row_checksum(row: dict[str, Any]) -> str:
    """Hash the canonical JSON so the same record always has the same checksum."""
    canonical = json.dumps(row, sort_keys=True, separators=(",", ":"), default=str)
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def source_files(raw_dir: Path) -> list[Path]:
    """List loadable files. manifest.json is metadata and is skipped."""
    files = []
    for path in sorted(raw_dir.rglob("*")):
        if not path.is_file() or path.name == "manifest.json":
            continue
        if path.suffix in {".json", ".csv"}:
            files.append(path)
    return files


def load_file(connection: Any, path: Path, raw_dir: Path, pipeline_run_id: str) -> int:
    """Replace one file's Bronze rows, then insert the current records."""
    relative_path = path.relative_to(raw_dir).as_posix()
    # A new run id must not leave the previous copy of this file in the table.
    connection.execute(DELETE_SQL, (relative_path,))
    inserted = 0
    for line_number, row in enumerate(iter_records(path), start=1):
        connection.execute(
            INSERT_SQL,
            (
                relative_path,
                line_number,
                record_id(relative_path, row),
                json.dumps(row, default=str),
                row_checksum(row),
                pipeline_run_id,
            ),
        )
        inserted += 1
    logger.info("Loaded %s rows from %s", inserted, relative_path)
    return inserted


def load_bronze(raw_dir: Path, pipeline_run_id: str) -> dict[str, int]:
    """Load every raw file into the local Bronze table."""
    counts: dict[str, int] = {}
    with connect("local") as connection:
        for path in source_files(raw_dir):
            relative_path = path.relative_to(raw_dir).as_posix()
            counts[relative_path] = load_file(connection, path, raw_dir, pipeline_run_id)
    return counts


def main() -> None:
    """Load data/raw into bronze.raw_records and print the run id and row counts."""
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    parser = argparse.ArgumentParser(description="Load raw files into bronze.raw_records")
    parser.add_argument("--input", type=Path, default=Path("data/raw"))
    parser.add_argument("--run-id", default=str(uuid.uuid4()))
    args = parser.parse_args()

    counts = load_bronze(args.input, args.run_id)
    print(f"pipeline_run_id={args.run_id}")
    for relative_path, count in counts.items():
        print(f"{relative_path} {count}")
    print(f"total {sum(counts.values())}")


if __name__ == "__main__":
    main()
