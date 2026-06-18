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
