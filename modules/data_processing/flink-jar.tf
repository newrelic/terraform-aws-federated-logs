# Source: New Relic's public bucket where the Flink JAR is published
# Destination: Customer's bucket where the JAR will be copied for Flink to access

locals {
  flink_jar_source_bucket = "nr-downloads-main"
  flink_jar_filename      = "flink-iceberg-commit-worker-${var.flink_iceberg_commit_worker_version}.jar"
  flink_jar_source_key    = "pipeline-control-gateway/fed-logs/${local.flink_jar_filename}"
  flink_jar_dest_key      = "flink/${local.flink_jar_filename}"
}

# Copy JAR from New Relic's bucket to customer's bucket
resource "aws_s3_object_copy" "flink_jar" {
  bucket = var.flink_jar_bucket
  key    = local.flink_jar_dest_key
  source = "/${local.flink_jar_source_bucket}/${local.flink_jar_source_key}"
}

output "flink_jar_s3_uri" {
  description = "S3 URI of the flink-iceberg-commit-worker JAR in the customer's deployment bucket."
  value       = "s3://${var.flink_jar_bucket}/${local.flink_jar_dest_key}"
}
