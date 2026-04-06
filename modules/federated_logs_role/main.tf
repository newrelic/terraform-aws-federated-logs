# Get aws account id and region from caller

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# =============================================================================
# Glue Service Role — unchanged, used by Glue optimizers
# =============================================================================

resource "aws_iam_role" "glue_service_role" {
  name                 = "${local.setup_naming_prefix}-glue-service"
  permissions_boundary = ""
  description          = "Role for Glue Service to access S3 and manage its own resources"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "glue.amazonaws.com"
        }
      },
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
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          "arn:aws:glue:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:catalog",
          "arn:aws:glue:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:database/${var.glue_catalog_db_name}",
          "arn:aws:glue:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:table/${var.glue_catalog_db_name}/*",
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
      }
    ]
  })
}

# =============================================================================
# NR Reader Role — cross-account role for New Relic Query Engine
# =============================================================================

resource "random_uuid" "external_id" {
  keepers = {
    setup_name = var.setup_name
  }
}

resource "aws_iam_role" "reader-role" {
  name        = "${local.setup_naming_prefix}-nr-query"
  description = "Cross-account role for New Relic Query Engine to read logs"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        # The official NR Account provided in your POC
        AWS = "arn:aws:iam::${local.nr_source_account}:user/federated-logs-user"
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
  name        = "${local.setup_naming_prefix}-nr-query"
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

# =============================================================================
# PCG Writer Role (Target Setup Role)
#
# Trust: only the base role can assume this role, verified by:
#   1. Principal ARN — only the specific base role can call AssumeRole
#   2. ABAC tag — the caller's PCG_Instance tag must match this role's tag
# Policy: scoped to this setup's specific S3 bucket + Glue database.
# =============================================================================

resource "aws_iam_role" "pcg-writer-role" {
  name                 = "${local.setup_naming_prefix}-pcg-writer"
  description          = "Target setup role for PCG — scoped to this setup's S3 bucket and Glue DB. Trusted by the base role only."
  permissions_boundary = ""

  tags = {
    PCG_Instance = var.pcg_instance_id
  }

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Principal = {
          AWS = var.base_role_arn
        }
        Condition = {
          StringEquals = {
            "aws:PrincipalTag/PCG_Instance" = var.pcg_instance_id
          }
        }
      }
    ]
  })
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

# =============================================================================
# Policy Attachments
# =============================================================================

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

