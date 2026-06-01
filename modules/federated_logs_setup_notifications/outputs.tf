output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule for Iceberg file events."
  value       = aws_cloudwatch_event_rule.iceberg_file_events.arn
}

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule for Iceberg file events."
  value       = aws_cloudwatch_event_rule.iceberg_file_events.name
}
