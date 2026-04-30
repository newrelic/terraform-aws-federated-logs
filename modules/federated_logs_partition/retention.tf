# S3 object to store the Glue Spark ETL script
resource "aws_s3_object" "retention_script" {
  count = local.is_data_retention_enabled ? 1 : 0

  bucket = var.s3_bucket_name
  key    = "${var.glue_catalog_db_name}/scripts/retention_job.py"
  source = "${path.module}/scripts/retention_job.py"
  etag   = filemd5("${path.module}/scripts/retention_job.py")
}

# AWS Glue Spark ETL Job for retention cleanup
resource "aws_glue_job" "retention" {
  count = local.is_data_retention_enabled ? 1 : 0

  name         = "${local.setup_naming_prefix}-retention-job"
  role_arn     = var.glue_service_role_arn
  glue_version = "4.0"

  command {
    name            = "glueetl"
    script_location = "s3://${var.s3_bucket_name}/${aws_s3_object.retention_script[0].key}"
    python_version  = "3"
  }

  worker_type       = "G.1X"
  number_of_workers = 2
  timeout           = 60
  max_retries       = 1

  default_arguments = {
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-glue-datacatalog"          = "true"
    "--enable-metrics"                   = "true"
    "--enable-spark-ui"                  = "true"
    "--datalake-formats"                 = "iceberg"
    "--conf"                             = "spark.sql.extensions=org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions --conf spark.sql.catalog.glue_catalog=org.apache.iceberg.spark.SparkCatalog --conf spark.sql.catalog.glue_catalog.warehouse=s3://${var.s3_bucket_name}/warehouse/ --conf spark.sql.catalog.glue_catalog.catalog-impl=org.apache.iceberg.aws.glue.GlueCatalog --conf spark.sql.catalog.glue_catalog.io-impl=org.apache.iceberg.aws.s3.S3FileIO --conf spark.sql.iceberg.handle-timestamp-without-timezone=true"
    "--DATABASE_NAME"                    = var.glue_catalog_db_name
    "--TABLE_RETENTION"                  = jsonencode(local.table_retention_days)
  }
  depends_on = [aws_s3_object.retention_script]
}

# Glue Trigger to schedule retention job
# Runs daily at midnight UTC (00:00) to delete old data based on table retention_period settings
resource "aws_glue_trigger" "retention_schedule" {
  count = local.is_data_retention_enabled ? 1 : 0

  name     = "${local.setup_naming_prefix}-retention-schedule"
  type     = "SCHEDULED"
  schedule = "cron(0 0 * * ? *)"

  actions {
    job_name = aws_glue_job.retention[0].name
  }
}

# CloudWatch Log Group for retention job logs
resource "aws_cloudwatch_log_group" "retention_logs" {
  count = local.is_data_retention_enabled ? 1 : 0

  name              = "/aws-glue/jobs/${local.setup_naming_prefix}-retention-job"
  retention_in_days = 7
}
