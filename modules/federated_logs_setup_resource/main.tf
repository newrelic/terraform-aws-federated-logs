data "aws_region" "current" {
  region = var.region
}

resource "aws_s3_bucket" "this" {
  bucket = local.setup_naming_prefix
  region = data.aws_region.current.region

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_glue_catalog_database" "this" {
  name        = lower(replace(local.setup_naming_prefix, "-", "_"))
  description = "Glue database containing NR resources for federated logs"
  region      = data.aws_region.current.region

  lifecycle {
    prevent_destroy = true
  }
}