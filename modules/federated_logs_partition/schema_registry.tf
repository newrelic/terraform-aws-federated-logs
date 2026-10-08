# The code-artifacts bucket also serves the PCG schema registry: the gateway
# writes one small JSON object per newly-seen column under the
# newrelic-fed-logs-schemas/ prefix. Those objects are only useful until the
# Glue catalog itself learns the column, so they expire after 1 day.
#
# The prefix filter is load-bearing: this bucket also holds the retention
# job's script (scripts/retention_job.py) and may hold more scripts later.
# A rule without this filter would expire those too.
#
# IMPORTANT: "newrelic-fed-logs-schemas/" must match the default
# SchemaRegistryConfig.Prefix in pipeline-control-gateway
# (exporter/icebergexporter/config.go). Nothing keeps the two in sync
# automatically -- if the gateway's prefix changes, change this filter too.
resource "aws_s3_bucket_lifecycle_configuration" "schema_registry_entries" {
  bucket = aws_s3_bucket.retention_scripts.id

  rule {
    id     = "expire-schema-registry-entries"
    status = "Enabled"

    filter {
      prefix = "newrelic-fed-logs-schemas/"
    }

    expiration {
      days = 1
    }
  }
}
