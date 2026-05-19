data "aws_region" "current" {
  region = var.region
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "this" {
  bucket = local.setup_naming_prefix
  region = data.aws_region.current.id
}

resource "aws_glue_catalog_database" "this" {
  name        = lower(replace(local.setup_naming_prefix, "-", "_"))
  description = "Glue database containing NR resources for federated logs"
  region      = data.aws_region.current.id
}

# =============================================================================
# S3 → EVENTBRIDGE NOTIFICATION
# =============================================================================

# Enable EventBridge notifications on the bucket
# All S3 events are forwarded to the default event bus — the rule below filters them
resource "aws_s3_bucket_notification" "this" {
  bucket      = aws_s3_bucket.this.id
  eventbridge = true
}

# EventBridge rule — matches pcg parquet file creation events in this bucket
# Filters by:
#   bucket name  → only this bucket
#   key wildcard → only files matching *pcg-*.parquet
#   reason       → PutObject only (excludes CompleteMultipartUpload, CopyObject)
resource "aws_cloudwatch_event_rule" "iceberg_file_events" {
  name        = "${local.setup_naming_prefix}-iceberg-file-created"
  description = "Fires when a .parquet file is created in ${local.setup_naming_prefix}"

  event_pattern = jsonencode({
    source        = ["aws.s3"]
    "detail-type" = ["Object Created"]
    detail = {
      bucket = {
        name = [aws_s3_bucket.this.id]
      }
      object = {
        key = [{ wildcard = "*pcg-*.parquet" }]
      }
      reason = ["PutObject"]
    }
  })
}

# EventBridge target — route matched events to the fleet-level SQS queue.
# The input_transformer preserves the native EventBridge envelope shape and
# injects roleArn / setupId under "detail" so the Flink commit worker can
# AssumeRole without an S3 HeadObject round-trip per file event.
resource "aws_cloudwatch_event_target" "iceberg_file_events_sqs" {
  rule      = aws_cloudwatch_event_rule.iceberg_file_events.name
  target_id = "sqs-target"
  arn       = var.sqs_queue_arn

  input_transformer {
    input_paths = {
      id         = "$.id"
      detailtype = "$.detail-type"
      source     = "$.source"
      account    = "$.account"
      time       = "$.time"
      region     = "$.region"
      resources  = "$.resources"
      bucket     = "$.detail.bucket.name"
      key        = "$.detail.object.key"
      size       = "$.detail.object.size"
      etag       = "$.detail.object.etag"
      reason     = "$.detail.reason"
    }

    input_template = <<-EOT
      {
        "version": "0",
        "id": <id>,
        "detail-type": <detailtype>,
        "source": <source>,
        "account": <account>,
        "time": <time>,
        "region": <region>,
        "resources": <resources>,
        "detail": {
          "version": "0",
          "bucket": { "name": <bucket> },
          "object": { "key": <key>, "size": <size>, "etag": <etag> },
          "reason": <reason>,
          "roleArn": "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.setup_naming_prefix}-pcg-writer",
          "setupId": "${var.setup_name}"
        }
      }
    EOT
  }
}