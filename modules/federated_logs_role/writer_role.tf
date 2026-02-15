
resource "aws_iam_role" "pcg-writer-role" {
  name                 = "${local.naming_prefix}-pcg-writer-role"
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
  name = "${local.naming_prefix}-pcg-writer-policy"
  role = aws_iam_role.pcg-writer-role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3WriteAccess"
        Effect = "Allow"
        Action = [
            "s3:PutObject", 
            "s3:GetObject", 
            "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.s3_bucket_name}",
          "arn:aws:s3:::${var.s3_bucket_name}/*"
        ]
      },
      {
        Sid    = "GlueCatalogUpdate"
        Effect = "Allow"
        Action = [
          "glue:GetDatabase",
          "glue:GetTable",
          "glue:UpdateTable",
          "glue:CreateTable"
        ]
        Resource = [
          "arn:aws:glue:*:*:catalog",
          "arn:aws:glue:*:*:database/${var.glue_catalog_db_name}",
          "arn:aws:glue:*:*:table/${var.glue_catalog_db_name}/*"
        ]
      }
    ]
  })
}