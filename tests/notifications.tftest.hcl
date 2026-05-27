# =============================================================================
# Integration Tests: federated_logs_setup_notifications module
# =============================================================================
#
# What we test here:
#   1. EventBridge rule naming conventions
#   2. EventBridge rule event pattern structure
#   3. Module dependency wiring (uses setup_resource and role outputs correctly)
#
# =============================================================================

# Mock the external provider to avoid requiring NEWRELIC_API_KEY in CI
mock_provider "external" {
  mock_data "external" {
    defaults = {
      result = {
        role_arn      = "arn:aws:iam::123456789012:role/mock-role"
        sqs_queue_arn = "arn:aws:sqs:us-east-1:123456789012:mock-queue"
      }
    }
  }
}

# Shared test variables
variables {
  fleet_entity_guid = "test-fleet-entity-guid"
  newrelic_region   = "US"
}

# =============================================================================
# NAMING CONVENTION TESTS
# =============================================================================

# -----------------------------------------------------------------------------
# TEST: EventBridge rule naming convention
# -----------------------------------------------------------------------------
run "test_eventbridge_rule_naming" {
  command = plan

  variables {
    setup_name          = "inttest-notif-01"
    s3_bucket_id        = "newrelic-fed-logs-inttest-notif-01"
    pcg_writer_role_arn = "arn:aws:iam::123456789012:role/newrelic-fed-logs-inttest-notif-01-pcg-writer"
    fleet_entity_guid   = var.fleet_entity_guid
    newrelic_region     = var.newrelic_region
  }

  module {
    source = "./modules/federated_logs_setup_notifications"
  }

  # Verify EventBridge rule name follows pattern
  assert {
    condition     = output.eventbridge_rule_name == "inttest-notif-01-iceberg-file-created"
    error_message = "EventBridge rule name should be '{setup_name}-iceberg-file-created'. Got: ${output.eventbridge_rule_name}"
  }
}

# -----------------------------------------------------------------------------
# TEST: EventBridge rule ARN is populated
# -----------------------------------------------------------------------------
run "test_eventbridge_rule_arn_output" {
  command = plan

  variables {
    setup_name          = "inttest-notif-02"
    s3_bucket_id        = "newrelic-fed-logs-inttest-notif-02"
    pcg_writer_role_arn = "arn:aws:iam::123456789012:role/newrelic-fed-logs-inttest-notif-02-pcg-writer"
    fleet_entity_guid   = var.fleet_entity_guid
    newrelic_region     = var.newrelic_region
  }

  module {
    source = "./modules/federated_logs_setup_notifications"
  }

  # Verify EventBridge rule ARN is not empty
  assert {
    condition     = output.eventbridge_rule_arn != ""
    error_message = "EventBridge rule ARN should not be empty"
  }
}

# =============================================================================
# INPUT VALIDATION TESTS
# =============================================================================

# -----------------------------------------------------------------------------
# TEST: newrelic_region validation - valid US
# -----------------------------------------------------------------------------
run "test_newrelic_region_us" {
  command = plan

  variables {
    setup_name          = "inttest-region-us"
    s3_bucket_id        = "newrelic-fed-logs-inttest-region-us"
    pcg_writer_role_arn = "arn:aws:iam::123456789012:role/test-role"
    fleet_entity_guid   = "test-fleet-guid"
    newrelic_region     = "US"
  }

  module {
    source = "./modules/federated_logs_setup_notifications"
  }

  # No expect_failures = plan should succeed
}

# -----------------------------------------------------------------------------
# TEST: newrelic_region validation - valid EU
# -----------------------------------------------------------------------------
run "test_newrelic_region_eu" {
  command = plan

  variables {
    setup_name          = "inttest-region-eu"
    s3_bucket_id        = "newrelic-fed-logs-inttest-region-eu"
    pcg_writer_role_arn = "arn:aws:iam::123456789012:role/test-role"
    fleet_entity_guid   = "test-fleet-guid"
    newrelic_region     = "EU"
  }

  module {
    source = "./modules/federated_logs_setup_notifications"
  }

  # No expect_failures = plan should succeed
}

# -----------------------------------------------------------------------------
# TEST: newrelic_region validation - valid STAGING
# -----------------------------------------------------------------------------
run "test_newrelic_region_staging" {
  command = plan

  variables {
    setup_name          = "inttest-region-stg"
    s3_bucket_id        = "newrelic-fed-logs-inttest-region-stg"
    pcg_writer_role_arn = "arn:aws:iam::123456789012:role/test-role"
    fleet_entity_guid   = "test-fleet-guid"
    newrelic_region     = "STAGING"
  }

  module {
    source = "./modules/federated_logs_setup_notifications"
  }

  # No expect_failures = plan should succeed
}

# -----------------------------------------------------------------------------
# TEST: newrelic_region validation - invalid value rejected
# -----------------------------------------------------------------------------
run "test_newrelic_region_invalid" {
  command = plan

  variables {
    setup_name          = "inttest-region-bad"
    s3_bucket_id        = "newrelic-fed-logs-inttest-region-bad"
    pcg_writer_role_arn = "arn:aws:iam::123456789012:role/test-role"
    fleet_entity_guid   = "test-fleet-guid"
    newrelic_region     = "INVALID"
  }

  module {
    source = "./modules/federated_logs_setup_notifications"
  }

  expect_failures = [var.newrelic_region]
}
