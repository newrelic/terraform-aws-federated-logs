resource "aws_s3_bucket" "this" {
  bucket = local.setup_naming_prefix
}

resource "null_resource" "empty_bucket_on_destroy" {
  triggers = {
    bucket_id = aws_s3_bucket.this.id
  }

  provisioner "local-exec" {
    when    = destroy
    command = "aws s3 rm s3://${self.triggers.bucket_id} --recursive || true"
  }
}

resource "aws_glue_catalog_database" "this" {
  name        = lower(replace(local.setup_naming_prefix, "-", "_"))
  description = "Glue database containing NR resources for federated logs"
}