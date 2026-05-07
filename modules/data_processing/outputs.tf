output "flink_application_name" {
  description = "Name of the Flink commit worker application"
  value       = aws_kinesisanalyticsv2_application.flink_iceberg_commit_worker.name
}

output "flink_application_arn" {
  description = "ARN of the Flink commit worker application"
  value       = aws_kinesisanalyticsv2_application.flink_iceberg_commit_worker.arn
}

output "sqs_queue_url" {
  description = "URL of the SQS queue for Iceberg file events"
  value       = aws_sqs_queue.iceberg_file_events.url
}

output "sqs_queue_arn" {
  description = "ARN of the SQS queue for Iceberg file events"
  value       = aws_sqs_queue.iceberg_file_events.arn
}

output "sqs_dlq_arn" {
  description = "ARN of the SQS dead-letter queue"
  value       = aws_sqs_queue.iceberg_file_events_dlq.arn
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for Flink"
  value       = aws_cloudwatch_log_group.flink_log_group.name
}
