# Source: New Relic's public bucket where the Flink JAR is published
# Destination: Auto-created bucket in customer's account for Flink JAR storage

locals {
  flink_jar_source_bucket = "nr-downloads-main"
  flink_jar_filename      = "flink-iceberg-commit-worker-${var.flink_iceberg_commit_worker_version}.jar"
  flink_jar_source_key    = "pipeline-control-gateway/fed-logs/${local.flink_jar_filename}"
  flink_jar_dest_key      = "flink/${local.flink_jar_filename}"
}

# Create S3 bucket for Flink JAR storage in customer's account
resource "aws_s3_bucket" "flink_jar" {
  bucket = "${local.naming_prefix}-flink-jar"

  tags = merge(var.tags, {
    Name = "${local.naming_prefix}-flink-jar"
  })
}

# Enable versioning for the Flink JAR bucket
resource "aws_s3_bucket_versioning" "flink_jar" {
  bucket = aws_s3_bucket.flink_jar.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Enable server-side encryption for the Flink JAR bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "flink_jar" {
  bucket = aws_s3_bucket.flink_jar.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block public access to the Flink JAR bucket
resource "aws_s3_bucket_public_access_block" "flink_jar" {
  bucket = aws_s3_bucket.flink_jar.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Copy JAR from New Relic's bucket to customer's bucket
resource "aws_s3_object_copy" "flink_jar" {
  bucket = aws_s3_bucket.flink_jar.id
  key    = local.flink_jar_dest_key
  source = "/${local.flink_jar_source_bucket}/${local.flink_jar_source_key}"

  depends_on = [
    aws_s3_bucket_versioning.flink_jar,
    aws_s3_bucket_server_side_encryption_configuration.flink_jar,
    aws_s3_bucket_public_access_block.flink_jar,
  ]
}

output "flink_jar_bucket_name" {
  description = "Name of the S3 bucket created for Flink JAR storage."
  value       = aws_s3_bucket.flink_jar.id
}

output "flink_jar_bucket_arn" {
  description = "ARN of the S3 bucket created for Flink JAR storage."
  value       = aws_s3_bucket.flink_jar.arn
}

output "flink_jar_s3_uri" {
  description = "S3 URI of the flink-iceberg-commit-worker JAR in the deployment bucket."
  value       = "s3://${aws_s3_bucket.flink_jar.id}/${local.flink_jar_dest_key}"
}
