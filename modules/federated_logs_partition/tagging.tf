# S3 object to store the Glue Python Shell script
resource "aws_s3_object" "tagging_script" {
  count = local.is_snapshot_tagging_enabled ? 1 : 0

  bucket = var.s3_bucket_name
  key    = "${var.glue_catalog_db_name}/scripts/tagging_job.py"
  source = "${path.module}/scripts/tagging_job.py"
  etag   = filemd5("${path.module}/scripts/tagging_job.py")
}

# AWS Glue Python Shell job for periodic snapshot tagging.
# Python Shell (not Spark ETL) because tagging is a single metadata commit
# per table — no data scan, no distributed compute — so a full Spark cluster
# would be pure overhead. See docs/superpowers/plans/2026-08-25-snapshot-tagging.md
# and the linked design doc for the job-type comparison.
resource "aws_glue_job" "tagging" {
  count = local.is_snapshot_tagging_enabled ? 1 : 0

  name     = "${local.setup_naming_prefix}-tagging-job"
  role_arn = var.glue_service_role_arn

  command {
    name            = "pythonshell"
    script_location = "s3://${var.s3_bucket_name}/${aws_s3_object.tagging_script[0].key}"
    python_version  = "3.9"
  }

  max_capacity = 0.0625 # smallest Python Shell allocation — metadata-only workload
  timeout      = 15
  max_retries  = 1

  default_arguments = {
    "--enable-continuous-cloudwatch-log" = "true"
    "--additional-python-modules"        = "pyiceberg[glue]<1.0"
    "--DATABASE_NAME"                    = var.glue_catalog_db_name
    "--WAREHOUSE_PATH"                   = "s3://${var.s3_bucket_name}/warehouse/"
    "--TABLE_TAG_CONFIG"                 = jsonencode(local.table_tag_config)
  }

  depends_on = [aws_s3_object.tagging_script]
}

# Glue Trigger to schedule the tagging job. Cron resolves to daily
# (cron(0 0 * * ? *)) or hourly (cron(0 * * * ? *)) based on the single
# cadence shared by every table that has snapshot_tagging.enabled = true —
# see terraform_data.tagging_cadence_check below for why it's guaranteed
# to be single-valued.
resource "aws_glue_trigger" "tagging_schedule" {
  count = local.is_snapshot_tagging_enabled ? 1 : 0

  name     = "${local.setup_naming_prefix}-tagging-schedule"
  type     = "SCHEDULED"
  schedule = local.tagging_cron_schedule

  actions {
    job_name = aws_glue_job.tagging[0].name
  }
}

# CloudWatch Log Group for tagging job logs.
# NOTE: a pythonshell Glue job writes to the account-wide
# /aws-glue/python-jobs/{output,error} log groups, not this one — this
# group exists for naming/retention parity with retention_logs. Any future
# alarming on this job's failures must target /aws-glue/python-jobs/*
# (filtered to this job's name), not this group.
resource "aws_cloudwatch_log_group" "tagging_logs" {
  count = local.is_snapshot_tagging_enabled ? 1 : 0

  name              = "/aws-glue/jobs/${local.setup_naming_prefix}-tagging-job"
  retention_in_days = 7
}

# Enforces that every table with snapshot_tagging.enabled = true agrees on
# cadence. One Glue trigger has exactly one cron schedule, so a mismatch
# across default_table_setting and partition_tables can't be honored.
# Implemented as a resource-level precondition (not a variable validation{}
# block) because the rule spans two separate variables, which variable
# validation blocks cannot see in Terraform >= 1.6.0 (the version floor
# declared in this repo's README) — that capability wasn't added until 1.9.
resource "terraform_data" "tagging_cadence_check" {
  count = local.is_snapshot_tagging_enabled ? 1 : 0

  input = "cadence-check"

  lifecycle {
    precondition {
      condition     = length(local.tagging_cadences) <= 1
      error_message = "All tables with snapshot_tagging.enabled = true must use the same cadence (one Glue trigger supports one cron schedule per setup). Found: ${join(", ", local.tagging_cadences)}."
    }
  }
}
