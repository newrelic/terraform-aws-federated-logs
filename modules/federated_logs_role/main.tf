resource "aws_iam_role" "glue_service_role" {
  name                 = "${var.resource_naming_prefix}-glue-service-role"
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
  name        = "${var.resource_naming_prefix}-glue-service-policy"
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
          "glue:BatchGetPartition"
        ]
        Resource = [
          "arn:aws:glue:${var.aws_region}:${var.aws_account_id}:catalog",
          "arn:aws:glue:${var.aws_region}:${var.aws_account_id}:database/${var.glue_catalog_db_name}",
          "arn:aws:glue:${var.aws_region}:${var.aws_account_id}:table/${var.glue_catalog_db_name}/*"
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

resource "aws_iam_role_policy_attachment" "glue_service_attach" {
  role       = aws_iam_role.glue_service_role.name
  policy_arn = aws_iam_policy.glue_service_policy.arn
}

resource "aws_iam_role" "reader-role" {
  name        = "${var.resource_naming_prefix}-nr-query-role"
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
          "sts:ExternalId" = var.nr_account_id
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "reader_policy" {
  name = "${var.resource_naming_prefix}-nr-query-policy"
  role = aws_iam_role.reader-role.id

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
          "arn:aws:glue:${var.aws_region}:${var.aws_account_id}:catalog",
          "arn:aws:glue:${var.aws_region}:${var.aws_account_id}:database/${var.glue_catalog_db_name}",
          "arn:aws:glue:${var.aws_region}:${var.aws_account_id}:table/${var.glue_catalog_db_name}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role" "pcg-writer-role" {
  name                 = "${var.resource_naming_prefix}-pcg-writer-role"
  description          = "IAM Role for Iceberg metadata writer with Glue and S3 access"
  permissions_boundary = ""

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      for key, config in var.clusters : {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          # Use the ARN directly from your input map
          Federated = config.oidc_provider_arn
        }
        Condition = {
          # We strip "arn:aws:iam::xxxx:oidc-provider/" to get the hostname
          StringEquals = {
            "${replace(config.oidc_provider_arn, "/^arn:aws:iam::.*:oidc-provider//", "")}:sub" : "system:serviceaccount:${config.k8s_namespace}:${config.k8s_service_account_name}",
            "${replace(config.oidc_provider_arn, "/^arn:aws:iam::.*:oidc-provider//", "")}:aud" : "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "writer_policy" {
  name = "${var.resource_naming_prefix}-pcg-writer-policy"
  role = aws_iam_role.pcg-writer-role.id

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
          "arn:aws:glue:${var.aws_region}:${var.aws_account_id}:catalog",
          "arn:aws:glue:${var.aws_region}:${var.aws_account_id}:database/${var.glue_catalog_db_name}",
          "arn:aws:glue:${var.aws_region}:${var.aws_account_id}:table/${var.glue_catalog_db_name}/*"
        ]
      }
    ]
  })
}