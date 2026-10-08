output "all_tables" {
  description = "Map of all tables with their details"
  value = {
    for k, v in aws_glue_catalog_table.iceberg_table : k => {
      name = v.name
      arn  = v.arn
    }
  }
}

output "all_table_ids" {
  description = "Map of tableId (database.table) to partition display name (e.g. Log_Federated) for seeding the dashboard variable dropdown."
  value = merge(
    {
      for k in [substr(replace(lower("${local.setup_naming_prefix}_${local.default_partition_name}"), "/[^a-z0-9_]/", "_"), 0, local.max_table_name_length)] :
      "${var.glue_catalog_db_name}.${k}" => local.default_partition_name
    },
    {
      for sanitized_name, raw_name in local.nr_partition_names :
      "${var.glue_catalog_db_name}.${sanitized_name}" => raw_name
    }
  )
}

output "retention_job_name" {
  description = "Name of the Glue retention job (if enabled)"
  value       = local.is_data_retention_enabled ? aws_glue_job.retention[0].name : null
}

output "code_artifacts_bucket_name" {
  description = "Name of the S3 bucket holding Glue ETL scripts and other code artifacts (including the PCG schema registry's objects). Always available -- not gated on data_retention_enabled."
  value       = aws_s3_bucket.retention_scripts.bucket
}

output "schema_registry_prefix" {
  description = "Key prefix (no trailing slash) under which the PCG schema registry writes objects in the code-artifacts bucket. Scopes both the 1-day lifecycle rule and the PCG writer grant."
  value       = local.schema_registry_prefix
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