output "s3_bucket_name" {
  description = "Name of the S3 bucket storing federated logs"
  value       = module.federated_logs.s3_bucket_name
}

output "glue_database_name" {
  description = "Name of the Glue catalog database"
  value       = module.federated_logs.glue_database_name
}

output "glue_service_role_arn" {
  description = "ARN of the IAM role used by Glue for table maintenance"
  value       = module.federated_logs.glue_service_role_arn
}

output "pcg_writer_role_arn" {
  description = "ARN of the IAM role for PCG to write federated logs"
  value       = module.federated_logs.pcg_writer_role_arn
}

output "nr_reader_role_arn" {
  description = "ARN of the IAM role for New Relic to query federated logs"
  value       = module.federated_logs.nr_reader_role_arn
}

output "iceberg_tables" {
  description = "Map of created Iceberg table names and ARNs"
  value       = module.federated_logs.iceberg_tables
}

output "e2e_validation_status" {
  description = "Parsed PASS/FAIL status of the most recent e2e Lambda invocation. null when e2e_validation_config.enabled = false."
  value       = module.federated_logs.e2e_validation_status
}

output "e2e_validation_result" {
  description = "JSON result (status, exit_code, stdout, stderr) of the most recent e2e Lambda invocation. null when e2e_validation_config.enabled = false."
  value       = module.federated_logs.e2e_validation_result
}
