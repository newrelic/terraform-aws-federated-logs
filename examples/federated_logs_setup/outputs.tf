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

output "validation_summary" {
  description = "Post-deploy validation status"
  value       = module.federated_logs.validation_summary
}
