output "base_role_arn" {
  description = "ARN of the fleet-level PCG base role. Pass this to each federated_logs_setup module as base_role_arn."
  value       = aws_iam_role.base_role.arn
}

output "base_role_name" {
  description = "Name of the fleet-level PCG base role."
  value       = aws_iam_role.base_role.name
}

output "aws_connection_entity_name" {
  description = "Name of the AWS Connection entity created in New Relic. Use this to look up the entity in the NR UI."
  value       = "${local.naming_prefix}-aws-connection"
}

output "fleet_ingest_connection_id" {
  description = "Entity GUID of the AWS Connection wrapping the fleet base role."
  value       = newrelic_aws_connection.fleet_ingest.id
}

output "base_role_tags" {
  description = "Tags applied to the fleet-level base role."
  value       = aws_iam_role.base_role.tags
}

output "abac_policy_json" {
  description = "JSON of the ABAC inline policy attached to the base role."
  value       = aws_iam_role_policy.abac_assume_policy.policy
}

# =============================================================================
# FLINK OUTPUTS
# =============================================================================

output "flink_role_arn" {
  description = "ARN of the Flink IAM role. Used when granting cross-account permissions."
  value       = aws_iam_role.flink_role.arn
}

output "flink_role_name" {
  description = "Name of the Flink IAM role."
  value       = aws_iam_role.flink_role.name
}

output "flink_application_name" {
  description = "Name of the Flink commit worker application."
  value       = aws_kinesisanalyticsv2_application.flink_iceberg_commit_worker.name
}

output "flink_application_arn" {
  description = "ARN of the Flink commit worker application."
  value       = aws_kinesisanalyticsv2_application.flink_iceberg_commit_worker.arn
}

output "sqs_queue_url" {
  description = "URL of the SQS queue for Iceberg file events."
  value       = aws_sqs_queue.iceberg_file_events.url
}

output "sqs_queue_arn" {
  description = "ARN of the SQS queue for Iceberg file events."
  value       = aws_sqs_queue.iceberg_file_events.arn
}

output "sqs_dlq_arn" {
  description = "ARN of the SQS dead-letter queue."
  value       = aws_sqs_queue.iceberg_file_events_dlq.arn
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for Flink."
  value       = aws_cloudwatch_log_group.flink_log_group.name
}
