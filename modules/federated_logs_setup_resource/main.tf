resource "aws_s3_bucket" "this" {
  bucket        = "${var.resource_naming_prefix}-${local.s3_bucket_name}"
  force_destroy = true
}

resource "aws_glue_catalog_database" "this" {
  name        = "${var.resource_naming_prefix}_${local.glue_catalog_db_name}"
  description = "Glue database containing NR resources for federated logs"
}