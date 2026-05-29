# =============================================================================
# S3 → EVENTBRIDGE NOTIFICATION
# =============================================================================

# Enable EventBridge notifications on the bucket
# All S3 events are forwarded to the default event bus — the rule below filters them
resource "aws_s3_bucket_notification" "this" {
  bucket      = var.s3_bucket_id
  eventbridge = true
}

# EventBridge rule — matches pcg parquet file creation events in this bucket
# Filters by:
#   bucket name  → only this bucket
#   key wildcard → only files matching *pcg-*.parquet
#   reason       → PutObject or CompleteMultipartUpload (large files >5MB use multipart)
resource "aws_cloudwatch_event_rule" "iceberg_file_events" {
  name        = "${var.setup_name}-iceberg-file-created"
  description = "Fires when a .parquet file is created in ${var.s3_bucket_id}"

  event_pattern = jsonencode({
    source        = ["aws.s3"]
    "detail-type" = ["Object Created"]
    detail = {
      bucket = {
        name = [var.s3_bucket_id]
      }
      object = {
        key = [{ wildcard = "*pcg-*.parquet" }]
      }
      reason = ["PutObject", "CompleteMultipartUpload"]
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
          "roleArn": "${var.pcg_writer_role_arn}",
          "setupId": "${var.setup_name}"
        }
      }
    EOT
  }
}
