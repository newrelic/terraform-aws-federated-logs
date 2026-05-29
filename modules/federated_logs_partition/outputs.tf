output "all_tables" {
  description = "Map of all tables with their details"
  value = {
    for k, v in aws_glue_catalog_table.iceberg_table : k => {
      name = v.name
      arn  = v.arn
    }
  }
}

output "retention_job_name" {
  description = "Name of the Glue retention job (if enabled)"
  value       = local.is_data_retention_enabled ? aws_glue_job.retention[0].name : null
}

output "glue_optimizer_failures_alarm_arn" {
  description = "ARN of the CloudWatch alarm that fires on any Glue Iceberg optimizer failure in this setup. Wire this to an SNS topic or downstream system for notification."
  value       = aws_cloudwatch_metric_alarm.glue_optimizer_failures.arn
}

output "glue_optimizer_failures_alarm_name" {
  description = "Name of the CloudWatch alarm that fires on any Glue Iceberg optimizer failure in this setup."
  value       = aws_cloudwatch_metric_alarm.glue_optimizer_failures.alarm_name
}