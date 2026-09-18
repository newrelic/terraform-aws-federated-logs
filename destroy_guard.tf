# Root-level destroy-time guard for the whole federated-logs deployment.
#
# `input` captures var.force_destroy at each apply and lands in state. The
# `when = destroy` provisioner reads it back at destroy time and fails fast
# when it was left at false, printing an actionable message. The real
# data-safety guarantee comes from `aws_s3_bucket.this.force_destroy = false`
# refusing to delete a non-empty bucket — the guard is what turns that
# refusal into a clear error the operator can act on.
#
# Two-step teardown the message points at:
#   1. Set `force_destroy = true` in your tfvars.
#   2. `terraform apply` to update this guard's stored input and the S3 bucket's attribute.
#   3. `terraform destroy` to tear everything down.
resource "terraform_data" "destroy_guard" {
  input = var.force_destroy

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      if [ "${self.input}" != "true" ]; then
        echo "" >&2
        echo "ERROR: terraform destroy is blocked because force_destroy is not true." >&2
        echo "" >&2
        echo "To retain your log data while removing everything else, use the" >&2
        echo "  removed { lifecycle { destroy = false } } snippet documented in the README." >&2
        echo "" >&2
        echo "To delete everything (including stored logs), set force_destroy = true in your" >&2
        echo "tfvars, run 'terraform apply' to update this guard and the S3 bucket, then rerun" >&2
        echo "'terraform destroy'." >&2
        echo "" >&2
        exit 1
      fi
    EOT
  }
}
