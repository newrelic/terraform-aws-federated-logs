# Helper module for tests - empties S3 bucket before destroy
# This is only used in tests, not in the actual module

variable "bucket_name" {
  description = "Name of the S3 bucket to empty"
  type        = string
}

resource "null_resource" "empty_bucket" {
  triggers = {
    bucket_name = var.bucket_name
    always_run  = timestamp()
  }

  provisioner "local-exec" {
    command = "aws s3 rm s3://${var.bucket_name} --recursive || true"
  }
}

output "bucket_emptied" {
  description = "Confirmation that bucket was emptied"
  value       = var.bucket_name
}
