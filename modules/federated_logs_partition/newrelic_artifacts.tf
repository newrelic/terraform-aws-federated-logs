# Bucket for non-table-data artifacts: the Glue job scripts
# (retention.tf, tagging.tf) and the schema registry's objects
# (schema_registry.tf). Unconditional on purpose: the schema registry
# depends on neither retention nor tagging.
resource "aws_s3_bucket" "newrelic_artifacts" {
  bucket = "newrelic-fed-logs-${var.setup_name}-artifacts"
  region = data.aws_region.current.region
}

# Bucket policy grants the Glue service role read access to the job
# scripts, so it exists only while a Glue job does.
resource "aws_s3_bucket_policy" "newrelic_artifacts" {
  count  = local.is_any_glue_job_enabled ? 1 : 0
  bucket = aws_s3_bucket.newrelic_artifacts.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowGlueServiceRoleRead"
      Effect = "Allow"
      Principal = {
        AWS = var.glue_service_role_arn
      }
      Action = ["s3:GetObject", "s3:ListBucket"]
      Resource = [
        "arn:aws:s3:::${aws_s3_bucket.newrelic_artifacts.bucket}",
        "arn:aws:s3:::${aws_s3_bucket.newrelic_artifacts.bucket}/*",
      ]
    }]
  })
}
