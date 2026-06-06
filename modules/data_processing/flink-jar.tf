# Source: New Relic's public bucket where the Flink JAR is published
# Destination: Auto-created bucket in customer's account for Flink JAR storage

locals {
  flink_jar_source_bucket = "nr-downloads-main"
  flink_jar_filename      = "flink-iceberg-commit-worker-${var.flink_iceberg_commit_worker_version}.jar"
  flink_jar_source_key    = "pipeline-control-gateway/fed-logs/${local.flink_jar_filename}"
  flink_jar_dest_key      = "flink/${local.flink_jar_filename}"

  # Public HTTPS endpoint bypasses the VPC gateway endpoint that blocks cross-region S3 calls.
  flink_jar_source_url = "https://${local.flink_jar_source_bucket}.s3.amazonaws.com/${local.flink_jar_source_key}"
  flink_jar_local_path = "${path.module}/.terraform/tmp/${local.flink_jar_filename}"
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

# Download the JAR from the public HTTPS endpoint into the module's .terraform/tmp dir;
# bypasses the VPC gateway endpoint that blocks cross-region S3 calls.
# Python keeps this OS-agnostic (macOS / Linux / Windows / CI).
resource "null_resource" "flink_jar_fetch" {
  triggers = {
    url = local.flink_jar_source_url
  }

  provisioner "local-exec" {
    interpreter = ["python3", "-c"]
    command     = <<-PY
      import pathlib, urllib.request
      dest = pathlib.Path("${local.flink_jar_local_path}")
      dest.parent.mkdir(parents=True, exist_ok=True)
      urllib.request.urlretrieve("${local.flink_jar_source_url}", dest)
    PY
  }

  depends_on = [aws_s3_bucket.flink_jar]
}

# Upload to the customer bucket — same destination as the prior aws_s3_object_copy.
resource "aws_s3_object" "flink_jar" {
  bucket = aws_s3_bucket.flink_jar.id
  key    = local.flink_jar_dest_key
  source = local.flink_jar_local_path

  depends_on = [
    null_resource.flink_jar_fetch,
    aws_s3_bucket_versioning.flink_jar,
    aws_s3_bucket_server_side_encryption_configuration.flink_jar,
    aws_s3_bucket_public_access_block.flink_jar,
  ]
}

# Delete the local JAR after it has been uploaded successfully.
# Triggers on etag, so it re-runs every time the upload changes.
resource "null_resource" "flink_jar_cleanup" {
  triggers = {
    etag = aws_s3_object.flink_jar.etag
  }

  provisioner "local-exec" {
    interpreter = ["python3", "-c"]
    command     = <<-PY
      import pathlib
      pathlib.Path("${local.flink_jar_local_path}").unlink(missing_ok=True)
    PY
  }
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
