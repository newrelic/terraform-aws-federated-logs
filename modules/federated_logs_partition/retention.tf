# AWS Secrets Manager secret to store New Relic API key (always created)
resource "aws_secretsmanager_secret" "newrelic_api_key" {
  name        = "${local.setup_naming_prefix}-newrelic-api-key"
  description = "New Relic API key for NGEP API authentication"
}

resource "aws_secretsmanager_secret_version" "newrelic_api_key" {
  secret_id = aws_secretsmanager_secret.newrelic_api_key.id
  secret_string = jsonencode({
    api_key = var.newrelic_api_key
  })
}

# S3 object to store the Glue Spark ETL script
resource "aws_s3_object" "retention_script" {
  count = local.has_retention_enabled ? 1 : 0

  bucket  = var.s3_bucket_name
  key     = "${var.glue_catalog_db_name}/scripts/retention_job.py"
  content = <<-PYTHON
import sys
import json
from datetime import datetime, timedelta
from pyspark.sql import SparkSession
from awsglue.utils import getResolvedOptions

def main():
    print("="*60)
    print("FEDERATED LOGS DATA RETENTION JOB")
    print("="*60)

    # Parse job parameters
    args = getResolvedOptions(sys.argv, ['DATABASE_NAME', 'TABLE_NAMES', 'RETENTION_PERIOD'])
    database = args['DATABASE_NAME']
    table_names = args['TABLE_NAMES'].split(',')  # Comma-separated list of tables
    retention_period = args['RETENTION_PERIOD']  # Format: "<number> DAYS" or "<number> DAY"

    print(f"Database: {database}")
    print(f"Tables to process: {table_names}")
    print(f"Retention period: {retention_period}")

    # Parse retention period (format: "7 DAYS" or "1 DAY")
    parts = retention_period.strip().split()
    if len(parts) != 2 or parts[1].upper() not in ['DAY', 'DAYS']:
        raise ValueError(f"Invalid retention format: {retention_period}. Expected '<number> DAYS'")

    days = int(parts[0])
    print(f"Parsed retention: {days} day(s)")

    # Calculate cutoff timestamp aligned to midnight UTC for efficient partition deletion
    # This ensures we delete whole hourly partitions (metadata-only) without CoW rewrites
    now = datetime.utcnow()
    cutoff = (now - timedelta(days=days)).replace(hour=0, minute=0, second=0, microsecond=0)
    cutoff_str = cutoff.strftime('%Y-%m-%d %H:%M:%S')
    print(f"Cutoff timestamp (midnight-aligned): {cutoff_str}")

    # Initialize Spark session with Hive support for Iceberg tables
    spark = SparkSession.builder \
        .appName("FederatedLogsRetention") \
        .enableHiveSupport() \
        .getOrCreate()

    print("✓ Spark session initialized")

    # Process each table with the same retention period
    results = {}
    for table_name in table_names:
        print(f"\n{'='*60}")
        print(f"Processing table: {table_name}")
        print(f"{'='*60}")

        try:
            # Execute DELETE using Spark SQL
            delete_query = f"DELETE FROM {database}.{table_name} WHERE timestamp < TIMESTAMP '{cutoff_str}'"
            print(f"[{table_name}] Executing: {delete_query}")
            spark.sql(delete_query)

            results[table_name] = 'SUCCESS'
            print(f"[{table_name}] ✓ Deletion completed successfully")

            # TODO: Report success to NGEP API

        except Exception as e:
            error_msg = str(e)
            results[table_name] = f'ERROR: {error_msg}'
            print(f"[{table_name}] ✗ Error: {error_msg}")

            # TODO: Report failure to NGEP API

            # Continue with other tables (don't fail fast)
            continue

    # Stop Spark session
    spark.stop()

    # Summary
    print(f"\n{'='*60}")
    print("RETENTION JOB SUMMARY")
    print(f"{'='*60}")
    print(json.dumps(results, indent=2))

    # Exit with error code if any failures
    failed = [t for t, s in results.items() if s != 'SUCCESS']
    if failed:
        print(f"\n⚠ {len(failed)} table(s) failed: {', '.join(failed)}")
        sys.exit(1)
    else:
        print(f"\n✓ All {len(results)} table(s) processed successfully")

if __name__ == '__main__':
    main()
PYTHON
}

# AWS Glue Spark ETL Job for retention cleanup
resource "aws_glue_job" "retention" {
  count = local.has_retention_enabled ? 1 : 0

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
    "--DATABASE_NAME"                    = var.glue_catalog_db_name
    "--TABLE_NAMES"                      = join(",", keys(local.all_tables))
    "--RETENTION_PERIOD"                 = var.retention_period
    "--SECRET_ARN"                       = aws_secretsmanager_secret.newrelic_api_key.arn
  }
}

# EventBridge rule to trigger retention job on schedule
# Runs daily at midnight UTC (00:00) to delete old data based on table retention_period settings
resource "aws_cloudwatch_event_rule" "retention_schedule" {
  count = local.has_retention_enabled ? 1 : 0

  name                = "${local.setup_naming_prefix}-retention-schedule"
  description         = "Trigger retention cleanup job for ${var.setup_name}"
  schedule_expression = "cron(0 0 * * ? *)"
}

# EventBridge target to invoke Glue job
resource "aws_cloudwatch_event_target" "retention_job" {
  count = local.has_retention_enabled ? 1 : 0

  rule      = aws_cloudwatch_event_rule.retention_schedule[0].name
  target_id = "GlueRetentionJob"
  arn       = aws_glue_job.retention[0].arn
  role_arn  = var.glue_service_role_arn
}

# CloudWatch Log Group for retention job logs
resource "aws_cloudwatch_log_group" "retention_logs" {
  count = local.has_retention_enabled ? 1 : 0

  name              = "/aws-glue/jobs/${local.setup_naming_prefix}-retention-job"
  retention_in_days = 7
}
