import sys
import json
import random
import time
import traceback
from datetime import datetime, timezone
from enum import Enum
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


class Status(Enum):
    SUCCESS = "SUCCESS"
    SKIPPED = "SKIPPED"
    ERROR = "ERROR"


def tag_current_snapshot(catalog, identifier, tag_name, retain_ms):
    """Tag the table's current snapshot, retrying on commit conflicts.

    Returns (Status, detail). Raises the last CommitFailedException if every
    attempt loses the commit race.

    The table handle MUST be reloaded on every attempt: it carries the metadata
    version the commit is validated against, so retrying with a stale handle
    fails identically every time. Reloading also means a conflict re-reads the
    table, so we tag whatever is current at the winning attempt — which is what
    we want for a recovery point.
    """
    for attempt in range(1, COMMIT_ATTEMPTS + 1):
        table = catalog.load_table(identifier)

        # This check is the ONLY thing that makes the job idempotent. pyiceberg's
        # create_tag does not fail on an existing ref: it asserts the ref's
        # current snapshot id and silently repoints the tag. Re-checked per
        # attempt, not just once: a concurrent run of this job may have created
        # the tag while we were backing off.
        if tag_name in table.refs():
            return Status.SKIPPED, "already tagged this tick"

        current_snapshot = table.current_snapshot()
        if current_snapshot is None:
            return Status.SKIPPED, "no snapshot yet"

        snapshot_id = current_snapshot.snapshot_id
        try:
            with table.manage_snapshots() as ms:
                ms.create_tag(snapshot_id, tag_name, max_ref_age_ms=retain_ms)
            return Status.SUCCESS, f"created tag {tag_name} on snapshot {snapshot_id}"
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

    # Unreachable while the loop re-raises on its last attempt; makes the
    # contract explicit if the loop bounds ever change.
    raise RuntimeError(f"tag_current_snapshot exhausted {COMMIT_ATTEMPTS} attempts without a result")


def main():
    # Parse job parameters
    args = getResolvedOptions(sys.argv, ["DATABASE_NAME", "TABLE_TAG_CONFIG", "WAREHOUSE_PATH"])
    database = args["DATABASE_NAME"]
    table_tag_config = json.loads(args["TABLE_TAG_CONFIG"])

    catalog = GlueCatalog("glue_catalog", warehouse=args["WAREHOUSE_PATH"])

    # Hour resolution, so a manual off-schedule run creates its own tag rather
    # than being skipped as a duplicate of the 01:00 UTC scheduled one.
    tag_name = f"backup-{datetime.now(timezone.utc):%Y-%m-%dT%H}"

    # Process each table with its own retain_days
    results = {}
    for table_name, cfg in table_tag_config.items():
        print(f"Processing table: {table_name}")

        try:
            print(f"Tag name: {tag_name}, retain_days: {cfg['retain_days']}")
            retain_ms = cfg["retain_days"] * 24 * 60 * 60 * 1000

            # Idempotency is handled inside the helper by its refs() check, so
            # an overlapping or retried run for the same tick is a no-op.
            status, detail = tag_current_snapshot(
                catalog, f"{database}.{table_name}", tag_name, retain_ms
            )
            results[table_name] = status
            print(f"[{table_name}] {status.value}: {detail}")

        except Exception as e:
            results[table_name] = Status.ERROR
            print(f"[{table_name}] ERROR: {e}")
            # Full traceback so a code/API bug is distinguishable from a
            # transient table-level failure in the job logs.
            print(traceback.format_exc())

            # Continue with other tables (don't fail fast) — same as retention_job.py
            continue

    # Exit with error code if any failures
    failed = [t for t, s in results.items() if s is Status.ERROR]
    if failed:
        print(f"{len(failed)} table(s) failed: {', '.join(failed)}")
        sys.exit(1)
    else:
        print(f"All {len(results)} table(s) processed successfully")


if __name__ == "__main__":
    main()
