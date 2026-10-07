locals {
  dashboard_name = coalesce(var.dashboard_name, "Federated Logs - ${var.setup_name}")

  naming_prefix         = "newrelic-fed-logs-${var.setup_name}"
  glue_prefix           = "newrelic_fed_logs_${var.setup_name}"
  eventbridge_rule_name = "${local.naming_prefix}-iceberg-file-created"
  glue_retention_job    = "${local.glue_prefix}-retention-job"

  # Derive resource names from the SQS queue ARN (arn:aws:sqs:<region>:<account>:<name>)
  sqs_queue_name = element(split(":", var.sqs_queue_arn), 5)
  fleet_prefix   = replace(local.sqs_queue_name, "-flink-sqs-queue", "")
  sqs_dlq_name   = "${local.fleet_prefix}-flink-sqs-dlq"
  flink_app_name = "${local.fleet_prefix}-flink-application"
}
