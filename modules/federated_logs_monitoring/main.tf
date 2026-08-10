locals {
  sqs_queue_name = var.sqs_queue_name
  sqs_dlq_name   = var.sqs_dlq_name
  flink_app_name = var.flink_application_name

  glue_prefix           = "newrelic_fed_logs_${var.setup_name}"
  eventbridge_rule_name = "newrelic-fed-logs-${var.setup_name}-iceberg-file-created"
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
      height = 2
      text   = <<-EOT
        ## Federated Logs — ${var.setup_name}
        AWS infrastructure monitoring for New Relic Federated Logs.
        **S3:** `${var.s3_bucket_name}` | **Glue DB:** `${var.glue_catalog_db_name}` | **EventBridge:** `${local.eventbridge_rule_name}`${local.pipeline_note}
      EOT
    }

    # ── Row 2: key health billboards ──────────────────────────────────────

    widget_billboard {
      title  = "SQS Queue Depth"
      row    = 3
      column = 1
      width  = 3
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT latest(ApproximateNumberOfMessagesVisible) AS 'Messages' FROM SqsQueueSample WHERE queueName = '${local.sqs_queue_name}' SINCE 5 minutes ago"
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
        query      = "SELECT latest(ApproximateNumberOfMessagesVisible) AS 'Messages' FROM SqsQueueSample WHERE queueName = '${local.sqs_dlq_name}' SINCE 5 minutes ago"
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
        query = "SELECT latest(bucketSizeBytes) / 1073741824 AS 'Size (GB)' FROM DatastoreSample WHERE provider = 'S3BucketSample' AND bucketName = '${var.s3_bucket_name}' SINCE 2 days ago"
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
        query = "SELECT sum(`Iceberg table compaction failure`) + sum(`Iceberg table retention failure`) + sum(`Iceberg table orphan_file_deletion failure`) AS 'Failures' FROM Metric WHERE DATABASE_NAME = '${var.glue_catalog_db_name}' SINCE 24 hours ago"
      }

      warning  = 1
      critical = 5
    }

    # ── Row 3: throughput overview ─────────────────────────────────────────

    widget_line {
      title  = "SQS Throughput — Messages Sent & Deleted"
      row    = 6
      column = 1
      width  = 6
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT sum(NumberOfMessagesSent) AS 'Sent', sum(NumberOfMessagesDeleted) AS 'Deleted' FROM SqsQueueSample WHERE queueName = '${local.sqs_queue_name}' SINCE 3 hours ago TIMESERIES AUTO"
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
        # uptime is in milliseconds; divide to get minutes.
        query = "SELECT latest(uptime) / 60000 AS 'Uptime (min)' FROM KinesisAnalyticsApplicationSample WHERE applicationName = '${local.flink_app_name}' SINCE 3 hours ago TIMESERIES AUTO"
      }
    }
  }

  # ══════════════════════════════════════════════════════════════════════════
  # Page 2 — Event Pipeline (SQS + Flink)
  # ══════════════════════════════════════════════════════════════════════════
  page {
    name = "Event Pipeline"

    # ── Row 1: queue volume ────────────────────────────────────────────────

    widget_line {
      title  = "Messages Sent to Queue"
      row    = 1
      column = 1
      width  = 6
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT sum(NumberOfMessagesSent) AS 'Sent' FROM SqsQueueSample WHERE queueName = '${local.sqs_queue_name}' SINCE 6 hours ago TIMESERIES AUTO"
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
        query      = "SELECT average(ApproximateNumberOfMessagesVisible) AS 'Visible', average(ApproximateNumberOfMessagesNotVisible) AS 'In-Flight' FROM SqsQueueSample WHERE queueName = '${local.sqs_queue_name}' SINCE 6 hours ago TIMESERIES AUTO"
      }
    }

    # ── Row 2: queue age & DLQ ─────────────────────────────────────────────

    widget_line {
      title  = "Oldest Message Age"
      row    = 4
      column = 1
      width  = 6
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT max(ApproximateAgeOfOldestMessage) AS 'Age (s)' FROM SqsQueueSample WHERE queueName = '${local.sqs_queue_name}' SINCE 6 hours ago TIMESERIES AUTO"
      }
    }

    widget_line {
      title  = "Dead Letter Queue Depth"
      row    = 4
      column = 7
      width  = 6
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT average(ApproximateNumberOfMessagesVisible) AS 'DLQ Visible' FROM SqsQueueSample WHERE queueName = '${local.sqs_dlq_name}' SINCE 6 hours ago TIMESERIES AUTO"
      }
    }

    # ── Row 3: Flink health ────────────────────────────────────────────────

    widget_line {
      title  = "Flink Uptime vs Downtime"
      row    = 7
      column = 1
      width  = 4
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT latest(uptime) / 60000 AS 'Uptime (min)', latest(downtime) / 60000 AS 'Downtime (min)' FROM KinesisAnalyticsApplicationSample WHERE applicationName = '${local.flink_app_name}' SINCE 6 hours ago TIMESERIES AUTO"
      }
    }

    widget_line {
      title  = "Flink Checkpoint Duration"
      row    = 7
      column = 5
      width  = 4
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT max(lastCheckpointDuration) AS 'Last Checkpoint (ms)', sum(numberOfFailedCheckpoints) AS 'Failed Checkpoints' FROM KinesisAnalyticsApplicationSample WHERE applicationName = '${local.flink_app_name}' SINCE 6 hours ago TIMESERIES AUTO"
      }
    }

    widget_billboard {
      title  = "Flink Full Restarts (24 h)"
      row    = 7
      column = 9
      width  = 4
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT sum(fullRestarts) AS 'Full Restarts' FROM KinesisAnalyticsApplicationSample WHERE applicationName = '${local.flink_app_name}' SINCE 24 hours ago"
      }

      warning  = 1
      critical = 3
    }

    # ── Row 4: Flink resource utilization ──────────────────────────────────

    widget_line {
      title  = "Flink CPU Utilization"
      row    = 10
      column = 1
      width  = 6
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT average(cpuUtilization) AS 'CPU %' FROM KinesisAnalyticsApplicationSample WHERE applicationName = '${local.flink_app_name}' SINCE 6 hours ago TIMESERIES AUTO"
      }
    }

    widget_line {
      title  = "Flink Heap Memory Utilization"
      row    = 10
      column = 7
      width  = 6
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT average(heapMemoryUtilization) AS 'Heap %' FROM KinesisAnalyticsApplicationSample WHERE applicationName = '${local.flink_app_name}' SINCE 6 hours ago TIMESERIES AUTO"
      }
    }
  }

  # ══════════════════════════════════════════════════════════════════════════
  # Page 3 — Storage & Event Routing (S3 + EventBridge)
  # ══════════════════════════════════════════════════════════════════════════
  page {
    name = "Storage & Events"

    # ── Row 1: S3 storage ─────────────────────────────────────────────────

    widget_line {
      title  = "S3 Bucket Size"
      row    = 1
      column = 1
      width  = 6
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query = "SELECT latest(bucketSizeBytes) / 1073741824 AS 'Bucket Size (GB)' FROM DatastoreSample WHERE provider = 'S3BucketSample' AND bucketName = '${var.s3_bucket_name}' SINCE 7 days ago TIMESERIES 1 day"
      }
    }

    widget_line {
      title  = "S3 Object Count"
      row    = 1
      column = 7
      width  = 6
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query = "SELECT latest(numberOfObjects) AS 'Objects' FROM DatastoreSample WHERE provider = 'S3BucketSample' AND bucketName = '${var.s3_bucket_name}' SINCE 7 days ago TIMESERIES 1 day"
      }
    }

    # ── Row 2: EventBridge routing ─────────────────────────────────────────

    widget_line {
      title  = "EventBridge — Parquet Events Routed"
      row    = 4
      column = 1
      width  = 6
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        # TriggeredRules: events matched and forwarded to the SQS target.
        query = "SELECT sum(TriggeredRules) AS 'Triggered', sum(MatchedEvents) AS 'Matched' FROM Metric WHERE metricName IN ('TriggeredRules', 'MatchedEvents') AND RuleName = '${local.eventbridge_rule_name}' SINCE 6 hours ago TIMESERIES AUTO"
      }
    }

    widget_line {
      title  = "EventBridge — Failed Invocations"
      row    = 4
      column = 7
      width  = 6
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT sum(FailedInvocations) AS 'Failed', sum(ThrottledRules) AS 'Throttled' FROM Metric WHERE metricName IN ('FailedInvocations', 'ThrottledRules') AND RuleName = '${local.eventbridge_rule_name}' SINCE 6 hours ago TIMESERIES AUTO"
      }
    }

    # ── Row 3: S3 request activity ─────────────────────────────────────────

    widget_line {
      title  = "S3 Request Activity"
      row    = 7
      column = 1
      width  = 12
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        # S3 request metrics require request metrics to be enabled on the bucket.
        query = "SELECT sum(AllRequests) AS 'Total', sum(PutRequests) AS 'PUT', sum(GetRequests) AS 'GET', sum(4xxErrors) AS '4xx Errors', sum(5xxErrors) AS '5xx Errors' FROM Metric WHERE metricName IN ('AllRequests', 'PutRequests', 'GetRequests', '4xxErrors', '5xxErrors') AND BucketName = '${var.s3_bucket_name}' SINCE 6 hours ago TIMESERIES AUTO"
      }
    }
  }

  # ══════════════════════════════════════════════════════════════════════════
  # Page 4 — Glue & Optimizer Health
  # ══════════════════════════════════════════════════════════════════════════
  page {
    name = "Glue & Optimizer Health"

    # ── Row 1: failure summary billboards ─────────────────────────────────

    widget_billboard {
      title  = "Compaction Failures (24 h)"
      row    = 1
      column = 1
      width  = 4
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT sum(`Iceberg table compaction failure`) AS 'Failures' FROM Metric WHERE DATABASE_NAME = '${var.glue_catalog_db_name}' SINCE 24 hours ago"
      }

      warning  = 1
      critical = 3
    }

    widget_billboard {
      title  = "Retention Failures (24 h)"
      row    = 1
      column = 5
      width  = 4
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT sum(`Iceberg table retention failure`) AS 'Failures' FROM Metric WHERE DATABASE_NAME = '${var.glue_catalog_db_name}' SINCE 24 hours ago"
      }

      warning  = 1
      critical = 3
    }

    widget_billboard {
      title  = "Orphan Deletion Failures (24 h)"
      row    = 1
      column = 9
      width  = 4
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT sum(`Iceberg table orphan_file_deletion failure`) AS 'Failures' FROM Metric WHERE DATABASE_NAME = '${var.glue_catalog_db_name}' SINCE 24 hours ago"
      }

      warning  = 1
      critical = 3
    }

    # ── Row 2: failure trends ──────────────────────────────────────────────

    widget_line {
      title  = "Optimizer Failure Trend"
      row    = 4
      column = 1
      width  = 12
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT sum(`Iceberg table compaction failure`) AS 'Compaction', sum(`Iceberg table retention failure`) AS 'Retention', sum(`Iceberg table orphan_file_deletion failure`) AS 'Orphan Deletion' FROM Metric WHERE DATABASE_NAME = '${var.glue_catalog_db_name}' SINCE 7 days ago TIMESERIES AUTO"
      }
    }

    # ── Row 3: Glue job metrics ────────────────────────────────────────────

    widget_line {
      title  = "Retention Job — Execution Time"
      row    = 7
      column = 1
      width  = 6
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query = "SELECT average(`glue.driver.aggregate.elapsedTime`) / 1000 AS 'Duration (s)' FROM Metric WHERE JobName = '${local.glue_retention_job}' SINCE 7 days ago TIMESERIES 1 day"
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
        query      = "SELECT sum(`glue.driver.aggregate.numCompletedStages`) AS 'Succeeded', sum(`glue.driver.aggregate.numFailedStages`) AS 'Failed' FROM Metric WHERE JobName = '${local.glue_retention_job}' SINCE 30 days ago FACET cases(WHERE `glue.driver.aggregate.numFailedStages` > 0 AS 'Failed', WHERE `glue.driver.aggregate.numCompletedStages` > 0 AS 'Succeeded')"
      }
    }
  }
}
