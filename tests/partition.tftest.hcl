# =============================================================================
# Plan-only validation tests for federated_logs_partition
# =============================================================================
# Mock the external provider to avoid requiring NEW_RELIC_API_KEY in CI
mock_provider "external" {
  mock_data "external" {
    defaults = {
      result = {
        role_arn                = "arn:aws:iam::123456789012:role/mock-role"
        base_role_connection_id = "mock-connection-guid"
        sqs_queue_arn           = "arn:aws:sqs:us-east-1:123456789012:mock-queue"
        flink_base_role_arn     = "arn:aws:iam::123456789012:role/mock-flink-base-role"
      }
    }
  }
}

# Mock New Relic provider (account_id is required)
mock_provider "newrelic" {}

# Mock AWS provider for plan-only tests (no real credentials required)
mock_provider "aws" {}

# =============================================================================
# VALIDATION TESTS (plan-only, no AWS resources needed)
# =============================================================================

run "test_validation_rejects_reserved_name_lowercase" {
  command = plan

  variables {
    setup_name            = "inttest-partition"
    s3_bucket_name        = "test-bucket"
    glue_catalog_db_name  = "test_db"
    glue_service_role_arn = "arn:aws:iam::123456789012:role/test-role"
    setup_id              = "mock-setup-id"
    newrelic_account_id   = 12345678
    partition_tables = {
      "log_federated" = {} # Reserved name - should fail
    }
  }

  module {
    source = "./modules/federated_logs_partition"
  }

  expect_failures = [var.partition_tables]
}

run "test_validation_rejects_reserved_name_mixed_case" {
  command = plan

  variables {
    setup_name            = "inttest-partition"
    s3_bucket_name        = "test-bucket"
    glue_catalog_db_name  = "test_db"
    glue_service_role_arn = "arn:aws:iam::123456789012:role/test-role"
    setup_id              = "mock-setup-id"
    newrelic_account_id   = 12345678
    partition_tables = {
      "Log_Federated" = {} # Reserved name (mixed case) - should fail
    }
  }

  module {
    source = "./modules/federated_logs_partition"
  }

  expect_failures = [var.partition_tables]
}

# Asserts on the --TABLE_TAG_CONFIG the module renders (not on the input
# variable), so it also pins the sanitized-key contract tagging_job.py relies
# on: keys are full Glue table names, covering both default_table_setting and
# every partition table, with retain_days defaulting to 15 when omitted.
run "test_snapshot_tagging_renders_table_tag_config" {
  command = plan

  variables {
    setup_name               = "inttest-partition"
    s3_bucket_name           = "test-bucket"
    glue_catalog_db_name     = "test_db"
    glue_service_role_arn    = "arn:aws:iam::123456789012:role/test-role"
    setup_id                 = "mock-setup-id"
    newrelic_account_id      = 12345678
    snapshot_tagging_enabled = true
    partition_tables = {
      "Log_backup-test" = {
        optimizer_configuration = {
          snapshot_tagging = {
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
    condition = jsondecode(aws_glue_job.tagging[0].default_arguments["--TABLE_TAG_CONFIG"]) == {
      newrelic_fed_logs_inttest_partition_log_federated   = { retain_days = 15 }
      newrelic_fed_logs_inttest_partition_log_backup_test = { retain_days = 14 }
    }
    error_message = "TABLE_TAG_CONFIG must map every sanitized table name to its retain_days (default 15), got ${aws_glue_job.tagging[0].default_arguments["--TABLE_TAG_CONFIG"]}"
  }
}

# Retention deliberately left disabled: the code-artifacts bucket must still
# be created for the tagging script alone.
run "test_snapshot_tagging_enabled_creates_glue_job" {
  command = plan

  variables {
    setup_name               = "inttest-partition"
    s3_bucket_name           = "test-bucket"
    glue_catalog_db_name     = "test_db"
    glue_service_role_arn    = "arn:aws:iam::123456789012:role/test-role"
    setup_id                 = "mock-setup-id"
    newrelic_account_id      = 12345678
    snapshot_tagging_enabled = true
    data_retention_enabled   = false
  }

  module {
    source = "./modules/federated_logs_partition"
  }

  assert {
    condition     = length(aws_glue_job.tagging) == 1
    error_message = "Expected exactly one tagging Glue job per setup when snapshot_tagging_enabled = true"
  }

  assert {
    condition     = aws_glue_job.tagging[0].command[0].name == "pythonshell"
    error_message = "Tagging job must be a Python Shell job, not Spark ETL"
  }

  assert {
    condition     = length(aws_glue_trigger.tagging_schedule) == 1 && aws_glue_trigger.tagging_schedule[0].schedule == "cron(0 1 * * ? *)"
    error_message = "Expected a daily tagging trigger at 01:00 UTC, offset from the retention job's midnight cron"
  }

  assert {
    condition     = aws_glue_job.tagging[0].default_arguments["--additional-python-modules"] == "pyarrow==14.0.2,pyiceberg[glue]==0.10.0"
    error_message = "pyiceberg/pyarrow must stay pinned to the exact pair verified on Python Shell 3.9, got ${aws_glue_job.tagging[0].default_arguments["--additional-python-modules"]}"
  }

  assert {
    condition     = length(aws_s3_bucket.retention_scripts) == 1
    error_message = "The code-artifacts bucket must be created for the tagging script even when data retention is disabled"
  }

  assert {
    condition     = aws_glue_job.tagging[0].command[0].script_location == "s3://newrelic-fed-logs-inttest-partition-code-artifacts/scripts/tagging_job.py"
    error_message = "Tagging job must run the script from the code-artifacts bucket, got ${aws_glue_job.tagging[0].command[0].script_location}"
  }
}

run "test_snapshot_tagging_disabled_creates_nothing" {
  command = plan

  variables {
    setup_name             = "inttest-partition"
    s3_bucket_name         = "test-bucket"
    glue_catalog_db_name   = "test_db"
    glue_service_role_arn  = "arn:aws:iam::123456789012:role/test-role"
    setup_id               = "mock-setup-id"
    newrelic_account_id    = 12345678
    data_retention_enabled = false
  }

  module {
    source = "./modules/federated_logs_partition"
  }

  assert {
    condition     = length(aws_glue_job.tagging) == 0 && length(aws_glue_trigger.tagging_schedule) == 0
    error_message = "snapshot_tagging_enabled defaults to false — expected no tagging job or trigger"
  }

  assert {
    condition     = length(aws_s3_bucket.retention_scripts) == 0
    error_message = "With neither retention nor tagging enabled, no code-artifacts bucket should be created"
  }
}

# retain_days = 0 produces a tag with max_ref_age_ms = 0 that expires the
# instant it's written — the job reports SUCCESS while protecting nothing.
# Placed last in the file deliberately: a failing run aborts every run after
# it, so new runs go at the end rather than in the middle.
run "test_snapshot_tagging_rejects_zero_retain_days" {
  command = plan

  variables {
    setup_name               = "inttest-partition"
    s3_bucket_name           = "test-bucket"
    glue_catalog_db_name     = "test_db"
    glue_service_role_arn    = "arn:aws:iam::123456789012:role/test-role"
    setup_id                 = "mock-setup-id"
    newrelic_account_id      = 12345678
    snapshot_tagging_enabled = true
    partition_tables = {
      "Log_backup_test" = {
        optimizer_configuration = {
          snapshot_tagging = {
            retain_days = 0
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
