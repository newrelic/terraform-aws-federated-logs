locals {
  sqs_queue_name = var.sqs_queue_name
  sqs_dlq_name   = var.sqs_dlq_name
  flink_app_name = var.flink_application_name

  naming_prefix         = "newrelic-fed-logs-${var.setup_name}"
  glue_prefix           = "newrelic_fed_logs_${var.setup_name}"
  eventbridge_rule_name = "${local.naming_prefix}-iceberg-file-created"
  glue_retention_job    = "${local.glue_prefix}-retention-job"

  dashboard_name = coalesce(var.dashboard_name, "Federated Logs - ${var.setup_name}")
}

resource "newrelic_one_dashboard" "this" {
  name        = local.dashboard_name
  permissions = "public_read_only"
  account_id  = var.newrelic_account_id

  # ══════════════════════════════════════════════════════════════════════════
  # Page 1 — Overview
  # ══════════════════════════════════════════════════════════════════════════
  page {
    name = "Overview"

    widget_markdown {
      title  = ""
      row    = 1
      column = 1
      width  = 12
      height = 1
      text   = <<-EOT
        ## Federated Logs — ${var.setup_name}
        AWS infrastructure monitoring for New Relic Federated Logs.
        **S3:** `${var.s3_bucket_name}` | **Glue DB:** `${var.glue_catalog_db_name}`
      EOT
    }

    widget_billboard {
      title  = "SQS Queue Depth"
      row    = 3
      column = 1
      width  = 3
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT average(`aws.sqs.ApproximateNumberOfMessagesVisible`) AS 'Messages' FROM Metric WHERE `aws.sqs.QueueName` = '${local.sqs_queue_name}' SINCE 5 minutes ago"
      }

      warning  = 1000
      critical = 5000
    }

    widget_billboard {
      title  = "DLQ Depth"
      row    = 3
      column = 4
      width  = 3
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT average(`aws.sqs.ApproximateNumberOfMessagesVisible`) AS 'Messages' FROM Metric WHERE `aws.sqs.QueueName` = '${local.sqs_dlq_name}' SINCE 5 minutes ago"
      }

      warning  = 1
      critical = 10
    }

    widget_billboard {
      title  = "S3 Bucket Size"
      row    = 3
      column = 7
      width  = 3
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT average(`aws.s3.BucketSizeBytes`) / 1073741824 AS 'Size (GB)' FROM Metric WHERE `aws.s3.BucketName` = '${var.s3_bucket_name}' SINCE 3 days ago"
      }
    }

    widget_billboard {
      title  = "Glue Optimizer Failures (24 h)"
      row    = 3
      column = 10
      width  = 3
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT sum(`aws.glue.Iceberg table compaction failure`) + sum(`aws.glue.Iceberg table retention failure`) + sum(`aws.glue.Iceberg table orphan_file_deletion failure`) AS 'Failures' FROM Metric WHERE `aws.glue.DATABASE_NAME` = '${var.glue_catalog_db_name}' SINCE 24 hours ago"
      }
    }

    widget_line {
      title  = "SQS Throughput — Messages Sent & Deleted"
      row    = 6
      column = 1
      width  = 6
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT sum(`aws.sqs.NumberOfMessagesSent`) AS 'Sent', sum(`aws.sqs.NumberOfMessagesDeleted`) AS 'Deleted' FROM Metric WHERE `aws.sqs.QueueName` = '${local.sqs_queue_name}' SINCE 3 hours ago TIMESERIES AUTO"
      }
    }

    widget_line {
      title  = "Flink Application Uptime"
      row    = 6
      column = 7
      width  = 6
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT average(`aws.kinesisanalytics.uptime`) / 60000 AS 'Uptime (min)' FROM Metric WHERE `aws.kinesisanalytics.Application` = '${local.flink_app_name}' SINCE 3 hours ago TIMESERIES AUTO"
      }
    }
  }

  # ══════════════════════════════════════════════════════════════════════════
  # Page 2 — Event Pipeline (SQS + Flink)
  # ══════════════════════════════════════════════════════════════════════════
  page {
    name = "Data Processing - SQS & Flink"

    widget_line {
      title  = "Messages Sent to Queue"
      row    = 1
      column = 1
      width  = 6
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT sum(`aws.sqs.NumberOfMessagesSent`) AS 'Sent' FROM Metric WHERE `aws.sqs.QueueName` = '${local.sqs_queue_name}' SINCE 1 hour ago TIMESERIES AUTO"
      }
    }

    widget_line {
      title  = "Queue Depth — Visible Messages"
      row    = 1
      column = 7
      width  = 6
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT average(`aws.sqs.ApproximateNumberOfMessagesVisible`) AS 'Visible', average(`aws.sqs.ApproximateNumberOfMessagesNotVisible`) AS 'In-Flight' FROM Metric WHERE `aws.sqs.QueueName` = '${local.sqs_queue_name}' SINCE 1 hour ago TIMESERIES AUTO"
      }
    }

    widget_line {
      title  = "Oldest Message Age"
      row    = 4
      column = 1
      width  = 6
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT max(`aws.sqs.ApproximateAgeOfOldestMessage`) AS 'Age (s)' FROM Metric WHERE `aws.sqs.QueueName` = '${local.sqs_queue_name}' SINCE 1 hour ago TIMESERIES AUTO"
      }
    }

    widget_line {
      title  = "Messages Deleted (Processed)"
      row    = 4
      column = 7
      width  = 6
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT sum(`aws.sqs.NumberOfMessagesDeleted`) AS 'Deleted messages' FROM Metric WHERE `aws.sqs.QueueName` = '${local.sqs_queue_name}' SINCE 1 hour ago TIMESERIES AUTO"
      }
    }

    widget_markdown {
      title  = ""
      row    = 7
      column = 1
      width  = 12
      height = 1
      text   = "## Flink System Metrics"
    }

    widget_line {
      title  = "Flink Uptime vs Downtime"
      row    = 8
      column = 1
      width  = 4
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT average(`aws.kinesisanalytics.uptime`) / 60000 AS 'Uptime (min)', average(`aws.kinesisanalytics.downtime`) / 60000 AS 'Downtime (min)' FROM Metric WHERE `aws.kinesisanalytics.Application` = '${local.flink_app_name}' SINCE 6 hours ago TIMESERIES AUTO"
      }
    }

    widget_line {
      title  = "Flink Checkpoint Duration"
      row    = 8
      column = 5
      width  = 4
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT max(`aws.kinesisanalytics.lastCheckpointDuration`) AS 'Last Checkpoint (ms)', sum(`aws.kinesisanalytics.numberOfFailedCheckpoints`) AS 'Failed Checkpoints' FROM Metric WHERE `aws.kinesisanalytics.Application` = '${local.flink_app_name}' SINCE 6 hours ago TIMESERIES AUTO"
      }
    }

    widget_billboard {
      title  = "Flink Full Restarts (24 h)"
      row    = 8
      column = 9
      width  = 4
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT sum(`aws.kinesisanalytics.fullRestarts`) AS 'Full Restarts' FROM Metric WHERE `aws.kinesisanalytics.Application` = '${local.flink_app_name}' SINCE 24 hours ago"
      }
    }

    widget_line {
      title  = "Flink CPU Utilization"
      row    = 11
      column = 1
      width  = 6
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT average(`aws.kinesisanalytics.cpuUtilization`) AS 'CPU %' FROM Metric WHERE `aws.kinesisanalytics.Application` = '${local.flink_app_name}' SINCE 6 hours ago TIMESERIES AUTO"
      }
    }

    widget_line {
      title  = "Flink Heap Memory Utilization"
      row    = 11
      column = 7
      width  = 6
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT average(`aws.kinesisanalytics.heapMemoryUtilization`) AS 'Heap %' FROM Metric WHERE `aws.kinesisanalytics.Application` = '${local.flink_app_name}' SINCE 6 hours ago TIMESERIES AUTO"
      }
    }

    # ── Iceberg Commit Metrics ────────────────────────────────────────────────

    widget_markdown {
      title  = ""
      row    = 14
      column = 1
      width  = 12
      height = 1
      text   = "## Flink Application Metrics"
    }

    widget_line {
      title  = "Iceberg Commit Success"
      row    = 15
      column = 1
      width  = 6
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT count(*) AS 'Commits' FROM Metric WHERE tableId = '${var.glue_catalog_db_name}.${var.glue_catalog_db_name}_log_federated' AND metricName = 'iceberg.commit.success' SINCE 1 hour ago TIMESERIES AUTO"
      }
    }

    widget_line {
      title  = "Iceberg Commit E2E Latency (ms)"
      row    = 15
      column = 7
      width  = 6
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT average(`iceberg.commit.e2e_latency_ms`) AS 'E2E Latency (ms)' FROM Metric WHERE tableId = '${var.glue_catalog_db_name}.${var.glue_catalog_db_name}_log_federated' SINCE 1 hour ago TIMESERIES AUTO"
      }
    }

    widget_line {
      title  = "Iceberg Commit Duration (ms)"
      row    = 18
      column = 1
      width  = 4
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT average(`iceberg.commit.duration_ms`) AS 'Commit Duration (ms)' FROM Metric WHERE tableId = '${var.glue_catalog_db_name}.${var.glue_catalog_db_name}_log_federated' SINCE 1 hour ago TIMESERIES AUTO"
      }
    }

    widget_line {
      title  = "Iceberg Batch Processing Latency (ms)"
      row    = 18
      column = 5
      width  = 4
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT average(`iceberg.commit.batch_processing_latency_ms`) AS 'Batch Latency (ms)' FROM Metric WHERE tableId = '${var.glue_catalog_db_name}.${var.glue_catalog_db_name}_log_federated' SINCE 1 hour ago TIMESERIES AUTO"
      }
    }

    widget_line {
      title  = "Iceberg Commit File Count"
      row    = 18
      column = 9
      width  = 4
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT average(`iceberg.commit.file_count`) AS 'Files per Commit' FROM Metric WHERE tableId = '${var.glue_catalog_db_name}.${var.glue_catalog_db_name}_log_federated' SINCE 1 hour ago TIMESERIES AUTO"
      }
    }
  }

  # ══════════════════════════════════════════════════════════════════════════
  # Page 3 — Storage & Events (S3 + EventBridge)
  # ══════════════════════════════════════════════════════════════════════════
  page {
    name = "Data Storage - S3"

    widget_line {
      title  = "S3 Request Activity (GET / PUT / HEAD)"
      row    = 1
      column = 1
      width  = 6
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT sum(`aws.s3.GetRequests`) AS 'GET', sum(`aws.s3.PutRequests`) AS 'PUT', sum(`aws.s3.HeadRequests`) AS 'HEAD' FROM Metric WHERE `aws.s3.BucketName` = '${var.s3_bucket_name}' SINCE 1 hour ago TIMESERIES AUTO"
      }
    }

    widget_line {
      title  = "S3 Bytes Transferred"
      row    = 1
      column = 7
      width  = 6
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT sum(`aws.s3.BytesDownloaded`) AS 'Downloaded (bytes)', sum(`aws.s3.BytesUploaded`) AS 'Uploaded (bytes)' FROM Metric WHERE `aws.s3.BucketName` = '${var.s3_bucket_name}' SINCE 1 hour ago TIMESERIES AUTO"
      }
    }

    widget_line {
      title  = "S3 Request Latency"
      row    = 4
      column = 1
      width  = 12
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT average(`aws.s3.TotalRequestLatency`) AS 'Average latency (ms)' FROM Metric WHERE `aws.s3.BucketName` = '${var.s3_bucket_name}' SINCE 1 hour ago TIMESERIES AUTO"
      }
    }

    widget_line {
      title  = "S3 Bucket Size"
      row    = 7
      column = 1
      width  = 6
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT average(`aws.s3.BucketSizeBytes`) / 1073741824 AS 'Bucket Size (GB)' FROM Metric WHERE `aws.s3.BucketName` = '${var.s3_bucket_name}' SINCE 7 days ago TIMESERIES 1 day"
      }
    }

    widget_line {
      title  = "S3 Object Count"
      row    = 7
      column = 7
      width  = 6
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT average(`aws.s3.NumberOfObjects`) AS 'Objects' FROM Metric WHERE `aws.s3.BucketName` = '${var.s3_bucket_name}' SINCE 7 days ago TIMESERIES 1 day"
      }
    }

    /* EventBridge widgets — uncomment when EventBridge metrics are needed

    widget_line {
      title  = "EventBridge — Parquet Events Routed"
      row    = 7
      column = 1
      width  = 6
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT sum(`aws.events.TriggeredRules`) AS 'Triggered', sum(`aws.events.MatchedEvents`) AS 'Matched' FROM Metric WHERE `aws.events.RuleName` = '${local.eventbridge_rule_name}' SINCE 6 hours ago TIMESERIES AUTO"
      }
    }

    widget_line {
      title  = "EventBridge — Failed Invocations"
      row    = 7
      column = 7
      width  = 6
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT sum(`aws.events.FailedInvocations`) AS 'Failed', sum(`aws.events.ThrottledRules`) AS 'Throttled' FROM Metric WHERE `aws.events.RuleName` = '${local.eventbridge_rule_name}' SINCE 6 hours ago TIMESERIES AUTO"
      }
    }

    */
  }

  # ══════════════════════════════════════════════════════════════════════════
  # Page 4 — Glue & Optimizer Health
  # ══════════════════════════════════════════════════════════════════════════
  page {
    name = "Glue & Optimizer Health"

    widget_billboard {
      title  = "Compaction (24 h)"
      row    = 1
      column = 1
      width  = 4
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT sum(`aws.glue.Iceberg table compaction success`) AS 'Success', sum(`aws.glue.Iceberg table compaction failure`) AS 'Failures' FROM Metric WHERE `aws.glue.DATABASE_NAME` = '${var.glue_catalog_db_name}' SINCE 24 hours ago"
      }
    }

    widget_billboard {
      title  = "Retention (24 h)"
      row    = 1
      column = 5
      width  = 4
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT sum(`aws.glue.Iceberg table retention success`) AS 'Success', sum(`aws.glue.Iceberg table retention failure`) AS 'Failures' FROM Metric WHERE `aws.glue.DATABASE_NAME` = '${var.glue_catalog_db_name}' SINCE 24 hours ago"
      }
    }

    widget_billboard {
      title  = "Orphan Deletion (24 h)"
      row    = 1
      column = 9
      width  = 4
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT sum(`aws.glue.Iceberg table orphan_file_deletion success`) AS 'Success', sum(`aws.glue.Iceberg table orphan_file_deletion failure`) AS 'Failures' FROM Metric WHERE `aws.glue.DATABASE_NAME` = '${var.glue_catalog_db_name}' SINCE 24 hours ago"
      }
    }

    widget_line {
      title  = "Optimizer Failure Trend"
      row    = 4
      column = 1
      width  = 12
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT sum(`aws.glue.Iceberg table compaction failure`) AS 'Compaction', sum(`aws.glue.Iceberg table retention failure`) AS 'Retention', sum(`aws.glue.Iceberg table orphan_file_deletion failure`) AS 'Orphan Deletion' FROM Metric WHERE `aws.glue.DATABASE_NAME` = '${var.glue_catalog_db_name}' SINCE 7 days ago TIMESERIES AUTO"
      }
    }

    widget_line {
      title  = "Retention Job — Execution Time"
      row    = 7
      column = 1
      width  = 6
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT average(`aws.glue.Duration of job (hours)`) * 3600 AS 'Duration (s)' FROM Metric WHERE `aws.glue.DATABASE_NAME` = '${var.glue_catalog_db_name}' AND metricName = 'aws.glue.Duration of job (hours)' SINCE 7 days ago TIMESERIES 1 day"
      }
    }

    widget_bar {
      title  = "Retention Job Runs — Success vs Failure"
      row    = 7
      column = 7
      width  = 6
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT sum(`aws.glue.Iceberg table retention success`) AS 'Success', sum(`aws.glue.Iceberg table retention failure`) AS 'Failures' FROM Metric WHERE `aws.glue.DATABASE_NAME` = '${var.glue_catalog_db_name}' SINCE 30 days ago TIMESERIES 1 day"
      }
    }
  }
}
