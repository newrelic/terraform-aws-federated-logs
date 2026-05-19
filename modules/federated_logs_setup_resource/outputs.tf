output "s3_bucket_name" {
  description = "Name of the S3 bucket"
  value       = aws_s3_bucket.this.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.this.arn
}

output "glue_catalog_db_name" {
  description = "Name of the Glue catalog database"
  value       = aws_glue_catalog_database.this.name
}

output "glue_catalog_db_arn" {
  description = "ARN of the Glue catalog database"
  value       = aws_glue_catalog_database.this.arn
}

output "setup_name" {
  description = "Name of the federated logs setup, used in resource naming"
  value       = var.setup_name
}

output "eventbridge_rule_arn" {
  description = "ARN of the per-setup EventBridge rule that filters .parquet file-creation events for this bucket."
  value       = aws_cloudwatch_event_rule.iceberg_file_events.arn
}