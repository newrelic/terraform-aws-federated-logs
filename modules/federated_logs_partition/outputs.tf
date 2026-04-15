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
  value       = local.has_retention_enabled ? aws_glue_job.retention[0].name : null
}

output "retention_period" {
  description = "Data retention period applied to all tables (null if disabled)"
  value       = var.retention_period
}