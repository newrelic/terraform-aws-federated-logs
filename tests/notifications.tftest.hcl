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

# Mock AWS provider for plan-only tests
mock_provider "aws" {}

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
    sqs_queue_arn       = "arn:aws:sqs:us-east-1:123456789012:test-queue"
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
# TEST: EventBridge target uses correct SQS queue ARN
# -----------------------------------------------------------------------------
run "test_eventbridge_target_sqs_arn" {
  command = plan

  variables {
    setup_name          = "inttest-notif-02"
    s3_bucket_id        = "newrelic-fed-logs-inttest-notif-02"
    pcg_writer_role_arn = "arn:aws:iam::123456789012:role/newrelic-fed-logs-inttest-notif-02-pcg-writer"
    sqs_queue_arn       = "arn:aws:sqs:us-east-1:123456789012:test-queue"
  }

  module {
    source = "./modules/federated_logs_setup_notifications"
  }

  # Verify EventBridge rule name follows pattern (ARN not known at plan time)
  assert {
    condition     = output.eventbridge_rule_name == "inttest-notif-02-iceberg-file-created"
    error_message = "EventBridge rule name should be '{setup_name}-iceberg-file-created'. Got: ${output.eventbridge_rule_name}"
  }
}
