# S3 object to store the Glue Python Shell script
resource "aws_s3_object" "tagging_script" {
  count = local.is_snapshot_tagging_enabled ? 1 : 0

  bucket = aws_s3_bucket.retention_scripts[0].id
  key    = "scripts/tagging_job.py"
  source = "${path.module}/scripts/tagging_job.py"
  etag   = filemd5("${path.module}/scripts/tagging_job.py")
}

# AWS Glue Python Shell job for periodic snapshot tagging.
# Python Shell (not Spark ETL) because tagging is a single metadata commit
# per table — no data scan, no distributed compute — so a full Spark cluster
# (Glue 4.0, G.1X workers, ~1 minute cold start) would be pure overhead for
# a job that only writes one JSON pointer; Python Shell gets fractional-DPU
# billing and seconds-scale startup instead.
resource "aws_glue_job" "tagging" {
  count = local.is_snapshot_tagging_enabled ? 1 : 0

  name     = "${local.setup_naming_prefix}-tagging-job"
  role_arn = var.glue_service_role_arn

  command {
    name            = "pythonshell"
    script_location = "s3://${aws_s3_bucket.retention_scripts[0].bucket}/${aws_s3_object.tagging_script[0].key}"
    python_version  = "3.9"
  }

  max_capacity = 0.0625 # smallest Python Shell allocation — metadata-only workload
  timeout      = 15
  max_retries  = 1

  # stdout/stderr go to the account-wide /aws-glue/python-jobs/{output,error}
  # log groups — Python Shell jobs have no per-job log group or continuous
  # logging. Alarming on this job must filter those groups by job name.
  default_arguments = {
    # Both versions are pinned exactly because Glue pip-installs these on
    # every run: a floating bound would pull an untested pyiceberg release on
    # the next scheduled run. pyarrow is held at 14.0.2 because newer releases
    # fail to import on the Python Shell 3.9 runtime (ImportError:
    # S3RetryStrategy from pyarrow._s3fs), even though pyiceberg 0.10.0
    # declares pyarrow>=17 — the tagging path only uses catalog/metadata
    # APIs, not pyiceberg.io.pyarrow. This pair was verified end to end on a
    # live Python Shell 3.9 job running tagging_job.py, including a real
    # create_tag commit.
    "--additional-python-modules" = "pyarrow==14.0.2,pyiceberg[glue]==0.10.0"
    "--DATABASE_NAME"             = var.glue_catalog_db_name
    "--WAREHOUSE_PATH"            = "s3://${var.s3_bucket_name}/warehouse/"
    "--TABLE_TAG_CONFIG"          = jsonencode(local.table_tag_config)
  }

  depends_on = [aws_s3_object.tagging_script]
}

# Glue Trigger to schedule the tagging job daily at 01:00 UTC, offset from
# the retention job's midnight run so the two don't contend for commits.
resource "aws_glue_trigger" "tagging_schedule" {
  count = local.is_snapshot_tagging_enabled ? 1 : 0

  name     = "${local.setup_naming_prefix}-tagging-schedule"
  type     = "SCHEDULED"
  schedule = "cron(0 1 * * ? *)"

  actions {
    job_name = aws_glue_job.tagging[0].name
  }
}
