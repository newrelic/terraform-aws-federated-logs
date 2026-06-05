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

# Copy JAR from New Relic's public bucket to customer's bucket via HTTPS download + S3 upload.
# Uses Python script with AWS Signature V4 (stdlib only - no boto3/AWS CLI required).
# This approach bypasses VPC endpoint cross-region restrictions that break aws_s3_object_copy.
resource "null_resource" "flink_jar_copy" {
  triggers = {
    source_url  = local.flink_jar_source_url
    dest_bucket = aws_s3_bucket.flink_jar.id
    dest_key    = local.flink_jar_dest_key
    version     = var.flink_iceberg_commit_worker_version
  }

  provisioner "local-exec" {
    command = "python3 ${path.module}/scripts/copy_flink_jar.py"

    environment = {
      SOURCE_URL   = local.flink_jar_source_url
      DEST_BUCKET  = aws_s3_bucket.flink_jar.id
      DEST_KEY     = local.flink_jar_dest_key
      DEST_REGION  = data.aws_region.current.name
      CONTENT_TYPE = "application/java-archive"
    }
  }

  depends_on = [
    aws_s3_bucket_versioning.flink_jar,
    aws_s3_bucket_server_side_encryption_configuration.flink_jar,
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
