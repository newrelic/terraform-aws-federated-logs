locals {
  flink_jar_filename  = "flink-iceberg-commit-worker-${var.flink_iceberg_commit_worker_version}.jar"
  flink_jar_s3_source = "/nr-downloads-main/pipeline-control-gateway/fed-logs/${local.flink_jar_filename}"
  flink_jar_s3_key    = "jars/${local.flink_jar_filename}"
}

# Copy the versioned Flink JAR from nr-downloads-main into the deployment bucket.
resource "aws_s3_object_copy" "flink_jar" {
  bucket       = var.flink_jar_bucket
  key          = local.flink_jar_s3_key
  source       = local.flink_jar_s3_source
  content_type = "application/java-archive"

  metadata = {
    "source-bucket" = "nr-downloads-main"
    "uploaded-by"   = "terraform"
  }

  metadata_directive = "REPLACE"
}

output "flink_jar_s3_uri" {
  description = "S3 URI of the uploaded flink-iceberg-commit-worker JAR."
  value       = "s3://${var.flink_jar_bucket}/${local.flink_jar_s3_key}"
}
