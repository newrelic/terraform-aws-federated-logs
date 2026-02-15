resource "aws_iam_role" "this" {
  name        = "${local.naming_prefix}-nr-query-role"
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
  name = "${local.naming_prefix}-nr-query-policy"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3ReadOnlyAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          "arn:aws:s3:::${var.s3_bucket_name}",
          "arn:aws:s3:::${var.s3_bucket_name}/*"
        ]
      },
      {
        Sid    = "GlueCatalogReadOnly"
        Effect = "Allow"
        Action = [
          "glue:GetDatabase",
          "glue:GetTable",
          "glue:GetPartitions",
          "glue:BatchGetPartition"
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