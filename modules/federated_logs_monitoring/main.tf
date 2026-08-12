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
      height = 2
      text   = <<-EOT
        ## Federated Logs — ${var.setup_name}
        AWS infrastructure monitoring for New Relic Federated Logs.
        **S3:** `${var.s3_bucket_name}` | **Glue DB:** `${var.glue_catalog_db_name}` | **EventBridge:** `${local.eventbridge_rule_name}`
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
        query      = "SELECT latest(`aws.sqs.ApproximateNumberOfMessagesVisible`) AS 'Messages' FROM Metric WHERE `aws.sqs.QueueName` = '${local.sqs_queue_name}' SINCE 5 minutes ago"
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
        query      = "SELECT latest(`aws.sqs.ApproximateNumberOfMessagesVisible`) AS 'Messages' FROM Metric WHERE `aws.sqs.QueueName` = '${local.sqs_dlq_name}' SINCE 5 minutes ago"
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
        query      = "SELECT latest(`aws.s3.BucketSizeBytes`) / 1073741824 AS 'Size (GB)' FROM Metric WHERE `aws.s3.BucketName` = '${var.s3_bucket_name}' SINCE 2 days ago"
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

      warning  = 1
      critical = 5
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
        query      = "SELECT latest(`aws.kinesisanalytics.uptime`) / 60000 AS 'Uptime (min)' FROM Metric WHERE `aws.kinesisanalytics.Application` = '${local.flink_app_name}' SINCE 3 hours ago TIMESERIES AUTO"
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
        query      = "SELECT sum(`aws.sqs.NumberOfMessagesSent`) AS 'Sent' FROM Metric WHERE `aws.sqs.QueueName` = '${local.sqs_queue_name}' SINCE 6 hours ago TIMESERIES AUTO"
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
        query      = "SELECT average(`aws.sqs.ApproximateNumberOfMessagesVisible`) AS 'Visible', average(`aws.sqs.ApproximateNumberOfMessagesNotVisible`) AS 'In-Flight' FROM Metric WHERE `aws.sqs.QueueName` = '${local.sqs_queue_name}' SINCE 6 hours ago TIMESERIES AUTO"
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
        query      = "SELECT max(`aws.sqs.ApproximateAgeOfOldestMessage`) AS 'Age (s)' FROM Metric WHERE `aws.sqs.QueueName` = '${local.sqs_queue_name}' SINCE 6 hours ago TIMESERIES AUTO"
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
        query      = "SELECT average(`aws.sqs.ApproximateNumberOfMessagesVisible`) AS 'DLQ Visible' FROM Metric WHERE `aws.sqs.QueueName` = '${local.sqs_dlq_name}' SINCE 6 hours ago TIMESERIES AUTO"
      }
    }

    widget_line {
      title  = "Flink Uptime vs Downtime"
      row    = 7
      column = 1
      width  = 4
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT latest(`aws.kinesisanalytics.uptime`) / 60000 AS 'Uptime (min)', latest(`aws.kinesisanalytics.downtime`) / 60000 AS 'Downtime (min)' FROM Metric WHERE `aws.kinesisanalytics.Application` = '${local.flink_app_name}' SINCE 6 hours ago TIMESERIES AUTO"
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
        query      = "SELECT max(`aws.kinesisanalytics.lastCheckpointDuration`) AS 'Last Checkpoint (ms)', sum(`aws.kinesisanalytics.numberOfFailedCheckpoints`) AS 'Failed Checkpoints' FROM Metric WHERE `aws.kinesisanalytics.Application` = '${local.flink_app_name}' SINCE 6 hours ago TIMESERIES AUTO"
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
        query      = "SELECT sum(`aws.kinesisanalytics.fullRestarts`) AS 'Full Restarts' FROM Metric WHERE `aws.kinesisanalytics.Application` = '${local.flink_app_name}' SINCE 24 hours ago"
      }

      warning  = 1
      critical = 3
    }

    widget_line {
      title  = "Flink CPU Utilization"
      row    = 10
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
      row    = 10
      column = 7
      width  = 6
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT average(`aws.kinesisanalytics.heapMemoryUtilization`) AS 'Heap %' FROM Metric WHERE `aws.kinesisanalytics.Application` = '${local.flink_app_name}' SINCE 6 hours ago TIMESERIES AUTO"
      }
    }
  }

  # ══════════════════════════════════════════════════════════════════════════
  # Page 3 — Storage & Events (S3 + EventBridge)
  # ══════════════════════════════════════════════════════════════════════════
  page {
    name = "Data Storage - S3 & EventBridge"

    widget_line {
      title  = "S3 Bucket Size"
      row    = 1
      column = 1
      width  = 6
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT latest(`aws.s3.BucketSizeBytes`) / 1073741824 AS 'Bucket Size (GB)' FROM Metric WHERE `aws.s3.BucketName` = '${var.s3_bucket_name}' SINCE 7 days ago TIMESERIES 1 day"
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
        query      = "SELECT latest(`aws.s3.NumberOfObjects`) AS 'Objects' FROM Metric WHERE `aws.s3.BucketName` = '${var.s3_bucket_name}' SINCE 7 days ago TIMESERIES 1 day"
      }
    }

    widget_line {
      title  = "S3 Request Activity"
      row    = 4
      column = 1
      width  = 12
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT sum(`aws.s3.GetRequests`) AS 'GET', sum(`aws.s3.PutRequests`) AS 'PUT', sum(`aws.s3.HeadRequests`) AS 'HEAD', sum(`aws.s3.DeleteRequests`) AS 'DELETE' FROM Metric WHERE `aws.s3.BucketName` = '${var.s3_bucket_name}' SINCE 6 hours ago TIMESERIES AUTO"
      }
    }

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
  }

  # ══════════════════════════════════════════════════════════════════════════
  # Page 4 — Glue & Optimizer Health
  # ══════════════════════════════════════════════════════════════════════════
  page {
    name = "Glue & Optimizer Health"

    widget_billboard {
      title  = "Compaction Failures (24 h)"
      row    = 1
      column = 1
      width  = 4
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT sum(`aws.glue.Iceberg table compaction failure`) AS 'Failures' FROM Metric WHERE `aws.glue.DATABASE_NAME` = '${var.glue_catalog_db_name}' SINCE 24 hours ago"
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
        query      = "SELECT sum(`aws.glue.Iceberg table retention failure`) AS 'Failures' FROM Metric WHERE `aws.glue.DATABASE_NAME` = '${var.glue_catalog_db_name}' SINCE 24 hours ago"
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
        query      = "SELECT sum(`aws.glue.Iceberg table orphan_file_deletion failure`) AS 'Failures' FROM Metric WHERE `aws.glue.DATABASE_NAME` = '${var.glue_catalog_db_name}' SINCE 24 hours ago"
      }

      warning  = 1
      critical = 3
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
        query      = "SELECT average(`aws.glue.glue.driver.aggregate.elapsedTime`) / 1000 AS 'Duration (s)' FROM Metric WHERE `aws.glue.JobName` = '${local.glue_retention_job}' AND `aws.glue.JobRunId` = 'ALL' SINCE 7 days ago TIMESERIES 1 day"
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
        query      = "SELECT sum(`aws.glue.glue.driver.aggregate.numCompletedStages`) AS 'Succeeded', sum(`aws.glue.glue.driver.aggregate.numFailedTasks`) AS 'Failed' FROM Metric WHERE `aws.glue.JobName` = '${local.glue_retention_job}' AND `aws.glue.JobRunId` = 'ALL' SINCE 30 days ago FACET cases(WHERE `aws.glue.glue.driver.aggregate.numFailedTasks` > 0 AS 'Failed', WHERE `aws.glue.glue.driver.aggregate.numCompletedStages` > 0 AS 'Succeeded')"
      }
    }
  }
}
