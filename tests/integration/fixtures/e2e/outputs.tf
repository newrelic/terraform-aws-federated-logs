# ---- AWS resources that are preserved with `prevent_destroy` and need explicit cleanup ----

output "s3_bucket_name" {
  description = "Name of the per-setup S3 bucket. Lifecycle-protected."
  value       = module.setup.s3_bucket_name
}

output "glue_catalog_db_name" {
  description = "Name of the per-setup Glue catalog database. Lifecycle-protected."
  value       = module.setup.glue_catalog_db_name
}

# ---- New Relic entity GUIDs for ID-targeted entityDelete calls ----------------

output "aws_connection_id" {
  description = "Entity GUID of the AWS Connection."
  value       = module.data_processing.fleet_ingest_connection_id
}

output "setup_id" {
  description = "Entity GUID of the newrelic_federated_logs_setup."
  value       = module.role.setup_id
}

output "default_partition_id" {
  description = "Entity GUID of the default Log_Federated partition."
  value       = module.role.default_partition_id
}

output "custom_partition_ids" {
  description = "Map of custom partition table name → entity GUID for the partitions."
  value       = module.partition.partition_ids
}

# ---- Useful for assertions inside the Go test --------------------------------

output "all_tables" {
  description = "Map of all partition tables (default + custom)."
  value       = module.partition.all_tables
}

output "glue_service_role_arn" {
  description = "ARN of the Glue service role."
  value       = module.role.glue_service_role_arn
}
