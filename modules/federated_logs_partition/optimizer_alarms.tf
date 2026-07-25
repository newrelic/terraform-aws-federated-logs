# CloudWatch alarms — one per Glue Iceberg optimizer type (compaction, retention,
# orphan_file_deletion). Each fires when that optimizer fails on ANY table in this
# setup's database. Scoping by DATABASE_NAME keeps the alarms to this setup — other
# setups in the same account use different Glue databases and won't trip these alarms.

resource "aws_cloudwatch_metric_alarm" "glue_optimizer_failures" {
  for_each = local.optimizer_failure_metrics

  alarm_name          = "${local.setup_naming_prefix}_glue_${each.key}_failures"
  alarm_description   = "Fires when the Glue Iceberg ${each.key} optimizer fails on any table in database ${var.glue_catalog_db_name}."
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  evaluation_periods  = 1
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "failures"
    return_data = true
    period      = 300
    label       = "Glue Iceberg ${each.key} failures"
    expression  = "SELECT SUM(\"${each.value}\") FROM SCHEMA(\"AWS/Glue\", DATABASE_NAME, TABLE_NAME) WHERE DATABASE_NAME = '${var.glue_catalog_db_name}'"
  }
}
