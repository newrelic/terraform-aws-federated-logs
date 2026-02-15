resource "aws_iam_role" "glue_service_role" {
  name = "${local.naming_prefix}-glue-service-role"
  permissions_boundary = "" 
  description = "Role for Glue Service to access S3 and manage its own resources"

  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = {
          Service = "glue.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_policy" "glue_service_policy" {
  name        = "${local.naming_prefix}-glue-service-policy"
  description = "Policy for Glue service to access S3 and manage its own resources"
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [
      {
        Sid      = "GlueServiceAccess"
        Effect   = "Allow"
        Action   = [
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
          "arn:aws:glue:*:*:catalog",
          "arn:aws:glue:*:*:database/${var.glue_catalog_db_name}",
          "arn:aws:glue:*:*:table/${var.glue_catalog_db_name}/*"
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