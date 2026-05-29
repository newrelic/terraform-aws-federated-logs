# CloudWatch alarm — fires when ANY Glue Iceberg optimizer fails on ANY
# table in this setup's database. Scoping by DATABASE_NAME keeps the alarm to this setup — other setups in
# the same account use different Glue databases and won't trip this alarm.

resource "aws_cloudwatch_metric_alarm" "glue_optimizer_failures" {
  alarm_name          = "${local.setup_naming_prefix}_glue_optimizer_failures"
  alarm_description   = "Fires when any Glue Iceberg optimizer (compaction, retention, or orphan_file_deletion) fails on any table in database ${var.glue_catalog_db_name}."
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  evaluation_periods  = 1
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "compaction"
    return_data = false
    period      = 300
    expression  = "SELECT SUM(\"Iceberg table compaction failure\") FROM SCHEMA(\"Glue\", DATABASE_NAME, TABLE_NAME) WHERE DATABASE_NAME = '${var.glue_catalog_db_name}'"
  }

  metric_query {
    id          = "retention"
    return_data = false
    period      = 300
    expression  = "SELECT SUM(\"Iceberg table retention failure\") FROM SCHEMA(\"Glue\", DATABASE_NAME, TABLE_NAME) WHERE DATABASE_NAME = '${var.glue_catalog_db_name}'"
  }

  metric_query {
    id          = "orphan_deletion"
    return_data = false
    period      = 300
    expression  = "SELECT SUM(\"Iceberg table orphan_file_deletion failure\") FROM SCHEMA(\"Glue\", DATABASE_NAME, TABLE_NAME) WHERE DATABASE_NAME = '${var.glue_catalog_db_name}'"
  }

  metric_query {
    id          = "total_failures"
    expression  = "compaction + retention + orphan_deletion"
    label       = "Total Glue Iceberg optimizer failures"
    return_data = true
  }
}
