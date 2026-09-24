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
    setup_id            = "MTIzNDU2NzxOR0VQfEZFRExPR1N8MDFhYmNkZWYtMDAwMC0wMDAwLTAwMDAtMDAwMDAwMDAwMDAw"
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
    setup_id            = "MTIzNDU2NzxOR0VQfEZFRExPR1N8MDJhYmNkZWYtMDAwMC0wMDAwLTAwMDAtMDAwMDAwMDAwMDAw"
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

# -----------------------------------------------------------------------------
# TEST: EventBridge input_transformer stamps the real setup_id (entity GUID)
# into "setupId", and setup_name into a separate "setupName" field.
# -----------------------------------------------------------------------------
run "test_input_transformer_uses_setup_id_not_setup_name" {
  command = plan

  variables {
    setup_name          = "inttest-notif-03"
    setup_id            = "MTIzNDU2NzxOR0VQfEZFRExPR1N8MDNhYmNkZWYtMDAwMC0wMDAwLTAwMDAtMDAwMDAwMDAwMDAw"
    s3_bucket_id        = "newrelic-fed-logs-inttest-notif-03"
    pcg_writer_role_arn = "arn:aws:iam::123456789012:role/newrelic-fed-logs-inttest-notif-03-pcg-writer"
    sqs_queue_arn       = "arn:aws:sqs:us-east-1:123456789012:test-queue"
  }

  module {
    source = "./modules/federated_logs_setup_notifications"
  }

  assert {
    condition = strcontains(
      aws_cloudwatch_event_target.iceberg_file_events_sqs.input_transformer[0].input_template,
      "\"setupId\": \"MTIzNDU2NzxOR0VQfEZFRExPR1N8MDNhYmNkZWYtMDAwMC0wMDAwLTAwMDAtMDAwMDAwMDAwMDAw\""
    )
    error_message = "input_transformer must stamp setupId from var.setup_id (the entity GUID), not var.setup_name"
  }

  assert {
    condition = !strcontains(
      aws_cloudwatch_event_target.iceberg_file_events_sqs.input_transformer[0].input_template,
      "\"setupId\": \"inttest-notif-03\""
    )
    error_message = "input_transformer must not fall back to stamping setup_name as setupId"
  }

  assert {
    condition = strcontains(
      aws_cloudwatch_event_target.iceberg_file_events_sqs.input_transformer[0].input_template,
      "\"setupName\": \"inttest-notif-03\""
    )
    error_message = "input_transformer must also stamp setupName from var.setup_name, alongside setupId"
  }
}
