# Iceberg Snapshot Tagging Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every Fed Logs table an opt-in, scheduled Glue Python Shell job that tags its current snapshot with a self-expiring Iceberg `SnapshotRef`, so there's a protected recovery point that survives the aggressive `number_of_snapshots_to_retain = 1` retention policy.

**Architecture:** New `tagging.tf` in `modules/federated_logs_partition/`, parallel to the existing `retention.tf`, but a Glue **Python Shell** job (not Spark ETL) running a new `pyiceberg`-based script (`scripts/tagging_job.py`, parallel to `scripts/retention_job.py`). A new `snapshot_tagging` block is added to `optimizer_configuration` in both `default_table_setting` and `partition_tables`. Because one Glue trigger has exactly one cron schedule, all tables that enable tagging must agree on `cadence`; that cross-table rule is enforced with a `terraform_data` resource carrying a `lifecycle.precondition`, since Terraform variable `validation {}` blocks can only see their own variable and this repo's declared minimum (`>= 1.6.0`) predates the 1.9 cross-variable validation relaxation.

**Tech Stack:** Terraform (AWS provider), AWS Glue Python Shell jobs, `pyiceberg[glue]`, `terraform test` (native plan-only test framework already used in this repo).

**Spec:** `/Users/patiballaprafullakiran/Workspace/flink-iceberg-commit-worker/docs/iceberg-snapshot-tagging-design.md` — read and reconciled against this repo before writing this plan. Scope for this plan is a deliberate subset of that spec's rollout plan: **only** rollout step 2 ("Terraform + Glue job"). Rollout step 1 (empirical validation of Glue's managed retention optimizer against Iceberg refs) and step 3 (alarming) are explicitly out of scope — confirmed with the user. `enabled` defaults to `false` everywhere: this plan ships the feature dormant.

## Global Constraints

(Copied verbatim from the spec; every task below implicitly inherits these.)

- `enabled` defaults to `false` per table — opt-in only, never on by default.
- `cadence` values: `"daily"` (default) or `"hourly"` only.
- `retain_days` defaults to `7`.
- Tag name format: `backup-<YYYY-MM-DDTHH>` (hour resolution regardless of cadence).
- Tag idempotency: check `table.refs()` before creating a tag; an existing tag for the current tick is `SKIPPED`, not an error.
- Script must loop per table, continue on a single table's error, and `sys.exit(1)` if any table failed (same control flow as `retention_job.py`).
- Glue job: `command.name = "pythonshell"`, `python_version = "3.9"`, `max_capacity = 0.0625`, `timeout = 15`, `max_retries = 1`, `--additional-python-modules = "pyiceberg[glue]"`.
- Glue trigger: `type = "SCHEDULED"`, cron = `cron(0 0 * * ? *)` for daily, `cron(0 * * * ? *)` for hourly.
- CloudWatch log group retention: 7 days (same as `retention_logs`).
- All tables with `snapshot_tagging.enabled = true` must share one `cadence` (single Glue trigger per setup) — Terraform must fail the plan if they don't.
- Out of scope, do not build: alarming (`optimizer_alarms.tf` extension), the empirical validation spike, mixed cadence support, query-time "as of tag" support.

---

## Task 1: `tagging_job.py` — pyiceberg snapshot-tagging script

**Files:**
- Create: `modules/federated_logs_partition/scripts/tagging_job.py`

**Interfaces:**
- Consumes: nothing from other tasks (no Terraform exists yet). Job arguments it expects at runtime (set by Task 3's `aws_glue_job.tagging`): `DATABASE_NAME` (string), `TABLE_TAG_CONFIG` (JSON string, `{table_name: {"retain_days": int}}`), `WAREHOUSE_PATH` (string, `s3://...`).
- Produces: nothing consumed in-process by later tasks — Task 3 only references this file's path on disk (`${path.module}/scripts/tagging_job.py`) for `aws_s3_object.tagging_script`.

There is no local pytest/unit-test harness for the Python scripts in this repo today — `retention_job.py` has none either; it's verified only via `python3 -m py_compile` locally and via the (out-of-scope) manual/e2e validation in production. This task follows that same precedent rather than introducing new test tooling.

- [ ] **Step 1: Write the script**

```python
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
        print(f"Tag name: {tag_name}, retain_days: {cfg['retain_days']}")

        try:
            table = catalog.load_table(f"{database}.{table_name}")

            # Idempotency: CREATE TAG fails if a ref with this name already
            # exists. Check first so a retried/overlapping run for the same
            # tick is a no-op, not a failure.
            if tag_name in table.refs():
                results[table_name] = "SKIPPED (already tagged this tick)"
                print(f"[{table_name}] Tag {tag_name} already exists, skipping")
                continue

            snapshot_id = table.current_snapshot().snapshot_id
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
```

- [ ] **Step 2: Syntax-check the script**

Run: `python3 -m py_compile modules/federated_logs_partition/scripts/tagging_job.py`
Expected: exits 0, no output. (This does not exercise `pyiceberg`/`awsglue` imports at runtime — those modules aren't installed locally; it only confirms the script parses. Runtime correctness against a real `pyiceberg` install is covered by the out-of-scope validation spike.)

- [ ] **Step 3: Commit**

```bash
git add modules/federated_logs_partition/scripts/tagging_job.py
git commit -m "feat: add pyiceberg snapshot tagging script"
```

---

## Task 2: Config surface — `snapshot_tagging` block on `optimizer_configuration`

**Files:**
- Modify: `modules/federated_logs_partition/variables.tf` (both the `default_table_setting` object type, currently lines 44-70, and the `partition_tables` object type, currently lines 72-108)
- Modify: `variables.tf` (root; both the `default_table_setting` object type, currently lines 75-99, and the `partition_tables` object type, currently lines 101-132)
- Test: `tests/partition.tftest.hcl`

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: every table object in `var.default_table_setting` / `var.partition_tables` now has `optimizer_configuration.snapshot_tagging` with fields `enabled` (bool, default `false`), `cadence` (string, default `"daily"`), `retain_days` (number, default `7`). Task 3's `locals.tf` reads these three fields by exactly these names off `local.all_tables[*].optimizer_configuration.snapshot_tagging`.

This task only touches the module used directly by `tests/partition.tftest.hcl` (`modules/federated_logs_partition`) for the *validation* rule, plus the root `variables.tf` for the *type* (schema) only. This mirrors an existing asymmetry already in this repo: `partition_tables`' reserved-name validation exists only in the module's `variables.tf`, not the root's — root doesn't mirror every module-level validation today, only the type shape that lets values flow through. The cadence *enum* validation (below) follows that same precedent: added to the module's `variables.tf`, which is what `tests/partition.tftest.hcl` exercises directly.

- [ ] **Step 1: Write the failing test**

Add to `tests/partition.tftest.hcl`:

```hcl
run "test_snapshot_tagging_schema_accepts_config" {
  command = plan

  variables {
    setup_name            = "inttest-partition"
    s3_bucket_name        = "test-bucket"
    glue_catalog_db_name  = "test_db"
    glue_service_role_arn = "arn:aws:iam::123456789012:role/test-role"
    setup_id              = "mock-setup-id"
    newrelic_account_id   = 12345678
    partition_tables = {
      "Log_backup_test" = {
        optimizer_configuration = {
          snapshot_tagging = {
            enabled     = true
            cadence     = "daily"
            retain_days = 14
          }
        }
      }
    }
  }

  module {
    source = "./modules/federated_logs_partition"
  }
}

run "test_snapshot_tagging_rejects_bad_cadence" {
  command = plan

  variables {
    setup_name            = "inttest-partition"
    s3_bucket_name        = "test-bucket"
    glue_catalog_db_name  = "test_db"
    glue_service_role_arn = "arn:aws:iam::123456789012:role/test-role"
    setup_id              = "mock-setup-id"
    newrelic_account_id   = 12345678
    partition_tables = {
      "Log_backup_test" = {
        optimizer_configuration = {
          snapshot_tagging = {
            enabled = true
            cadence = "weekly" # invalid — only "daily" or "hourly"
          }
        }
      }
    }
  }

  module {
    source = "./modules/federated_logs_partition"
  }

  expect_failures = [var.partition_tables]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `terraform test -filter=tests/partition.tftest.hcl`
Expected: `test_snapshot_tagging_schema_accepts_config` FAILs with an "Unsupported attribute" / "Value for undeclared attribute" error on `snapshot_tagging` (the field doesn't exist in the type yet). `test_snapshot_tagging_rejects_bad_cadence` also fails to even reach the validation (same undeclared-attribute error), which is fine — both are expected to fail before Step 3, for the same underlying reason.

- [ ] **Step 3: Add the schema to the module's `variables.tf`**

In `modules/federated_logs_partition/variables.tf`, inside `optimizer_configuration` in **both** `default_table_setting` and `partition_tables` (i.e. twice — once per object type), add, alongside the existing `orphan_file_deletion` / `snapshot_retention` / `compaction` blocks:

```hcl
      snapshot_tagging = optional(object({
        enabled     = optional(bool, false)
        cadence     = optional(string, "daily")
        retain_days = optional(number, 7)
      }), {})
```

Then add two new `validation` blocks to the file (after the existing ones), enforcing the cadence enum per variable:

```hcl
variable "default_table_setting" {
  # ...existing content unchanged...

  validation {
    condition     = contains(["daily", "hourly"], var.default_table_setting.optimizer_configuration.snapshot_tagging.cadence)
    error_message = "default_table_setting.optimizer_configuration.snapshot_tagging.cadence must be 'daily' or 'hourly'."
  }
}
```

```hcl
variable "partition_tables" {
  # ...existing content and existing validation blocks unchanged...

  validation {
    condition = alltrue([
      for k, v in var.partition_tables : contains(["daily", "hourly"], v.optimizer_configuration.snapshot_tagging.cadence)
    ])
    error_message = "optimizer_configuration.snapshot_tagging.cadence must be 'daily' or 'hourly' for every partition table."
  }
}
```

- [ ] **Step 4: Mirror the schema (type only, no new validation) in the root `variables.tf`**

In root `variables.tf`, inside `optimizer_configuration` in **both** `default_table_setting` and `partition_tables`, add the identical `snapshot_tagging` block from Step 3. Do not add the cadence-enum `validation` blocks here — see the note above on existing root/module validation asymmetry.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `terraform test -filter=tests/partition.tftest.hcl`
Expected: both new runs `pass`, and all pre-existing runs in the file still `pass` (no regression on `test_validation_rejects_reserved_name_lowercase` / `test_validation_rejects_reserved_name_mixed_case`).

- [ ] **Step 6: Commit**

```bash
git add variables.tf modules/federated_logs_partition/variables.tf tests/partition.tftest.hcl
git commit -m "feat: add snapshot_tagging config block to optimizer_configuration"
```

---

## Task 3: Cadence resolution, cross-table validation, and the tagging Glue job

**Files:**
- Modify: `modules/federated_logs_partition/locals.tf`
- Create: `modules/federated_logs_partition/tagging.tf`
- Test: `tests/partition.tftest.hcl`

**Interfaces:**
- Consumes: `optimizer_configuration.snapshot_tagging.{enabled,cadence,retain_days}` from Task 2's schema, off `local.all_tables` (already defined in `locals.tf`). Consumes `modules/federated_logs_partition/scripts/tagging_job.py` from Task 1 (referenced by path, not imported).
- Produces (new locals other tasks/resources may reference): `local.is_snapshot_tagging_enabled` (bool), `local.table_tag_config` (map of table name → `{retain_days = number}`), `local.tagging_cadences` (list of distinct cadence strings among enabled tables — used only by the precondition below), `local.tagging_cron_schedule` (string, a `cron(...)` expression). Produces resources `aws_s3_object.tagging_script`, `aws_glue_job.tagging`, `aws_glue_trigger.tagging_schedule`, `aws_cloudwatch_log_group.tagging_logs`, `terraform_data.tagging_cadence_check` — Task 4's `outputs.tf` will reference `aws_glue_job.tagging[0].name`.

This is one task, not two, because `tagging.tf`'s resources are unreviewable in isolation from the `locals.tf` values they read — a reviewer can't approve one without the other.

**On the cross-table cadence rule:** Terraform variable `validation {}` blocks can only see the variable being validated, so a rule that spans both `default_table_setting` and every entry of `partition_tables` (and must run at *plan* time, not just apply) needs a different mechanism. This plan uses a `terraform_data` resource with a `lifecycle.precondition` — verified locally against Terraform 1.14.6 with a scratch config before writing this plan: a `terraform_data` resource whose precondition fails does cause `terraform plan` to error, and `terraform test`'s `expect_failures` correctly accepts a resource address (not just a variable) as the failing checkable object.

- [ ] **Step 1: Write the failing tests**

Add to `tests/partition.tftest.hcl`:

```hcl
run "test_snapshot_tagging_cadence_mismatch_fails" {
  command = plan

  variables {
    setup_name            = "inttest-partition"
    s3_bucket_name        = "test-bucket"
    glue_catalog_db_name  = "test_db"
    glue_service_role_arn = "arn:aws:iam::123456789012:role/test-role"
    setup_id              = "mock-setup-id"
    newrelic_account_id   = 12345678
    default_table_setting = {
      optimizer_configuration = {
        snapshot_tagging = {
          enabled = true
          cadence = "daily"
        }
      }
    }
    partition_tables = {
      "Log_backup_test" = {
        optimizer_configuration = {
          snapshot_tagging = {
            enabled = true
            cadence = "hourly" # disagrees with default_table_setting's "daily"
          }
        }
      }
    }
  }

  module {
    source = "./modules/federated_logs_partition"
  }

  expect_failures = [terraform_data.tagging_cadence_check]
}

run "test_snapshot_tagging_enabled_creates_glue_job" {
  command = plan

  variables {
    setup_name            = "inttest-partition"
    s3_bucket_name        = "test-bucket"
    glue_catalog_db_name  = "test_db"
    glue_service_role_arn = "arn:aws:iam::123456789012:role/test-role"
    setup_id              = "mock-setup-id"
    newrelic_account_id   = 12345678
    partition_tables = {
      "Log_backup_test" = {
        optimizer_configuration = {
          snapshot_tagging = {
            enabled     = true
            cadence     = "daily"
            retain_days = 14
          }
        }
      }
    }
  }

  module {
    source = "./modules/federated_logs_partition"
  }

  assert {
    condition     = length(aws_glue_job.tagging) == 1
    error_message = "Expected exactly one tagging Glue job when a table has snapshot_tagging.enabled = true"
  }

  assert {
    condition     = aws_glue_job.tagging[0].command[0].name == "pythonshell"
    error_message = "Tagging job must be a Python Shell job, not Spark ETL"
  }

  assert {
    condition     = length(aws_glue_trigger.tagging_schedule) == 1 && aws_glue_trigger.tagging_schedule[0].schedule == "cron(0 0 * * ? *)"
    error_message = "Expected a daily tagging trigger with the standard midnight-UTC cron"
  }
}

run "test_snapshot_tagging_disabled_creates_nothing" {
  command = plan

  variables {
    setup_name            = "inttest-partition"
    s3_bucket_name        = "test-bucket"
    glue_catalog_db_name  = "test_db"
    glue_service_role_arn = "arn:aws:iam::123456789012:role/test-role"
    setup_id              = "mock-setup-id"
    newrelic_account_id   = 12345678
  }

  module {
    source = "./modules/federated_logs_partition"
  }

  assert {
    condition     = length(aws_glue_job.tagging) == 0
    error_message = "No table has snapshot_tagging.enabled — expected zero tagging Glue jobs"
  }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `terraform test -filter=tests/partition.tftest.hcl`
Expected: all three new runs FAIL — `terraform_data.tagging_cadence_check` and `aws_glue_job.tagging` / `aws_glue_trigger.tagging_schedule` don't exist yet, so Terraform reports "Reference to undeclared resource" for each.

- [ ] **Step 3: Add the new locals**

In `modules/federated_logs_partition/locals.tf`, after the existing `optimizer_failure_metrics` local (currently the last block, lines 106-112), add:

```hcl
  # Snapshot tagging configuration — tables that opted in (snapshot_tagging.enabled = true)
  tagging_enabled_tables = {
    for k, v in local.all_tables : k => v
    if v.optimizer_configuration.snapshot_tagging.enabled
  }

  is_snapshot_tagging_enabled = length(local.tagging_enabled_tables) > 0

  # Map of table name -> {retain_days}, passed into the Glue job's --TABLE_TAG_CONFIG argument
  table_tag_config = {
    for k, v in local.tagging_enabled_tables : k => {
      retain_days = v.optimizer_configuration.snapshot_tagging.retain_days
    }
  }

  # Distinct cadences among enabled tables. The Glue trigger has exactly one
  # cron schedule, so this must resolve to at most one value — enforced by
  # terraform_data.tagging_cadence_check's precondition in tagging.tf.
  tagging_cadences = distinct([
    for k, v in local.tagging_enabled_tables : v.optimizer_configuration.snapshot_tagging.cadence
  ])

  # Arbitrary pick when the precondition passes, since it guarantees at most
  # one distinct value. Falls back to "daily" when tagging is disabled
  # entirely (the trigger resource won't exist in that case, so this value
  # is unused, but the local must still evaluate).
  tagging_cadence = length(local.tagging_cadences) > 0 ? local.tagging_cadences[0] : "daily"

  tagging_cron_schedule = local.tagging_cadence == "hourly" ? "cron(0 * * * ? *)" : "cron(0 0 * * ? *)"
```

- [ ] **Step 4: Create `tagging.tf`**

```hcl
# S3 object to store the Glue Python Shell script
resource "aws_s3_object" "tagging_script" {
  count = local.is_snapshot_tagging_enabled ? 1 : 0

  bucket = var.s3_bucket_name
  key    = "${var.glue_catalog_db_name}/scripts/tagging_job.py"
  source = "${path.module}/scripts/tagging_job.py"
  etag   = filemd5("${path.module}/scripts/tagging_job.py")
}

# AWS Glue Python Shell job for periodic snapshot tagging.
# Python Shell (not Spark ETL) because tagging is a single metadata commit
# per table — no data scan, no distributed compute — so a full Spark cluster
# would be pure overhead. See docs/superpowers/plans/2026-08-25-snapshot-tagging.md
# and the linked design doc for the job-type comparison.
resource "aws_glue_job" "tagging" {
  count = local.is_snapshot_tagging_enabled ? 1 : 0

  name     = "${local.setup_naming_prefix}-tagging-job"
  role_arn = var.glue_service_role_arn

  command {
    name            = "pythonshell"
    script_location = "s3://${var.s3_bucket_name}/${aws_s3_object.tagging_script[0].key}"
    python_version  = "3.9"
  }

  max_capacity = 0.0625 # smallest Python Shell allocation — metadata-only workload
  timeout      = 15
  max_retries  = 1

  default_arguments = {
    "--enable-continuous-cloudwatch-log" = "true"
    "--additional-python-modules"        = "pyiceberg[glue]"
    "--DATABASE_NAME"                    = var.glue_catalog_db_name
    "--WAREHOUSE_PATH"                   = "s3://${var.s3_bucket_name}/warehouse/"
    "--TABLE_TAG_CONFIG"                 = jsonencode(local.table_tag_config)
  }

  depends_on = [aws_s3_object.tagging_script]
}

# Glue Trigger to schedule the tagging job. Cron resolves to daily
# (cron(0 0 * * ? *)) or hourly (cron(0 * * * ? *)) based on the single
# cadence shared by every table that has snapshot_tagging.enabled = true —
# see terraform_data.tagging_cadence_check below for why it's guaranteed
# to be single-valued.
resource "aws_glue_trigger" "tagging_schedule" {
  count = local.is_snapshot_tagging_enabled ? 1 : 0

  name     = "${local.setup_naming_prefix}-tagging-schedule"
  type     = "SCHEDULED"
  schedule = local.tagging_cron_schedule

  actions {
    job_name = aws_glue_job.tagging[0].name
  }
}

# CloudWatch Log Group for tagging job logs
resource "aws_cloudwatch_log_group" "tagging_logs" {
  count = local.is_snapshot_tagging_enabled ? 1 : 0

  name              = "/aws-glue/jobs/${local.setup_naming_prefix}-tagging-job"
  retention_in_days = 7
}

# Enforces that every table with snapshot_tagging.enabled = true agrees on
# cadence. One Glue trigger has exactly one cron schedule, so a mismatch
# across default_table_setting and partition_tables can't be honored.
# Implemented as a resource-level precondition (not a variable validation{}
# block) because the rule spans two separate variables, which variable
# validation blocks cannot see in Terraform >= 1.6.0 (the version floor
# declared in this repo's README) — that capability wasn't added until 1.9.
resource "terraform_data" "tagging_cadence_check" {
  count = local.is_snapshot_tagging_enabled ? 1 : 0

  input = "cadence-check"

  lifecycle {
    precondition {
      condition     = length(local.tagging_cadences) <= 1
      error_message = "All tables with snapshot_tagging.enabled = true must use the same cadence (one Glue trigger supports one cron schedule per setup). Found: ${join(", ", local.tagging_cadences)}."
    }
  }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `terraform test -filter=tests/partition.tftest.hcl`
Expected: all runs `pass`, including every pre-existing run in the file (no regression).

- [ ] **Step 6: Commit**

```bash
git add modules/federated_logs_partition/locals.tf modules/federated_logs_partition/tagging.tf tests/partition.tftest.hcl
git commit -m "feat: add tagging Glue job, trigger, and cross-table cadence validation"
```

---

## Task 4: Expose the tagging job name as a module output

**Files:**
- Modify: `modules/federated_logs_partition/outputs.tf`

**Interfaces:**
- Consumes: `aws_glue_job.tagging` and `local.is_snapshot_tagging_enabled` from Task 3.
- Produces: output `tagging_job_name`, mirroring the existing `retention_job_name` output. Not re-exported at the root — `retention_job_name` isn't re-exported at root either (checked: root `outputs.tf`'s current output set doesn't include it), so this keeps the same precedent.

- [ ] **Step 1: Add the output**

In `modules/federated_logs_partition/outputs.tf`, after the existing `retention_job_name` output, add:

```hcl
output "tagging_job_name" {
  description = "Name of the Glue snapshot tagging job (if enabled on any table)"
  value       = local.is_snapshot_tagging_enabled ? aws_glue_job.tagging[0].name : null
}
```

- [ ] **Step 2: Verify the plan still succeeds**

Run: `terraform test -filter=tests/partition.tftest.hcl`
Expected: all runs still `pass` (an output addition can't fail a plan-only test, but this confirms no typo broke evaluation).

- [ ] **Step 3: Commit**

```bash
git add modules/federated_logs_partition/outputs.tf
git commit -m "feat: expose tagging_job_name output"
```

---

## Task 5: Document `snapshot_tagging` in the README

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: nothing programmatic — this is documentation only, describing the config surface from Tasks 2-3.

- [ ] **Step 1: Add `snapshot_tagging` to the example `optimizer_configuration` block**

In `README.md`, inside the `optimizer_configuration = { ... }` block under `default_table_setting` (currently lines 61-77), add a `snapshot_tagging` entry alongside the existing three, with a comment noting it's opt-in:

```hcl
    optimizer_configuration = {
      orphan_file_deletion = {
        orphan_file_retention_period_in_days = 3
        run_rate_in_hours                    = 24
      }
      snapshot_retention = {
        snapshot_retention_period_in_days = 1
        number_of_snapshots_to_retain     = 1
        clean_expired_files               = false
        run_rate_in_hours                 = 3
      }
      compaction = {
        strategy              = "binpack"
        min_input_files       = 5
        delete_file_threshold = 1
      }
      # Opt-in: periodic protected recovery point. Disabled by default —
      # see snapshot_tagging under Inputs below before enabling.
      snapshot_tagging = {
        enabled     = false
        cadence     = "daily"
        retain_days = 7
      }
    }
```

- [ ] **Step 2: Add a row to the Inputs table**

In `README.md`'s `## Inputs` table (currently around line 129-143), the `default_table_setting` and `partition_tables` rows already say "(retention, table parameters, optimizer config)" / "(...optimizer config...)" generically — no per-field rows exist for the other `optimizer_configuration` sub-blocks either, so no new table row is needed; the nested block is documented via the example above, consistent with how `orphan_file_deletion` / `snapshot_retention` / `compaction` are already documented (example-only, no Inputs-table rows of their own).

Instead, add one sentence to the `optimizer_configuration` comment block that already exists above the variable declarations, documenting the new sub-block's defaults, matching the existing comment style (lines 22-36 of the module's `variables.tf`, mirrored in root `variables.tf`):

In both `modules/federated_logs_partition/variables.tf` and root `variables.tf`, extend the existing comment block:

```hcl
#──────────────────────────────────────────────────────────────
# Optimizer configuration defaults (for both variables below):
#   orphan_file_deletion:
#     orphan_file_retention_period_in_days = 3
#     run_rate_in_hours                    = 24
#   snapshot_retention:
#     snapshot_retention_period_in_days    = 1
#     number_of_snapshots_to_retain        = 1
#     clean_expired_files                  = false
#     run_rate_in_hours                    = 3
#   compaction:
#     strategy                             = "binpack"
#     min_input_files                      = 5
#     delete_file_threshold                = 1
#   snapshot_tagging (opt-in periodic protected recovery point; disabled by default):
#     enabled                              = false
#     cadence                              = "daily"  # "daily" | "hourly"
#     retain_days                          = 7
#──────────────────────────────────────────────────────────────
```

- [ ] **Step 3: Verify markdown renders sanely**

Run: `grep -n "snapshot_tagging" README.md modules/federated_logs_partition/variables.tf variables.tf`
Expected: matches in all three files, at the locations just edited.

- [ ] **Step 4: Commit**

```bash
git add README.md modules/federated_logs_partition/variables.tf variables.tf
git commit -m "docs: document snapshot_tagging config block"
```
