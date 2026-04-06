# ---------------------------------------------------------------
# Layer 1 — AWS-side resource checks (always run during plan/apply)
# ---------------------------------------------------------------

check "s3_bucket_accessible" {
  data "aws_s3_bucket" "validate" {
    bucket = var.s3_bucket_name
  }

  assert {
    condition     = data.aws_s3_bucket.validate.id != ""
    error_message = "S3 bucket '${var.s3_bucket_name}' does not exist or is not accessible."
  }
}

check "glue_database_accessible" {
  data "aws_glue_catalog_database" "validate" {
    name = var.glue_catalog_db_name
  }

  assert {
    condition     = data.aws_glue_catalog_database.validate.name != ""
    error_message = "Glue catalog database '${var.glue_catalog_db_name}' does not exist."
  }
}

# ---------------------------------------------------------------
# Layer 2 — End-to-end ingest + query (on-demand only)
# ---------------------------------------------------------------

resource "terraform_data" "validate_e2e" {
  count = var.run_validation ? 1 : 0

  triggers_replace = [
    local.run_id,
    var.s3_bucket_name,
    var.glue_catalog_db_name,
  ]

  provisioner "local-exec" {
    command     = "bash ${path.module}/scripts/validate_e2e.sh"
    environment = {
      S3_BUCKET          = var.s3_bucket_name
      GLUE_DB_NAME       = var.glue_catalog_db_name
      NR_ACCOUNT_ID      = tostring(var.newrelic_account_id)
      NR_USER_API_KEY    = var.newrelic_user_api_key
      NR_REGION          = var.newrelic_region
      MAX_WAIT_SECONDS   = tostring(var.max_wait_seconds)
      POLL_INTERVAL_SECS = tostring(var.poll_interval_seconds)
      RUN_ID             = local.run_id
    }
  }
}
