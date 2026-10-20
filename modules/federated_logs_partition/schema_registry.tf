# The code-artifacts bucket also serves the PCG schema registry: the gateway
# writes one small JSON object per newly-seen column under the
# newrelic-fed-logs-schemas/ prefix. Those objects are only useful until the
# Glue catalog itself learns the column, so they expire after 1 day.
#
# The prefix filter is load-bearing: this bucket also holds the retention
# job's script (scripts/retention_job.py) and may hold more scripts later.
# A rule without this filter would expire those too.
#
# IMPORTANT: local.schema_registry_prefix must match the default
# SchemaRegistryConfig.Prefix in pipeline-control-gateway
# (exporter/icebergexporter/config.go). Nothing keeps the two in sync
# automatically -- if the gateway's prefix changes, change this filter too.
locals {
  schema_registry_prefix = "newrelic-fed-logs-schemas"
}

resource "aws_s3_bucket_lifecycle_configuration" "schema_registry_entries" {
  bucket = aws_s3_bucket.code_artifacts.id

  rule {
    id     = "expire-schema-registry-entries"
    status = "Enabled"

    filter {
      prefix = "${local.schema_registry_prefix}/"
    }

    expiration {
      days = 1
    }
  }
}

# Grants the PCG writer role access to the schema registry's objects.
resource "aws_iam_role_policy" "pcg_writer_schema_registry_access" {
  name = "schema-registry-access"
  role = var.pcg_writer_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Objects are limited to the registry prefix: the same bucket holds the
        # Glue job scripts, which run as the Glue service role.
        Sid      = "SchemaRegistryObjects"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject"]
        Resource = "arn:aws:s3:::${aws_s3_bucket.code_artifacts.bucket}/${local.schema_registry_prefix}/*"
      },
      {
        # No s3:prefix condition on ListBucket: the registry relies on GetObject
        # returning 404 (not 403) for missing keys, which requires an
        # unconditioned ListBucket grant.
        Sid      = "SchemaRegistryBucket"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = "arn:aws:s3:::${aws_s3_bucket.code_artifacts.bucket}"
      }
    ]
  })
}
