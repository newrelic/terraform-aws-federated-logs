# Get current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# =============================================================================
# IAM ROLE FOR FLINK APPLICATION
# =============================================================================

resource "aws_iam_role" "flink_commit_worker" {
  name                 = "${local.setup_naming_prefix}-flink-commit-worker"
  description          = "Role for Flink commit worker to process Iceberg file events"
  permissions_boundary = var.permissions_boundary_arn

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "kinesisanalytics.amazonaws.com"
        }
      },
    ]
  })

  tags = merge(var.tags, {
    Name = "${local.setup_naming_prefix}-flink-commit-worker"
  })
}

# =============================================================================
# IAM POLICY FOR FLINK APPLICATION
# =============================================================================

resource "aws_iam_policy" "flink_commit_worker" {
  name        = "${local.setup_naming_prefix}-flink-commit-worker"
  description = "Policy for Flink commit worker with S3, SQS, Glue, CloudWatch, and Secrets Manager access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3WarehouseAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectMetadata",
          "s3:HeadObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.s3_bucket_name}",
          "arn:aws:s3:::${var.s3_bucket_name}/*"
        ]
      },
      {
        Sid    = "S3DeploymentBucketAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectMetadata",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.flink_jar_bucket}",
          "arn:aws:s3:::${var.flink_jar_bucket}/*"
        ]
      },
      {
        Sid    = "SQSAccess"
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl"
        ]
        Resource = [
          var.sqs_queue_arn
        ]
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = [
          "arn:aws:logs:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:log-group:/aws/kinesis-analytics/*"
        ]
      },
      {
        Sid    = "CloudWatchMetrics"
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = ["*"]
      },
      {
        Sid    = "GlueCatalogAccess"
        Effect = "Allow"
        Action = [
          "glue:GetDatabase",
          "glue:GetDatabases",
          "glue:GetTable",
          "glue:GetTables",
          "glue:UpdateTable",
          "glue:CreateTable",
          "glue:GetPartition",
          "glue:GetPartitions",
          "glue:BatchCreatePartition",
          "glue:BatchGetPartition"
        ]
        Resource = [
          "arn:aws:glue:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:catalog",
          "arn:aws:glue:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:database/${var.glue_catalog_db_name}",
          "arn:aws:glue:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:table/${var.glue_catalog_db_name}/*"
        ]
      },
      {
        Sid    = "SecretsManagerAccess"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          "arn:aws:secretsmanager:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:secret:${var.secrets_manager_prefix}/*"
        ]
      }
    ]
  })
}

# =============================================================================
# ATTACH POLICY TO ROLE
# =============================================================================

resource "aws_iam_role_policy_attachment" "flink_commit_worker_attach" {
  role       = aws_iam_role.flink_commit_worker.name
  policy_arn = aws_iam_policy.flink_commit_worker.arn
}
