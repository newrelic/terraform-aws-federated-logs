output "s3_bucket_name" {
  description = "Name of the S3 bucket storing federated logs"
  value       = module.setup.s3_bucket_name
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket storing federated logs"
  value       = module.setup.s3_bucket_arn
}

output "glue_database_name" {
  description = "Name of the Glue catalog database"
  value       = module.setup.glue_catalog_db_name
}

output "glue_service_role_arn" {
  description = "ARN of the IAM role used by Glue for table maintenance"
  value       = module.role.glue_service_role_arn
}

output "pcg_writer_role_arn" {
  description = "ARN of the IAM role for PCG to write federated logs"
  value       = module.role.pcg_writer_role_arn
}

output "nr_reader_role_arn" {
  description = "ARN of the IAM role for New Relic to query federated logs"
  value       = module.role.nr_reader_role_arn
}

output "iceberg_tables" {
  description = "Map of created Iceberg table names and their configurations"
  value       = module.partition.all_tables
}
