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
