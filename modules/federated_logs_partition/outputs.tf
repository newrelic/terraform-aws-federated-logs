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

output "partition_ids" {
  description = "Map of non-default partition table name → entity GUID of the corresponding newrelic_federated_logs_partition."
  value = {
    for k, v in newrelic_federated_logs_partition.this : k => v.id
  }
}