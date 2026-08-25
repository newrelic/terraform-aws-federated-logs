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

run "test_snapshot_tagging_explicit_values_pass_through" {
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
            cadence     = "hourly"
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
    condition     = var.partition_tables["Log_backup_test"].optimizer_configuration.snapshot_tagging.enabled == true
    error_message = "snapshot_tagging.enabled should be true as explicitly set"
  }
  assert {
    condition     = var.partition_tables["Log_backup_test"].optimizer_configuration.snapshot_tagging.cadence == "hourly"
    error_message = "snapshot_tagging.cadence should be hourly as explicitly set"
  }
  assert {
    condition     = var.partition_tables["Log_backup_test"].optimizer_configuration.snapshot_tagging.retain_days == 14
    error_message = "snapshot_tagging.retain_days should be 14 as explicitly set"
  }
}

run "test_snapshot_tagging_defaults_apply_when_omitted" {
  command = plan

  variables {
    setup_name            = "inttest-partition"
    s3_bucket_name        = "test-bucket"
    glue_catalog_db_name  = "test_db"
    glue_service_role_arn = "arn:aws:iam::123456789012:role/test-role"
    setup_id              = "mock-setup-id"
    newrelic_account_id   = 12345678
    partition_tables = {
      "Log_backup_test" = {}
    }
  }

  module {
    source = "./modules/federated_logs_partition"
  }

  assert {
    condition     = var.partition_tables["Log_backup_test"].optimizer_configuration.snapshot_tagging.enabled == false
    error_message = "snapshot_tagging.enabled should default to false"
  }
  assert {
    condition     = var.partition_tables["Log_backup_test"].optimizer_configuration.snapshot_tagging.cadence == "daily"
    error_message = "snapshot_tagging.cadence should default to daily"
  }
  assert {
    condition     = var.partition_tables["Log_backup_test"].optimizer_configuration.snapshot_tagging.retain_days == 7
    error_message = "snapshot_tagging.retain_days should default to 7"
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

# Two tables that AGREE on a non-default cadence. Guards two regressions that
# every other run in this file tolerates:
#   1. A precondition counting tables instead of distinct cadences
#      (length(local.tagging_enabled_tables) vs length(local.tagging_cadences))
#      — the mismatch test above uses 2 tables with 2 cadences, so those two
#      quantities are equal there and expect_failures cannot tell them apart.
#   2. A hardcoded daily cron — the only other run asserting on the schedule
#      uses cadence = "daily", which a constant also satisfies.
# Also confirms table_tag_config spans BOTH default_table_setting and
# partition_tables, and that one Glue job is created per setup, not per table.
run "test_snapshot_tagging_agreeing_cadence_multi_table_hourly" {
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
          enabled     = true
          cadence     = "hourly"
          retain_days = 3
        }
      }
    }
    partition_tables = {
      "Log_backup_test" = {
        optimizer_configuration = {
          snapshot_tagging = {
            enabled     = true
            cadence     = "hourly" # agrees with default_table_setting
            retain_days = 21
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
    error_message = "Two tagging-enabled tables must still yield exactly one Glue job per setup, not one per table"
  }

  assert {
    condition     = aws_glue_trigger.tagging_schedule[0].schedule == "cron(0 * * * ? *)"
    error_message = "Both tables use cadence = hourly, so the trigger must use the hourly cron, got ${aws_glue_trigger.tagging_schedule[0].schedule}"
  }

  assert {
    condition     = length(jsondecode(aws_glue_job.tagging[0].default_arguments["--TABLE_TAG_CONFIG"])) == 2
    error_message = "TABLE_TAG_CONFIG must contain both the default table and the partition table, got ${aws_glue_job.tagging[0].default_arguments["--TABLE_TAG_CONFIG"]}"
  }
}
