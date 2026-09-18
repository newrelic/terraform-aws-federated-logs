data "aws_region" "current" {
  region = var.region
}

resource "aws_s3_bucket" "this" {
  bucket = local.setup_naming_prefix
  region = data.aws_region.current.region

  # Primary data-safety guard. When false (default) the S3 DeleteBucket call fails
  # on any non-empty bucket, so an accidental `terraform destroy` cannot drop stored
  # logs. Flip to true only for a deliberate teardown.
  force_destroy = var.force_destroy
}

resource "aws_glue_catalog_database" "this" {
  name        = lower(replace(local.setup_naming_prefix, "-", "_"))
  description = "Glue database containing NR resources for federated logs"
  region      = data.aws_region.current.region
}
