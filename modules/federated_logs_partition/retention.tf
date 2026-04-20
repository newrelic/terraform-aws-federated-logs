# S3 object to store the Glue Spark ETL script
resource "aws_s3_object" "retention_script" {
  count = local.is_retention_enabled ? 1 : 0

  bucket  = var.s3_bucket_name
  key     = "${var.glue_catalog_db_name}/scripts/retention_job.py"
  content = <<-PYTHON
import sys
import json
from datetime import datetime, timedelta, timezone
from pyspark.sql import SparkSession
from awsglue.utils import getResolvedOptions

def main():

    # Parse job parameters
    args = getResolvedOptions(sys.argv, ['DATABASE_NAME', 'TABLE_RETENTION'])
    database = args['DATABASE_NAME']
    table_retention_json = args['TABLE_RETENTION']

    # Parse JSON map of table names to retention days
    table_retention = json.loads(table_retention_json)

    # Initialize Spark session with Hive support for Iceberg tables
    spark = SparkSession.builder \
        .appName("FederatedLogsRetention") \
        .enableHiveSupport() \
        .getOrCreate()

    # Process each table with its specific retention period
    results = {}
    for table_name, retention_days in table_retention.items():
        print(f"Processing table: {table_name}")
        print(f"Retention period: {retention_days} days")

        # Calculate cutoff timestamp aligned to midnight UTC for efficient partition deletion
        now = datetime.now(timezone.utc)
        cutoff = (now - timedelta(days=retention_days)).replace(hour=0, minute=0, second=0, microsecond=0)
        cutoff_str = cutoff.strftime('%Y-%m-%d %H:%M:%S')
        print(f"Cutoff timestamp (midnight-aligned): {cutoff_str}")

        try:
            # Execute DELETE using Spark SQL with Iceberg catalog
            delete_query = f"DELETE FROM glue_catalog.{database}.{table_name} WHERE timestamp < TIMESTAMP '{cutoff_str}'"
            print(f"[{table_name}] Executing: {delete_query}")
            spark.sql(delete_query)

            results[table_name] = 'SUCCESS'
            print(f"[{table_name}] Deletion completed successfully")

            # TODO: Report success to NGEP API

        except Exception as e:
            error_msg = str(e)
            results[table_name] = f'ERROR: {error_msg}'
            print(f"[{table_name}] Error: {error_msg}")

            # TODO: Report failure to NGEP API

            # Continue with other tables (don't fail fast)
            continue

    # Stop Spark session
    spark.stop()

    # Exit with error code if any failures
    failed = [t for t, s in results.items() if s != 'SUCCESS']
    if failed:
        print(f" {len(failed)} table(s) failed: {', '.join(failed)}")
        sys.exit(1)
    else:
        print(f" All {len(results)} table(s) processed successfully")

if __name__ == '__main__':
    main()
PYTHON
}

# AWS Glue Spark ETL Job for retention cleanup
resource "aws_glue_job" "retention" {
  count = local.is_retention_enabled ? 1 : 0

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
  timeout           = 120
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
  count = local.is_retention_enabled ? 1 : 0

  name     = "${local.setup_naming_prefix}-retention-schedule"
  type     = "SCHEDULED"
  schedule = "cron(0 0 * * ? *)"

  actions {
    job_name = aws_glue_job.retention[0].name
  }
}

# CloudWatch Log Group for retention job logs
resource "aws_cloudwatch_log_group" "retention_logs" {
  count = local.is_retention_enabled ? 1 : 0

  name              = "/aws-glue/jobs/${local.setup_naming_prefix}-retention-job"
  retention_in_days = 7
}
