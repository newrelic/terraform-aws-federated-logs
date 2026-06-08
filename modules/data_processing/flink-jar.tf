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

# HEAD the source JAR to get its ETag for change detection.
data "http" "flink_jar_metadata" {
  url    = local.flink_jar_source_url
  method = "HEAD"

  retry {
    attempts     = 3
    min_delay_ms = 1000
    max_delay_ms = 5000
  }

  lifecycle {
    postcondition {
      condition     = !contains([401, 403], self.status_code)
      error_message = "Access denied to ${local.flink_jar_source_url} (HTTP ${self.status_code}). Ensure the Terraform runner has outbound HTTPS access to S3 and is not blocked by a VPC endpoint policy."
    }
    postcondition {
      condition     = self.status_code != 404
      error_message = "JAR not found at ${local.flink_jar_source_url} (HTTP 404). Verify that version '${var.flink_iceberg_commit_worker_version}' exists in the nr-downloads-main bucket."
    }
    postcondition {
      condition     = contains([200, 401, 403, 404], self.status_code)
      error_message = "Unexpected error fetching JAR metadata from ${local.flink_jar_source_url} (HTTP ${self.status_code})."
    }
  }
}

# Download the JAR from the public HTTPS endpoint into the module's .terraform/tmp dir;
# bypasses the VPC gateway endpoint that blocks cross-region S3 calls.
# Python keeps this OS-agnostic (macOS / Linux / Windows / CI).
resource "null_resource" "flink_jar_fetch" {
  triggers = {
    url  = local.flink_jar_source_url
    etag = data.http.flink_jar_metadata.response_headers["Etag"]
  }

  provisioner "local-exec" {
    interpreter = ["python3", "-c"]
    environment = {
      FLINK_JAR_URL  = local.flink_jar_source_url
      FLINK_JAR_DEST = local.flink_jar_local_path
    }
    command = <<-PY
      import os, pathlib, urllib.request, urllib.error, socket, time, sys
      MAX_NO_RETRY = 3
      RETRY_DELAY_SECONDS = 5
      SOCKET_TIMEOUT_SECONDS = 60
      dest = pathlib.Path(os.environ["FLINK_JAR_DEST"])
      dest.parent.mkdir(parents=True, exist_ok=True)
      url = os.environ["FLINK_JAR_URL"]
      socket.setdefaulttimeout(SOCKET_TIMEOUT_SECONDS)
      for attempt in range(MAX_NO_RETRY):
          try:
              urllib.request.urlretrieve(url, dest)
              if not dest.exists():
                  raise RuntimeError("Downloaded file does not exist")
              if dest.stat().st_size > 0:
                  sys.exit(0)
              raise RuntimeError("Downloaded file is empty")
          except urllib.error.HTTPError as e:
              if e.code < 500:
                  sys.exit(f"ERROR: {url} returned HTTP {e.code} (not retryable)")
              if attempt < MAX_NO_RETRY - 1:
                  time.sleep(RETRY_DELAY_SECONDS)
              else:
                  sys.exit(f"ERROR: Failed to download {url} after {MAX_NO_RETRY} attempts: HTTP {e.code}")
          except urllib.error.URLError as e:
              if attempt < MAX_NO_RETRY - 1:
                  time.sleep(RETRY_DELAY_SECONDS)
              else:
                  sys.exit(f"ERROR: Failed to download {url} after {MAX_NO_RETRY} attempts: {e.reason}")
          except Exception as e:
              if attempt < MAX_NO_RETRY - 1:
                  time.sleep(RETRY_DELAY_SECONDS)
              else:
                  sys.exit(f"ERROR: Failed to download {url} after {MAX_NO_RETRY} attempts: {e}")
    PY
  }

  depends_on = [aws_s3_bucket.flink_jar]
}

# Upload to the customer bucket — same destination as the prior aws_s3_object_copy.
resource "aws_s3_object" "flink_jar" {
  bucket = aws_s3_bucket.flink_jar.id
  key    = local.flink_jar_dest_key
  source = local.flink_jar_local_path
  etag   = data.http.flink_jar_metadata.response_headers["Etag"]

  depends_on = [
    null_resource.flink_jar_fetch,
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
