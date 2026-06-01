# Get aws account id from caller

data "aws_caller_identity" "current" {}
data "aws_region" "current" {
  region = var.region
}

data "external" "base_role" {
  program = ["python3", "${path.module}/scripts/fetch_base_role.py"]
  query = {
    fleet_entity_guid = var.fleet_entity_guid
    nr_endpoint       = local.nr_graphql_endpoint
  }
}

resource "random_uuid" "external_id" {
  keepers = {
    # If this value changes, a new UUID will be generated
    setup_name = var.setup_name
  }
}

resource "aws_iam_role" "glue_service_role" {
  name        = "${local.setup_naming_prefix}-glue-service"
  description = "Role for Glue Service to access S3 and manage its own resources"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "glue.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "glue_service_policy" {
  name        = "${local.setup_naming_prefix}-glue-service"
  description = "Policy for Glue service to access S3 and manage its own resources"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "GlueServiceAccess"
        Effect = "Allow"
        Action = [
          "glue:GetDatabase",
          "glue:GetDatabases",
          "glue:CreateTable",
          "glue:UpdateTable",
          "glue:DeleteTable",
          "glue:GetTable",
          "glue:GetTables",
          "glue:GetPartition",
          "glue:GetPartitions",
          "glue:CreatePartition",
          "glue:UpdatePartition",
          "glue:DeletePartition",
          "glue:BatchCreatePartition",
          "glue:BatchDeletePartition",
          "glue:BatchGetPartition",
          "glue:StartJobRun",
          "glue:GetJobRun",
          "glue:GetJobRuns",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          "arn:aws:glue:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:catalog",
          "arn:aws:glue:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:database/${var.glue_catalog_db_name}",
          "arn:aws:glue:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:database/default",
          "arn:aws:glue:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:table/${var.glue_catalog_db_name}/*",
          "arn:aws:glue:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:job/*",
          "arn:aws:logs:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:log-group:/aws-glue/*"
        ]
      },
      {
        Sid    = "S3Access"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
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
        Sid    = "CloudWatchMetrics"
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role" "reader-role" {
  name        = "${local.setup_naming_prefix}-${local.nr_reader_role_suffix}"
  description = "Cross-account role for New Relic Query Engine to read logs"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::${local.nr_source_account}:role/NRGlobalIAMRole"
      }
      Action = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "sts:ExternalId" = random_uuid.external_id.result
        }
      }
    }]
  })
}

resource "aws_iam_policy" "reader_policy" {
  name        = "${local.setup_naming_prefix}-${local.nr_reader_role_suffix}"
  description = "Policy for New Relic Query Engine to read from S3 and Glue Catalog"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3DataReadAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.s3_bucket_name}",
          "arn:aws:s3:::${var.s3_bucket_name}/*"
        ]
      },
      {
        Sid    = "GlueCatalogReadAccess"
        Effect = "Allow"
        Action = [
          "glue:GetDatabase",
          "glue:GetDatabases",
          "glue:GetTable",
          "glue:GetTables",
          "glue:GetPartition",
          "glue:GetPartitions",
          "glue:BatchGetPartition"
        ]
        Resource = [
          "arn:aws:glue:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:catalog",
          "arn:aws:glue:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:database/${var.glue_catalog_db_name}",
          "arn:aws:glue:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:table/${var.glue_catalog_db_name}/*"
        ]
      }
    ]
  })
}

# ── PCG Writer Role ───────────────────────────────────────────────────────────
# Per-setup writer role. Trusts ONLY the fleet base role via ABAC tag matching.
# The base role must have fleet_entity_guid = var.fleet_entity_guid to satisfy the condition.

resource "aws_iam_role" "pcg-writer-role" {
  name        = "${local.setup_naming_prefix}-pcg-writer"
  description = "IAM Role for Iceberg metadata writer with Glue and S3 access"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = data.external.base_role.result["role_arn"]
        }
        Action = ["sts:AssumeRole", "sts:TagSession"]
        Condition = {
          StringEquals = {
            "aws:PrincipalTag/fleet_entity_guid" = var.fleet_entity_guid
          }
        }
      }
    ]
  })

  tags = {
    fleet_entity_guid = var.fleet_entity_guid
  }
}

resource "aws_iam_policy" "writer_policy" {
  name        = "${local.setup_naming_prefix}-pcg-writer"
  description = "Policy for Iceberg metadata writer with Glue and S3 access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3ObjectAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          "arn:aws:s3:::${var.s3_bucket_name}",
          "arn:aws:s3:::${var.s3_bucket_name}/*"
        ]
      },
      {
        Sid    = "GlueCatalogAccess"
        Effect = "Allow"
        Action = [
          "glue:GetDatabase",
          "glue:UpdateTable",
          "glue:GetTable"
        ]
        Resource = [
          "arn:aws:glue:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:catalog",
          "arn:aws:glue:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:database/${var.glue_catalog_db_name}",
          "arn:aws:glue:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:table/${var.glue_catalog_db_name}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "glue_service_attach" {
  role       = aws_iam_role.glue_service_role.name
  policy_arn = aws_iam_policy.glue_service_policy.arn
}

resource "aws_iam_role_policy_attachment" "reader_attach" {
  role       = aws_iam_role.reader-role.name
  policy_arn = aws_iam_policy.reader_policy.arn
}

resource "aws_iam_role_policy_attachment" "writer_attach" {
  role       = aws_iam_role.pcg-writer-role.name
  policy_arn = aws_iam_policy.writer_policy.arn
}
