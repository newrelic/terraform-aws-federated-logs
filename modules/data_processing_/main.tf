data "aws_region" "current" {}

# =============================================================================
# SQS QUEUES
# =============================================================================

# Dead Letter Queue (DLQ) - must be created first
resource "aws_sqs_queue" "iceberg_file_events_dlq" {
  name = "${local.setup_naming_prefix}-file-events-dlq"

  # Message settings
  visibility_timeout_seconds = 30
  message_retention_seconds  = var.sqs_message_retention
  max_message_size           = 262144 # 256 KB
  delay_seconds              = 0
  receive_wait_time_seconds  = 0 # Short polling for DLQ

  # Encryption - SQS managed SSE
  sqs_managed_sse_enabled = true

  tags = merge(var.tags, {
    Name = "${local.setup_naming_prefix}-file-events-dlq"
  })
}

# Main queue for Iceberg file events
resource "aws_sqs_queue" "iceberg_file_events" {
  name = "${local.setup_naming_prefix}-file-events"

  # Message settings
  visibility_timeout_seconds = var.sqs_visibility_timeout
  message_retention_seconds  = var.sqs_message_retention
  max_message_size           = 262144 # 256 KB
  delay_seconds              = 0
  receive_wait_time_seconds  = 20 # Long polling (reduces API calls & cost)

  # Encryption - SQS managed SSE
  sqs_managed_sse_enabled = true

  # Dead-letter queue configuration
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.iceberg_file_events_dlq.arn
    maxReceiveCount     = var.sqs_max_receive_count
  })

  tags = merge(var.tags, {
    Name = "${local.setup_naming_prefix}-file-events"
  })
}

# =============================================================================
# SQS QUEUE POLICY - Allow S3 to send messages
# =============================================================================

resource "aws_sqs_queue_policy" "iceberg_file_events_policy" {
  queue_url = aws_sqs_queue.iceberg_file_events.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowS3ToSendMessage"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.iceberg_file_events.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = "arn:aws:s3:::${var.s3_bucket_name}"
          }
        }
      }
    ]
  })
}

# =============================================================================
# Redrive allow policy - allows main queue to use DLQ
# =============================================================================

resource "aws_sqs_queue_redrive_allow_policy" "iceberg_dlq_allow" {
  queue_url = aws_sqs_queue.iceberg_file_events_dlq.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.iceberg_file_events.arn]
  })
}

# =============================================================================
# S3 EVENT NOTIFICATION - Send .parquet file events to SQS
# =============================================================================

resource "aws_s3_bucket_notification" "iceberg_file_events" {
  bucket = var.s3_bucket_name

  queue {
    queue_arn     = aws_sqs_queue.iceberg_file_events.arn
    events        = ["s3:ObjectCreated:*"]
    filter_suffix = ".parquet"
  }

  depends_on = [aws_sqs_queue_policy.iceberg_file_events_policy]
}

# =============================================================================
# CLOUDWATCH LOG GROUP FOR FLINK
# =============================================================================

resource "aws_cloudwatch_log_group" "flink_log_group" {
  name              = "/aws/kinesis-analytics/${local.setup_naming_prefix}-flink-commit-worker"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, {
    Name = "${local.setup_naming_prefix}-flink-commit-worker-logs"
  })
}

resource "aws_cloudwatch_log_stream" "flink_log_stream" {
  name           = "kinesis-analytics-log-stream"
  log_group_name = aws_cloudwatch_log_group.flink_log_group.name
}

# =============================================================================
# AWS MANAGED FLINK APPLICATION
# =============================================================================

resource "aws_kinesisanalyticsv2_application" "flink_iceberg_commit_worker" {
  name                   = "${local.setup_naming_prefix}-flink-commit-worker"
  description            = "Flink job for Iceberg metadata commits - handles multiple tables with single-writer pattern"
  runtime_environment    = var.flink_runtime
  service_execution_role = var.flink_role_arn

  # Streaming application mode
  application_mode = "STREAMING"

  application_configuration {

    # Application Code Configuration
    application_code_configuration {
      code_content {
        s3_content_location {
          bucket_arn = "arn:aws:s3:::${var.flink_jar_bucket}"
          file_key   = var.flink_jar_key
        }
      }
      code_content_type = "ZIPFILE"
    }

    # Flink Application Configuration
    flink_application_configuration {

      # Checkpoint Configuration
      checkpoint_configuration {
        configuration_type            = "CUSTOM"
        checkpointing_enabled         = true
        checkpoint_interval           = var.checkpoint_interval_ms
        min_pause_between_checkpoints = 5000
      }

      # Monitoring Configuration
      monitoring_configuration {
        configuration_type = "CUSTOM"
        metrics_level      = "APPLICATION"
        log_level          = "INFO"
      }

      # Parallelism Configuration
      parallelism_configuration {
        configuration_type   = "CUSTOM"
        parallelism          = var.parallelism
        parallelism_per_kpu  = 1
        auto_scaling_enabled = true
      }
    }

    # Environment Properties (Application Configuration)
    environment_properties {
      property_group {
        property_group_id = "FlinkApplicationProperties"

        property_map = {
          # AWS Configuration
          "aws.region" = data.aws_region.current.id

          # SQS Configuration
          "sqs.queue.url"  = aws_sqs_queue.iceberg_file_events.url
          "sqs.region"     = data.aws_region.current.id
          "sqs.batch.size" = tostring(var.sqs_batch_size)

          # Iceberg Configuration
          "iceberg.catalog.type"            = "glue"
          "iceberg.catalog.warehouse"       = "s3://${var.s3_bucket_name}"
          "iceberg.commit.batch.size"       = "100"
          "iceberg.commit.batch.timeout.ms" = "2000"

          # Commit Retry Configuration
          "commit.initial.retry.delay.ms" = "500"
          "commit.max.retries"            = "5"
          "commit.max.retry.delay.ms"     = "30000"
          "commit.jitter.percent"         = "20"

          # Schema Evolution Configuration
          "schema.evolution.enabled"        = "true"
          "schema.evolution.max.retries"    = "3"
          "schema.evolution.retry.delay.ms" = "1000"

          # Flink Configuration
          "flink.parallelism"         = tostring(var.parallelism)
          "flink.checkpoint.interval" = tostring(var.checkpoint_interval_ms)

          # New Relic Monitoring
          "newrelic.license.key.secret"   = var.newrelic_license_key_secret
          "newrelic.metrics.api.endpoint" = var.newrelic_metrics_endpoint
        }
      }
    }

    # Application Snapshot Configuration
    application_snapshot_configuration {
      snapshots_enabled = var.snapshots_enabled
    }
  }

  # CloudWatch Logging
  cloudwatch_logging_options {
    log_stream_arn = aws_cloudwatch_log_stream.flink_log_stream.arn
  }

  tags = merge(var.tags, {
    Name = "${local.setup_naming_prefix}-flink-commit-worker"
  })

  # Ensure CloudWatch resources are created first
  depends_on = [
    aws_cloudwatch_log_stream.flink_log_stream
  ]
}
