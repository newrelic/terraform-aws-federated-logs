import sys
import json
import random
import time
from datetime import datetime, timezone
from awsglue.utils import getResolvedOptions
from pyiceberg.catalog.glue import GlueCatalog
from pyiceberg.exceptions import CommitFailedException

# Creating a tag is an Iceberg metadata commit under optimistic locking, and
# these tables are appended to continuously by the Flink commit worker and
# rewritten by Glue's compaction optimizer. Losing that race is the expected
# case, not the exotic one, and pyiceberg surfaces it as CommitFailedException
# with no retry of its own.
COMMIT_ATTEMPTS = 5
COMMIT_BACKOFF_CAP_S = 8


def tag_current_snapshot(catalog, identifier, tag_name, retain_ms):
    """Tag the table's current snapshot, retrying on commit conflicts.

    Returns (snapshot_id, status). snapshot_id is None when nothing was tagged.

    The table handle MUST be reloaded on every attempt: it carries the metadata
    version the commit is validated against, so retrying with a stale handle
    fails identically every time. Reloading also means a conflict re-reads the
    table, so we tag whatever is current at the winning attempt — which is what
    we want for a recovery point.
    """
    for attempt in range(1, COMMIT_ATTEMPTS + 1):
        table = catalog.load_table(identifier)

        # Re-checked per attempt, not just once: a concurrent run of this job
        # may have created the tag while we were backing off.
        if tag_name in table.refs():
            return None, "SKIPPED (already tagged this tick)"

        current_snapshot = table.current_snapshot()
        if current_snapshot is None:
            return None, "SKIPPED (no snapshot yet)"

        snapshot_id = current_snapshot.snapshot_id
        try:
            with table.manage_snapshots() as ms:
                ms.create_tag(snapshot_id, tag_name, max_ref_age_ms=retain_ms)
            return snapshot_id, "SUCCESS"
        except CommitFailedException as e:
            if attempt == COMMIT_ATTEMPTS:
                raise
            backoff = min(2 ** (attempt - 1), COMMIT_BACKOFF_CAP_S)
            backoff += random.uniform(0, 0.5)  # jitter, so parallel tables desync
            print(
                f"  commit conflict on attempt {attempt}/{COMMIT_ATTEMPTS} "
                f"({e}); reloading table and retrying in {backoff:.1f}s"
            )
            time.sleep(backoff)


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
            retain_ms = cfg["retain_days"] * 24 * 60 * 60 * 1000

            # Idempotency is handled inside the helper: CREATE TAG fails if a
            # ref with this name already exists, so an overlapping or retried
            # run for the same tick is a no-op rather than a failure.
            snapshot_id, status = tag_current_snapshot(
                catalog, f"{database}.{table_name}", tag_name, retain_ms
            )
            results[table_name] = status

            if status == "SUCCESS":
                print(f"[{table_name}] Created tag {tag_name} on snapshot {snapshot_id}")
            else:
                print(f"[{table_name}] {status}")

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
