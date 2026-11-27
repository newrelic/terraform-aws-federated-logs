# =============================================================================
# S3 → EVENTBRIDGE NOTIFICATION
# =============================================================================

data "aws_caller_identity" "current" {}

locals {
  # The 5th colon-segment of any SQS ARN is the account ID hosting the queue
  # (arn:aws:sqs:<region>:<account-id>:<queue-name>). The notifications module
  # already receives this ARN via var.sqs_queue_arn (sourced from the NGEP
  # entity tagged by data_processing), so cross-account topology can be
  # inferred without asking the customer to declare it.
  target_account_id = split(":", var.sqs_queue_arn)[4]

  # Cross-account delivery is needed when the target SQS queue lives in a
  # different account from the EventBridge rule. AWS requires a role_arn on
  # the target in that case; same-account targets can rely solely on the
  # queue's resource policy.
  cross_account_delivery = local.target_account_id != data.aws_caller_identity.current.account_id
}

# Enable EventBridge notifications on the bucket
# All S3 events are forwarded to the default event bus — the rule below filters them
resource "aws_s3_bucket_notification" "this" {
  bucket      = var.s3_bucket_id
  eventbridge = true
}

# IAM role assumed by EventBridge to deliver events to a cross-account SQS queue.
# Created only when target_account_id is set and differs from the current account.
resource "aws_iam_role" "eventbridge_to_sqs" {
  count = local.cross_account_delivery ? 1 : 0

  name = "newrelic-fed-logs-${var.setup_name}-eb-to-sqs"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "eventbridge_to_sqs" {
  count = local.cross_account_delivery ? 1 : 0

  name = "send-to-cross-account-sqs"
  role = aws_iam_role.eventbridge_to_sqs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "sqs:SendMessage"
        Resource = var.sqs_queue_arn
      }
    ]
  })
}

# EventBridge rule — matches PCG-written parquet file creation events in this bucket
# Filters by:
#   bucket name → only this bucket
#   key         → suffix "pcg-df.parquet" (PCG's current file-naming convention,
#                 <uuid>.pcg-df.parquet — see pipeline-control-gateway#634).
#                 `suffix` filters are NOT subject to the 30-rules-per-bus
#                 wildcard quota (non-adjustable), unlike the `wildcard` filter
#                 this replaced — that's the entire reason for this rule shape.
#                 Requires every setup's PCG image to be on a build that writes
#                 the .pcg-df.parquet suffix; a setup still writing the legacy
#                 pcg-00000-<uuid>.parquet prefix form will silently stop
#                 triggering this rule. Confirm the PCG image is upgraded
#                 fleet-wide before applying this to an existing setup.
#   reason      → PutObject or CompleteMultipartUpload (large files >5MB use multipart)
resource "aws_cloudwatch_event_rule" "iceberg_file_events" {
  name        = "newrelic-fed-logs-${var.setup_name}-iceberg-file-created"
  description = "Fires when a PCG-written .parquet file is created in ${var.s3_bucket_id}"

  event_pattern = jsonencode({
    source        = ["aws.s3"]
    "detail-type" = ["Object Created"]
    detail = {
      bucket = {
        name = [var.s3_bucket_id]
      }
      object = {
        key = [{ suffix = "pcg-df.parquet" }]
      }
      reason = ["PutObject", "CompleteMultipartUpload"]
    }
  })
}

# EventBridge target — route matched events to the fleet-level SQS queue.
# The input_transformer preserves the native EventBridge envelope shape and
# injects roleArn / setupId / setupName under "detail" so the Flink commit
# worker can AssumeRole without an S3 HeadObject round-trip per file event.
# setupId is the entity GUID (unique); setupName is the human-readable name.
resource "aws_cloudwatch_event_target" "iceberg_file_events_sqs" {
  rule      = aws_cloudwatch_event_rule.iceberg_file_events.name
  target_id = "sqs-target"
  arn       = var.sqs_queue_arn

  # role_arn is REQUIRED by EventBridge when the target lives in another
  # account. With it set, EventBridge calls SQS as the assumed role's
  # session (in this account) — the target queue's policy must therefore
  # trust this account, not the events.amazonaws.com service principal.
  role_arn = local.cross_account_delivery ? aws_iam_role.eventbridge_to_sqs[0].arn : null

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
          "setupId": "${var.setup_id}",
          "setupName": "${var.setup_name}"
        }
      }
    EOT
  }
}
