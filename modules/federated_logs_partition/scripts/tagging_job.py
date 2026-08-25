import sys
import json
from datetime import datetime, timezone
from awsglue.utils import getResolvedOptions
from pyiceberg.catalog.glue import GlueCatalog


def main():
    # Parse job parameters
    args = getResolvedOptions(sys.argv, ["DATABASE_NAME", "TABLE_TAG_CONFIG", "WAREHOUSE_PATH"])
    database = args["DATABASE_NAME"]
    table_tag_config = json.loads(args["TABLE_TAG_CONFIG"])

    catalog = GlueCatalog("glue_catalog", warehouse=args["WAREHOUSE_PATH"])

    # Hour resolution regardless of cadence (daily or hourly), so cadence can
    # change without a naming collision, and the name self-documents the tick.
    tag_name = f"backup-{datetime.now(timezone.utc):%Y-%m-%dT%H}"

    # Process each table with its own retain_days
    results = {}
    for table_name, cfg in table_tag_config.items():
        print(f"Processing table: {table_name}")

        try:
            print(f"Tag name: {tag_name}, retain_days: {cfg['retain_days']}")
            table = catalog.load_table(f"{database}.{table_name}")

            # Idempotency: CREATE TAG fails if a ref with this name already
            # exists. Check first so a retried/overlapping run for the same
            # tick is a no-op, not a failure.
            if tag_name in table.refs():
                results[table_name] = "SKIPPED (already tagged this tick)"
                print(f"[{table_name}] Tag {tag_name} already exists, skipping")
                continue

            current_snapshot = table.current_snapshot()
            if current_snapshot is None:
                results[table_name] = "SKIPPED (no snapshot yet)"
                print(f"[{table_name}] Table has no snapshot yet, skipping")
                continue

            snapshot_id = current_snapshot.snapshot_id
            retain_ms = cfg["retain_days"] * 24 * 60 * 60 * 1000

            with table.manage_snapshots() as ms:
                ms.create_tag(snapshot_id, tag_name, max_ref_age_ms=retain_ms)

            results[table_name] = "SUCCESS"
            print(f"[{table_name}] Created tag {tag_name} on snapshot {snapshot_id}")

        except Exception as e:
            error_msg = str(e)
            results[table_name] = f"ERROR: {error_msg}"
            print(f"[{table_name}] Error: {error_msg}")

            # Continue with other tables (don't fail fast) — same as retention_job.py
            continue

    # Exit with error code if any failures
    failed = [t for t, s in results.items() if s.startswith("ERROR")]
    if failed:
        print(f"{len(failed)} table(s) failed: {', '.join(failed)}")
        sys.exit(1)
    else:
        print(f"All {len(results)} table(s) processed successfully")


if __name__ == "__main__":
    main()
