# =============================================================================
# Integration Tests: federated_logs_partition module
# =============================================================================
#
# Test Structure:
#   1. Validation tests (plan-only, no AWS resources)
#   2. Shared setup (one S3 bucket, Glue DB, IAM roles)
#   3. Sequential functional tests (build on each other)
#
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

provider "aws" {
  region = "us-east-1"
}

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

# =============================================================================
# SHARED SETUP (used by all functional tests)
# =============================================================================

run "setup" {
  command = apply

  variables {
    setup_name = "inttest-partition"
  }

  module {
    source = "./modules/federated_logs_setup_resource"
  }
}

run "roles" {
  command = apply

  variables {
    setup_name           = run.setup.setup_name
    s3_bucket_name       = run.setup.s3_bucket_name
    glue_catalog_db_name = run.setup.glue_catalog_db_name
    fleet_entity_guid    = "test-fleet-entity-guid"
    newrelic_account_id  = 12345678
    newrelic_org_id      = "test-nr-org-id"
    newrelic_region      = "US"
  }

  # Mock the NGEP fetch — no NR API call needed
  override_data {
    target = data.external.base_role
    values = {
      result = {
        role_arn                = "arn:aws:iam::123456789012:role/mock-base-role"
        base_role_connection_id = "mock-connection-guid"
        sqs_queue_arn           = "arn:aws:sqs:us-east-1:123456789012:mock-queue"
        flink_base_role_arn     = "arn:aws:iam::123456789012:role/mock-flink-base-role"
      }
    }
  }

  # Skip pcg-writer role creation: its trust policy principal (an IAM role ARN)
  # is mocked, so AWS would reject the fake account ID. The partition tests only
  # need glue_service_role_arn, not the pcg-writer role.
  override_resource {
    target = aws_iam_role.pcg-writer-role
    values = {
      arn  = "arn:aws:iam::000000000000:role/mock-pcg-writer"
      name = "mock-pcg-writer"
      tags = {}
    }
  }

  # Skip the policy attachment since the role above is mocked and doesn't exist in AWS
  override_resource {
    target = aws_iam_role_policy_attachment.writer_attach
    values = {}
  }

  module {
    source = "./modules/federated_logs_role"
  }
}

# =============================================================================
# FUNCTIONAL TESTS (sequential, building on shared setup)
# =============================================================================

# -----------------------------------------------------------------------------
# Test: Default table is always created (no custom tables)
# -----------------------------------------------------------------------------
run "test_default_table_only" {
  command = apply

  variables {
    setup_name            = run.setup.setup_name
    s3_bucket_name        = run.setup.s3_bucket_name
    glue_catalog_db_name  = run.setup.glue_catalog_db_name
    glue_service_role_arn = run.roles.glue_service_role_arn
    setup_id              = run.roles.setup_id
    newrelic_account_id   = 12345678
    # No partition_tables - should still create default table
  }

  module {
    source = "./modules/federated_logs_partition"
  }

  assert {
    condition     = length(output.all_tables) == 1
    error_message = "Should have exactly 1 table (default) when no custom tables specified. Got: ${length(output.all_tables)}"
  }
}

# -----------------------------------------------------------------------------
# Test: Add custom tables (default + 2 custom = 3 tables)
# -----------------------------------------------------------------------------
run "test_add_custom_tables" {
  command = apply

  variables {
    setup_name            = run.setup.setup_name
    s3_bucket_name        = run.setup.s3_bucket_name
    glue_catalog_db_name  = run.setup.glue_catalog_db_name
    glue_service_role_arn = run.roles.glue_service_role_arn
    setup_id              = run.roles.setup_id
    newrelic_account_id   = 12345678
    partition_tables = {
      "app_logs"      = {}
      "security_logs" = {}
    }
  }

  module {
    source = "./modules/federated_logs_partition"
  }

  assert {
    condition     = length(output.all_tables) == 3
    error_message = "Should have 3 tables (1 default + 2 custom). Got: ${length(output.all_tables)}"
  }
}

# -----------------------------------------------------------------------------
# Test: Table names with special characters are sanitized
# -----------------------------------------------------------------------------
run "test_table_name_sanitization" {
  command = apply

  variables {
    setup_name            = run.setup.setup_name
    s3_bucket_name        = run.setup.s3_bucket_name
    glue_catalog_db_name  = run.setup.glue_catalog_db_name
    glue_service_role_arn = run.roles.glue_service_role_arn
    setup_id              = run.roles.setup_id
    newrelic_account_id   = 12345678
    partition_tables = {
      "app_logs"       = {}
      "security_logs"  = {}
      "My-App.Logs"    = {} # Contains hyphen and dot
      "UPPERCASE_NAME" = {} # Contains uppercase
    }
  }

  module {
    source = "./modules/federated_logs_partition"
  }

  assert {
    condition     = length(output.all_tables) == 5
    error_message = "Should have 5 tables (1 default + 4 custom). Got: ${length(output.all_tables)}"
  }

  # Verify all table names are sanitized (lowercase, alphanumeric, underscores only)
  assert {
    condition = alltrue([
      for name, _ in output.all_tables :
      can(regex("^[a-z0-9_]+$", name))
    ])
    error_message = "All table names should be lowercase with only alphanumeric and underscores"
  }

  # Verify all table names include the setup prefix
  assert {
    condition = alltrue([
      for name, _ in output.all_tables :
      startswith(name, "newrelic_fed_logs_inttest_partition_")
    ])
    error_message = "All table names should start with 'newrelic_fed_logs_inttest_partition_' prefix"
  }
}

# -----------------------------------------------------------------------------
# Test: Custom optimizer configuration is accepted
# -----------------------------------------------------------------------------
run "test_custom_optimizer_config" {
  command = apply

  variables {
    setup_name            = run.setup.setup_name
    s3_bucket_name        = run.setup.s3_bucket_name
    glue_catalog_db_name  = run.setup.glue_catalog_db_name
    glue_service_role_arn = run.roles.glue_service_role_arn
    setup_id              = run.roles.setup_id
    newrelic_account_id   = 12345678
    partition_tables = {
      "app_logs"       = {}
      "security_logs"  = {}
      "My-App.Logs"    = {}
      "UPPERCASE_NAME" = {}
      "custom_config_table" = {
        table_parameters = {
          "custom_param" = "custom_value"
        }
        optimizer_configuration = {
          orphan_file_deletion = {
            orphan_file_retention_period_in_days = 7
            run_rate_in_hours                    = 12
          }
          snapshot_retention = {
            snapshot_retention_period_in_days = 10
            number_of_snapshots_to_retain     = 5
            clean_expired_files               = true
            run_rate_in_hours                 = 12
          }
        }
      }
    }
  }

  module {
    source = "./modules/federated_logs_partition"
  }

  assert {
    condition     = length(output.all_tables) == 6
    error_message = "Should have 6 tables (1 default + 5 custom). Got: ${length(output.all_tables)}"
  }
}

# -----------------------------------------------------------------------------
# Test: Remove some tables
# -----------------------------------------------------------------------------
run "test_remove_some_tables" {
  command = apply

  variables {
    setup_name            = run.setup.setup_name
    s3_bucket_name        = run.setup.s3_bucket_name
    glue_catalog_db_name  = run.setup.glue_catalog_db_name
    glue_service_role_arn = run.roles.glue_service_role_arn
    setup_id              = run.roles.setup_id
    newrelic_account_id   = 12345678
    partition_tables = {
      "app_logs"      = {}
      "security_logs" = {}
    }
  }

  module {
    source = "./modules/federated_logs_partition"
  }

  assert {
    condition     = length(output.all_tables) == 3
    error_message = "Should have 3 tables after removing custom tables. Got: ${length(output.all_tables)}"
  }
}

# -----------------------------------------------------------------------------
# Test: Remove all custom tables (back to default only)
# -----------------------------------------------------------------------------
run "test_remove_all_custom" {
  command = apply

  variables {
    setup_name            = run.setup.setup_name
    s3_bucket_name        = run.setup.s3_bucket_name
    glue_catalog_db_name  = run.setup.glue_catalog_db_name
    glue_service_role_arn = run.roles.glue_service_role_arn
    setup_id              = run.roles.setup_id
    newrelic_account_id   = 12345678
    # No partition_tables - back to default only
  }

  module {
    source = "./modules/federated_logs_partition"
  }

  assert {
    condition     = length(output.all_tables) == 1
    error_message = "Should have 1 table (default only) after removing all custom. Got: ${length(output.all_tables)}"
  }
}

# -----------------------------------------------------------------------------
# Test: Custom default table settings
# -----------------------------------------------------------------------------
run "test_custom_default_table_setting" {
  command = apply

  variables {
    setup_name            = run.setup.setup_name
    s3_bucket_name        = run.setup.s3_bucket_name
    glue_catalog_db_name  = run.setup.glue_catalog_db_name
    glue_service_role_arn = run.roles.glue_service_role_arn
    setup_id              = run.roles.setup_id
    newrelic_account_id   = 12345678
    default_table_setting = {
      table_parameters = {
        "default_custom_param" = "default_custom_value"
      }
    }
    # No custom partition_tables - just customized default
  }

  module {
    source = "./modules/federated_logs_partition"
  }

  assert {
    condition     = length(output.all_tables) == 1
    error_message = "Should have exactly 1 table (customized default). Got: ${length(output.all_tables)}"
  }
}

# =============================================================================
# CLEANUP (empty bucket before destroy)
# =============================================================================
# Iceberg creates metadata files that Terraform doesn't manage.
# Empty the bucket before destroy to prevent "BucketNotEmpty" errors.
# =============================================================================

run "cleanup_bucket" {
  command = apply

  variables {
    bucket_name = run.setup.s3_bucket_name
  }

  module {
    source = "./tests/helpers/empty_bucket"
  }
}
