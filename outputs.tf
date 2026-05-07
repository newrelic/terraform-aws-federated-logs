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

output "flink_application_name" {
  description = "Name of the Flink commit worker application"
  value       = module.data_processing.flink_application_name
}

output "flink_application_arn" {
  description = "ARN of the Flink commit worker application"
  value       = module.data_processing.flink_application_arn
}

output "flink_role_arn" {
  description = "ARN of the IAM role used by Flink commit worker"
  value       = module.data_processing_role.flink_role_arn
}

output "sqs_queue_url" {
  description = "URL of the SQS queue for Iceberg file events"
  value       = module.data_processing.sqs_queue_url
}

output "sqs_queue_arn" {
  description = "ARN of the SQS queue for Iceberg file events"
  value       = module.data_processing.sqs_queue_arn
}
