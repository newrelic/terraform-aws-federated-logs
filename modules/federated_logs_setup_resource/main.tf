resource "aws_s3_bucket" "this" {
  bucket = "${var.naming_prefix}-${local.s3_bucket_name}"
  force_destroy = true
}

resource "aws_glue_catalog_database" "this" {
  name = "${var.naming_prefix}-${local.glue_catalog_db_name}"
  description = "Glue database containing NR resources for federated logs"
}