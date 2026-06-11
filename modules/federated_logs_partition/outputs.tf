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

output "glue_optimizer_failures_alarm_arns" {
  description = "Map of optimizer type (compaction, retention, orphan_deletion) → ARN of the CloudWatch alarm that fires on that optimizer's failures in this setup. Wire these to an SNS topic or downstream system for notification."
  value       = { for k, v in aws_cloudwatch_metric_alarm.glue_optimizer_failures : k => v.arn }
}

output "glue_optimizer_failures_alarm_names" {
  description = "Map of optimizer type (compaction, retention, orphan_deletion) → name of the CloudWatch alarm that fires on that optimizer's failures in this setup."
  value       = { for k, v in aws_cloudwatch_metric_alarm.glue_optimizer_failures : k => v.alarm_name }
}

output "partition_ids" {
  description = "Map of non-default partition table name → entity GUID of the corresponding newrelic_federated_logs_partition."
  value = {
    for k, v in newrelic_federated_logs_partition.this : k => v.id
  }
}