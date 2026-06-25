output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule for Iceberg file events."
  value       = aws_cloudwatch_event_rule.iceberg_file_events.arn
}

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule for Iceberg file events."
  value       = aws_cloudwatch_event_rule.iceberg_file_events.name
}

output "eventbridge_role_arn" {
  description = "ARN of the IAM role EventBridge assumes to deliver events to a cross-account SQS queue. Null for same-account deployments."
  value       = local.cross_account_delivery ? aws_iam_role.eventbridge_to_sqs[0].arn : null
}
