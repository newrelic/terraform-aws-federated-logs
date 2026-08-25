data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  s3_bucket_arn  = "arn:aws:s3:::${var.s3_bucket_name}"
  s3_object_arn  = "arn:aws:s3:::${var.s3_bucket_name}/*"
  glue_catalog   = "arn:aws:glue:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:catalog"
  glue_db_arn    = "arn:aws:glue:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:database/${var.glue_database_name}"
  glue_table_arn = "arn:aws:glue:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:table/${var.glue_database_name}/*"

  glue_role_name       = element(split("/", var.glue_service_role_arn), length(split("/", var.glue_service_role_arn)) - 1)
  pcg_writer_role_name = element(split("/", var.pcg_writer_role_arn), length(split("/", var.pcg_writer_role_arn)) - 1)
  nr_reader_role_name  = element(split("/", var.nr_reader_role_arn), length(split("/", var.nr_reader_role_arn)) - 1)
}
