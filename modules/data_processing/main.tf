# ── Base Role ────────────────────────────────────────────────────────────────
# Fleet-level IAM role authenticated via OIDC (IRSA) or Pod Identity.
# Has NO direct S3/Glue permissions — it can only assume per-setup pcg-writer
# roles via the ABAC inline policy below.

resource "aws_iam_role" "base_role" {
  name        = "${local.naming_prefix}-base"
  description = "Fleet-level base role for PCG. Authenticates via EKS and assumes per-setup writer roles via ABAC."

  assume_role_policy = local.auth_mode == "irsa" ? jsonencode({
    Version = "2012-10-17"
    Statement = [
      for key, config in var.clusters : {
        Effect = "Allow"
        Action = "sts:AssumeRoleWithWebIdentity"
        Principal = {
          Federated = config.oidc_provider_arn
        }
        Condition = {
          StringEquals = {
            "${replace(config.oidc_provider_arn, "/^arn:aws:iam::.*:oidc-provider//", "")}:sub" = "system:serviceaccount:${config.k8s_namespace}:${config.k8s_service_account_name}"
            "${replace(config.oidc_provider_arn, "/^arn:aws:iam::.*:oidc-provider//", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
    }) : jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "pods.eks.amazonaws.com"
        }
        Action = ["sts:AssumeRole", "sts:TagSession"]
        Condition = {
          StringEquals = {
            "aws:RequestTag/kubernetes-namespace" = [for c in var.clusters : c.k8s_namespace]
          }
        }
      }
    ]
  })

  tags = {
    fleet_entity_guid = var.fleet_entity_guid
  }
}

# ABAC wildcard policy: allows assuming any pcg-writer role in any account
# where the role's fleet_entity_guid tag matches this base role's fleet_entity_guid tag.
resource "aws_iam_role_policy" "abac_assume_policy" {
  name = "${local.naming_prefix}-abac-assume"
  role = aws_iam_role.base_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["sts:AssumeRole", "sts:TagSession"]
        Resource = "arn:aws:iam::*:role/newrelic-fed-logs-*-pcg-writer"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/fleet_entity_guid" = "$${aws:PrincipalTag/fleet_entity_guid}"
          }
        }
      }
    ]
  })
}

# Pod Identity: bind base role to each cluster's service account
resource "aws_eks_pod_identity_association" "base_role" {
  for_each = { for k, v in var.clusters : k => v if local.auth_mode == "pod_identity" }

  cluster_name    = each.value.cluster_name
  namespace       = each.value.k8s_namespace
  service_account = each.value.k8s_service_account_name
  role_arn        = aws_iam_role.base_role.arn
}

# ── Flink Role ────────────────────────────────────────────────────────────────
# Fleet-level IAM role for Managed Flink. Has NO direct S3/Glue permissions —
# assumes per-setup pcg-writer roles via ABAC, mirroring the PCG base role.

resource "aws_iam_role" "flink_role" {
  name        = "${local.naming_prefix}-flink-base"
  description = "Fleet-level Flink role for Iceberg commits. Trusts Managed Flink service and assumes per-setup writer roles via ABAC."

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "kinesisanalytics.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    fleet_entity_guid = var.fleet_entity_guid
  }
}

resource "aws_iam_role_policy" "flink_role_policy" {
  name = "${local.naming_prefix}-flink-policy"
  role = aws_iam_role.flink_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # S3 read-only access for the JAR deployment bucket (customer's bucket)
      {
        Sid    = "S3DeploymentBucketAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectMetadata",
          "s3:ListBucket",
        ]
        Resource = [
          aws_s3_bucket.flink_jar.arn,
          "${aws_s3_bucket.flink_jar.arn}/*",
        ]
      },
      # SQS: consume Iceberg file-creation events
      {
        Sid    = "SQSAccess"
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl",
        ]
        Resource = [aws_sqs_queue.iceberg_file_events.arn]
      },
      # CloudWatch Logs: write Flink application logs
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams",
        ]
        Resource = ["arn:aws:logs:${data.aws_region.current.region}:*:log-group:/aws/kinesis-analytics/*"]
      },
      # CloudWatch Metrics: emit application-level metrics
      {
        Sid      = "CloudWatchMetrics"
        Effect   = "Allow"
        Action   = ["cloudwatch:PutMetricData"]
        Resource = ["*"]
      },
      # ABAC: assume setup-specific pcg-writer roles in any account
      {
        Effect   = "Allow"
        Action   = ["sts:AssumeRole", "sts:TagSession"]
        Resource = "arn:aws:iam::*:role/newrelic-fed-logs-*-pcg-writer"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/fleet_entity_guid" = "$${aws:PrincipalTag/fleet_entity_guid}"
          }
        }
      },
    ]
  })
}

# ── Flink Application ─────────────────────────────────────────────────────────

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# Read NR license key from environment variable (never stored in Terraform state)
data "external" "license_key" {
  program = ["python3", "${path.module}/scripts/get_license_key.py"]
}

resource "aws_cloudwatch_log_group" "flink_log_group" {
  name              = "/aws/kinesis-analytics/${local.naming_prefix}-flink-application"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, {
    Name = "${local.naming_prefix}-flink-application-logs"
  })
}

resource "aws_cloudwatch_log_stream" "flink_log_stream" {
  name           = "${local.naming_prefix}-flink-log-stream"
  log_group_name = aws_cloudwatch_log_group.flink_log_group.name
}

resource "aws_kinesisanalyticsv2_application" "flink_iceberg_commit_worker" {
  name                   = "${local.naming_prefix}-flink-application"
  description            = "Flink job for Iceberg metadata commits - handles multiple tables with single-writer pattern"
  runtime_environment    = var.flink_runtime
  service_execution_role = aws_iam_role.flink_role.arn

  application_mode  = "STREAMING"
  start_application = var.start_application

  application_configuration {

    application_code_configuration {
      code_content {
        s3_content_location {
          bucket_arn = aws_s3_bucket.flink_jar.arn
          file_key   = local.flink_jar_dest_key
        }
      }
      code_content_type = "ZIPFILE"
    }

    flink_application_configuration {

      # Flink checkpointing configuration
      # See: https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/datastream/fault-tolerance/checkpointing/
      checkpoint_configuration {
        configuration_type    = "CUSTOM"
        checkpointing_enabled = true
        checkpoint_interval   = var.checkpoint_interval_ms
      }

      monitoring_configuration {
        configuration_type = "CUSTOM"
        metrics_level      = "APPLICATION"
        log_level          = "INFO"
      }

      # Flink parallelism configuration
      # See: https://docs.aws.amazon.com/managed-flink/latest/apiv2/API_ParallelismConfiguration.html
      parallelism_configuration {
        configuration_type   = "CUSTOM"
        parallelism          = var.parallelism
        parallelism_per_kpu  = var.parallelism_per_kpu
        auto_scaling_enabled = var.auto_scaling_enabled
      }
    }

    environment_properties {
      property_group {
        property_group_id = "FlinkApplicationProperties"

        property_map = {
          "aws.region" = data.aws_region.current.region

          "sqs.queue.url"  = aws_sqs_queue.iceberg_file_events.url
          "sqs.region"     = data.aws_region.current.region
          "sqs.batch.size" = tostring(var.sqs_batch_size)

          "iceberg.catalog.type"            = "glue"
          "iceberg.commit.batch.size"       = "100"
          "iceberg.commit.batch.timeout.ms" = "2000"

          "commit.initial.retry.delay.ms" = "500"
          "commit.max.retries"            = "5"
          "commit.max.retry.delay.ms"     = "30000"
          "commit.jitter.percent"         = "20"

          "schema.evolution.enabled"        = "true"
          "schema.evolution.max.retries"    = "3"
          "schema.evolution.retry.delay.ms" = "1000"

          "flink.parallelism"         = tostring(var.parallelism)
          "flink.checkpoint.interval" = tostring(var.checkpoint_interval_ms)

          "newrelic.license.key"          = data.external.license_key.result.license_key
          "newrelic.metrics.api.endpoint" = var.newrelic_metrics_endpoint
        }
      }
    }

    application_snapshot_configuration {
      snapshots_enabled = var.snapshots_enabled
    }
  }

  cloudwatch_logging_options {
    log_stream_arn = aws_cloudwatch_log_stream.flink_log_stream.arn
  }

  tags = merge(var.tags, {
    Name = "${local.naming_prefix}-flink-application"
  })

  depends_on = [
    aws_iam_role_policy.flink_role_policy,
    aws_cloudwatch_log_stream.flink_log_stream,
    aws_s3_object.flink_jar,
  ]
}

# ── Flink: SQS file-event queue ───────────────────────────────────────────────
# Dead-letter queue receives events that the Flink job failed to process.

resource "aws_sqs_queue" "iceberg_file_events_dlq" {
  name = "${local.naming_prefix}-flink-sqs-dlq"

  visibility_timeout_seconds = 30
  message_retention_seconds  = var.sqs_message_retention
  max_message_size           = 262144 # 256 KB
  delay_seconds              = 0
  receive_wait_time_seconds  = 0 # short polling for DLQ

  sqs_managed_sse_enabled = true

  tags = merge(var.tags, {
    Name = "${local.naming_prefix}-flink-sqs-dlq"
  })
}

# Main queue: receives S3 Parquet file-creation events via EventBridge.
resource "aws_sqs_queue" "iceberg_file_events" {
  name = "${local.naming_prefix}-flink-sqs-queue"

  visibility_timeout_seconds = var.sqs_visibility_timeout
  message_retention_seconds  = var.sqs_message_retention
  max_message_size           = 262144 # 256 KB
  delay_seconds              = 0
  receive_wait_time_seconds  = 20 # long polling reduces API calls

  sqs_managed_sse_enabled = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.iceberg_file_events_dlq.arn
    maxReceiveCount     = var.sqs_max_receive_count
  })

  tags = merge(var.tags, {
    Name = "${local.naming_prefix}-flink-sqs-queue"
  })
}

resource "aws_sqs_queue_policy" "iceberg_file_events_policy" {
  queue_url = aws_sqs_queue.iceberg_file_events.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEventBridgeToSendMessage"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.iceberg_file_events.arn
        Condition = {
          StringEquals = {
            # Only allow events from the current account and explicitly allowed accounts
            "aws:SourceAccount" = local.all_allowed_account_ids
          }
          ArnLike = {
            # Matches every per-setup EventBridge rule that follows the naming convention
            "aws:SourceArn" = local.sqs_eventbridge_source_arn_patterns
          }
        }
      }
    ]
  })
}

# Allow the main queue to use the DLQ for redrive.
resource "aws_sqs_queue_redrive_allow_policy" "iceberg_dlq_allow" {
  queue_url = aws_sqs_queue.iceberg_file_events_dlq.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.iceberg_file_events.arn]
  })
}


# ── NGEP: AWS Connection Entity and Relationship ─────────────────────────────
# 1. newrelic_aws_connection — entity + tags
# 2. null_resource            — Python script that only creates the
#    HAS_FED_LOGS_BASE_ROLE relationship.
resource "newrelic_aws_connection" "fleet_ingest" {
  name        = "${local.naming_prefix}-aws-connection"
  description = var.fleet_ingest_connection_description

  scope_type = "ORGANIZATION"
  scope_id   = var.newrelic_org_id

  credential {
    assume_role {
      role_arn = aws_iam_role.base_role.arn
    }
  }

  tag {
    key    = "fleet_entity_guid"
    values = [var.fleet_entity_guid]
  }
  tag {
    key    = "auth_mode"
    values = [local.auth_mode]
  }
  tag {
    key    = "sqs_queue_arn"
    values = [aws_sqs_queue.iceberg_file_events.arn]
  }
  tag {
    key    = "flink_base_role_arn"
    values = [aws_iam_role.flink_role.arn]
  }
}

resource "null_resource" "fleet_relationship" {
  triggers = {
    fleet_entity_guid = var.fleet_entity_guid
    connection_id     = newrelic_aws_connection.fleet_ingest.id
    nr_endpoint       = local.nr_graphql_endpoint
    sqs_queue_arn     = aws_sqs_queue.iceberg_file_events.arn
  }

  provisioner "local-exec" {
    environment = {
      FLEET_ENTITY_GUID = var.fleet_entity_guid
      CONNECTION_ID     = newrelic_aws_connection.fleet_ingest.id
      NR_ENDPOINT       = local.nr_graphql_endpoint
      SQS_QUEUE_ARN     = aws_sqs_queue.iceberg_file_events.arn
    }
    command = "python3 ${path.module}/scripts/create_relationship.py"
  }

  depends_on = [newrelic_aws_connection.fleet_ingest]
}