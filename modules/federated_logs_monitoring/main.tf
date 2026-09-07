resource "newrelic_one_dashboard" "this" {
  name        = local.dashboard_name
  permissions = "public_read_only"
  account_id  = var.newrelic_account_id

  dynamic "variable" {
    for_each = length(var.partition_table_ids) > 0 ? [1] : []
    content {
      name                 = "table_id"
      title                = "Partition"
      type                 = "enum"
      is_multi_selection   = false
      replacement_strategy = "default"

      dynamic "item" {
        for_each = var.partition_table_ids
        content {
          title = item.value   # "Log_Federated", "Log_Application" etc.
          value = item.key     # full tableId "database.table"
        }
      }

      default_values = ["${var.glue_catalog_db_name}.${var.glue_catalog_db_name}_log_federated"]
    }
  }

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
      title  = "PCG Backpressure"
      row    = 3
      column = 7
      width  = 3
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT latest(pcg_backpressure_active) AS 'Backpressure' FROM Metric WHERE service.name = 'pipeline-control-gateway' AND clusterName = '${var.pcg_cluster_name}' SINCE 5 minutes ago"
      }

      critical = 0.5
    }

    widget_billboard {
      title  = "Glue Optimizer Failures"
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
      title  = "Iceberg Commit Activity"
      row    = 6
      column = 7
      width  = 6
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT filter(count(iceberg.commit.success), WHERE iceberg.commit.success = 1) AS 'Commits', filter(count(iceberg.commit.success), WHERE iceberg.commit.success = 0) AS 'Failures' FROM Metric WHERE service.name = 'flink-iceberg-commit-worker' AND tableId = {{table_id}} SINCE 3 hours ago TIMESERIES AUTO"
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
      title  = "Flink Full Restarts"
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
        query      = "SELECT count(*) AS 'Commits' FROM Metric WHERE tableId = {{table_id}} AND metricName = 'iceberg.commit.success' SINCE 1 hour ago TIMESERIES AUTO"
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
        query      = "SELECT average(`iceberg.commit.e2e_latency_ms`) AS 'E2E Latency (ms)' FROM Metric WHERE tableId = {{table_id}} SINCE 1 hour ago TIMESERIES AUTO"
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
        query      = "SELECT average(`iceberg.commit.duration_ms`) AS 'Commit Duration (ms)' FROM Metric WHERE tableId = {{table_id}} SINCE 1 hour ago TIMESERIES AUTO"
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
        query      = "SELECT average(`iceberg.commit.batch_processing_latency_ms`) AS 'Batch Latency (ms)' FROM Metric WHERE tableId = {{table_id}} SINCE 1 hour ago TIMESERIES AUTO"
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
        query      = "SELECT average(`iceberg.commit.file_count`) AS 'Files per Commit' FROM Metric WHERE tableId = {{table_id}} SINCE 1 hour ago TIMESERIES AUTO"
      }
    }
  }

  # ══════════════════════════════════════════════════════════════════════════
  # Page 3 — Storage & Events (S3 + EventBridge)
  # ══════════════════════════════════════════════════════════════════════════
  page {
    name = "Data Storage - S3 & EventBridge"

    /* S3 request metrics — uncomment after enabling S3 request metrics on the bucket
       (AWS Console → S3 → bucket → Metrics → Request metrics → Create filter)
       Equivalent metrics are available on the PCG Metrics page for free.

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

    widget_bar {
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

    */

    widget_area {
      title  = "S3 Bucket Size"
      row    = 1
      column = 1
      width  = 6
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT average(`aws.s3.BucketSizeBytes`) / 1073741824 AS 'Bucket Size (GB)' FROM Metric WHERE `aws.s3.BucketName` = '${var.s3_bucket_name}' SINCE 7 days ago TIMESERIES 1 day"
      }
    }

    widget_area {
      title  = "S3 Object Count"
      row    = 1
      column = 7
      width  = 6
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT average(`aws.s3.NumberOfObjects`) AS 'Objects' FROM Metric WHERE `aws.s3.BucketName` = '${var.s3_bucket_name}' SINCE 7 days ago TIMESERIES 1 day"
      }
    }

    widget_line {
      title  = "EventBridge — Parquet Events Routed"
      row    = 4
      column = 1
      width  = 6
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT sum(`aws.events.TriggeredRules`) AS 'Triggered', sum(`aws.events.MatchedEvents`) AS 'Matched' FROM Metric WHERE `aws.events.RuleName` = '${local.eventbridge_rule_name}' SINCE 6 hours ago TIMESERIES AUTO"
      }
    }

    widget_line {
      title  = "EventBridge — Success vs Failed Invocations"
      row    = 4
      column = 7
      width  = 6
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT sum(`aws.events.SuccessfulInvocationAttempts`) AS 'Succeeded', sum(`aws.events.FailedInvocations`) AS 'Failed' FROM Metric WHERE `aws.events.RuleName` = '${local.eventbridge_rule_name}' SINCE 6 hours ago TIMESERIES AUTO"
      }
    }

    widget_line {
      title  = "EventBridge — S3 to SQS Delivery Latency (ms)"
      row    = 7
      column = 1
      width  = 12
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT average(`aws.events.IngestionToInvocationSuccessLatency`) AS 'S3→SQS Latency (ms)' FROM Metric WHERE `aws.events.RuleName` = '${local.eventbridge_rule_name}' SINCE 6 hours ago TIMESERIES AUTO"
      }
    }
  }

  # ══════════════════════════════════════════════════════════════════════════
  # Page 4 — Glue & Optimizer Health
  # ══════════════════════════════════════════════════════════════════════════
  page {
    name = "Glue & Optimizer Health"

    widget_billboard {
      title  = "Compaction"
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
      title  = "Retention"
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
      title  = "Orphan Deletion"
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
        query      = "SELECT average(`aws.glue.Duration of job (hours)`) * 3600 AS 'Duration (s)' FROM Metric WHERE `aws.glue.DATABASE_NAME` = '${var.glue_catalog_db_name}' AND metricName = 'aws.glue.Duration of job (hours)' SINCE 7 days ago TIMESERIES AUTO"
      }
    }

    widget_line {
      title  = "Optimizer Impact — Files Processed"
      row    = 7
      column = 7
      width  = 6
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT sum(`aws.glue.Number of files compacted`) AS 'Files Compacted', sum(`aws.glue.Number of data files removed`) AS 'Files Removed (Retention)', sum(`aws.glue.Number of orphan files deleted`) AS 'Orphan Files Deleted' FROM Metric WHERE `aws.glue.DATABASE_NAME` = '${var.glue_catalog_db_name}' SINCE 7 days ago TIMESERIES AUTO"
      }
    }
  }

  # ══════════════════════════════════════════════════════════════════════════
  # Page 5 — PCG Metrics (only when pcg_cluster_name is provided)
  # ══════════════════════════════════════════════════════════════════════════
  page {
    name = "PCG Metrics"

      # ── Section 1: Health Snapshot ────────────────────────────────────────

      widget_billboard {
        title  = "Backpressure Active"
        row    = 1
        column = 1
        width  = 3
        height = 3

        nrql_query {
          account_id = var.newrelic_account_id
          query      = "SELECT latest(pcg_backpressure_active) AS 'Backpressure' FROM Metric WHERE service.name = 'pipeline-control-gateway' AND clusterName = '${var.pcg_cluster_name}' FACET podName SINCE 5 minutes ago"
        }

        critical = 0.5
      }

      widget_billboard {
        title  = "CPU Utilization (%)"
        row    = 1
        column = 4
        width  = 3
        height = 3

        nrql_query {
          account_id = var.newrelic_account_id
          query      = "SELECT latest(pcg_instance_cpu_utilization) * 100 AS 'CPU %' FROM Metric WHERE service.name = 'pipeline-control-gateway' AND clusterName = '${var.pcg_cluster_name}' FACET podName SINCE 5 minutes ago"
        }

        warning  = 70
        critical = 85
      }

      widget_billboard {
        title  = "Memory Utilization (%)"
        row    = 1
        column = 7
        width  = 3
        height = 3

        nrql_query {
          account_id = var.newrelic_account_id
          query      = "SELECT latest(pcg_instance_memory_utilization) * 100 AS 'Memory %' FROM Metric WHERE service.name = 'pipeline-control-gateway' AND clusterName = '${var.pcg_cluster_name}' FACET podName SINCE 5 minutes ago"
        }

        warning  = 60
        critical = 75
      }

      widget_billboard {
        title  = "Ingest Channel Depth"
        row    = 1
        column = 10
        width  = 3
        height = 3

        nrql_query {
          account_id = var.newrelic_account_id
          query      = "SELECT latest(otelcol_icebergexporter_ingest_channel_depth) AS 'Ingest Depth' FROM Metric WHERE service.name = 'pipeline-control-gateway' AND clusterName = '${var.pcg_cluster_name}' FACET podName SINCE 5 minutes ago"
        }

        warning  = 25000
        critical = 40000
      }

      # ── Section 2: Throughput ─────────────────────────────────────────────

      widget_line {
        title  = "Records/sec & Files/min"
        row    = 4
        column = 1
        width  = 6
        height = 3

        nrql_query {
          account_id = var.newrelic_account_id
          query      = "SELECT rate(sum(otelcol_icebergexporter_batch_sent_records), 1 SECOND) AS 'Records/sec', rate(sum(otelcol_icebergexporter_files_written), 1 MINUTE) AS 'Files/min' FROM Metric WHERE service.name = 'pipeline-control-gateway' AND clusterName = '${var.pcg_cluster_name}' SINCE 1 hour ago TIMESERIES AUTO"
        }
      }

      widget_line {
        title  = "Throughput — Incoming vs S3 Written (MB/s)"
        row    = 4
        column = 7
        width  = 6
        height = 3

        nrql_query {
          account_id = var.newrelic_account_id
          query      = "SELECT rate(sum(otelcol_icebergexporter_batch_sent_bytes), 1 SECOND) / 1000000 AS 'Incoming MB/s', rate(sum(otelcol_icebergexporter_s3_bytes_sent), 1 SECOND) / 1000000 AS 'S3 Written MB/s' FROM Metric WHERE service.name = 'pipeline-control-gateway' AND clusterName = '${var.pcg_cluster_name}' SINCE 1 hour ago TIMESERIES AUTO"
        }
      }

      # ── Section 3: Latency ────────────────────────────────────────────────

      widget_line {
        title  = "PCG Total Latency Percentiles (ms)"
        row    = 7
        column = 1
        width  = 6
        height = 3

        nrql_query {
          account_id = var.newrelic_account_id
          query      = "SELECT percentile(otelcol_icebergexporter_pcg_total_latency_ms, 50) AS 'P50', percentile(otelcol_icebergexporter_pcg_total_latency_ms, 95) AS 'P95', percentile(otelcol_icebergexporter_pcg_total_latency_ms, 99) AS 'P99' FROM Metric WHERE service.name = 'pipeline-control-gateway' AND clusterName = '${var.pcg_cluster_name}' SINCE 1 hour ago TIMESERIES AUTO"
        }
      }

      widget_line {
        title  = "S3 Write Latency Percentiles (ms)"
        row    = 7
        column = 7
        width  = 6
        height = 3

        nrql_query {
          account_id = var.newrelic_account_id
          query      = "SELECT percentile(otelcol_icebergexporter_write_latency_ms, 50) AS 'P50', percentile(otelcol_icebergexporter_write_latency_ms, 95) AS 'P95', percentile(otelcol_icebergexporter_write_latency_ms, 99) AS 'P99' FROM Metric WHERE service.name = 'pipeline-control-gateway' AND clusterName = '${var.pcg_cluster_name}' SINCE 1 hour ago TIMESERIES AUTO"
        }
      }

      widget_line {
        title  = "Latency Breakdown by Stage (avg ms)"
        row    = 10
        column = 1
        width  = 12
        height = 3

        nrql_query {
          account_id = var.newrelic_account_id
          query      = "SELECT average(otelcol_icebergexporter_buffering_latency_ms) AS 'Buffering', average(otelcol_icebergexporter_conversion_latency_ms) AS 'Arrow Conversion', average(otelcol_icebergexporter_write_latency_ms) AS 'S3 Write' FROM Metric WHERE service.name = 'pipeline-control-gateway' AND clusterName = '${var.pcg_cluster_name}' SINCE 1 hour ago TIMESERIES AUTO"
        }
      }

      # ── Section 4: Errors & Backpressure ─────────────────────────────────

      widget_line {
        title  = "Backpressure Rejection Rate"
        row    = 13
        column = 1
        width  = 4
        height = 3

        nrql_query {
          account_id = var.newrelic_account_id
          query      = "SELECT rate(sum(pcg_backpressure_rejections_total), 1 SECOND) AS 'Rejections/sec' FROM Metric WHERE service.name = 'pipeline-control-gateway' AND clusterName = '${var.pcg_cluster_name}' SINCE 1 hour ago TIMESERIES AUTO"
        }
      }

      widget_line {
        title  = "Refused Log Records"
        row    = 13
        column = 5
        width  = 4
        height = 3

        nrql_query {
          account_id = var.newrelic_account_id
          query      = "SELECT rate(sum(otelcol_receiver_refused_log_records), 1 SECOND) AS 'Refused/sec' FROM Metric WHERE service.name = 'pipeline-control-gateway' AND clusterName = '${var.pcg_cluster_name}' SINCE 1 hour ago TIMESERIES AUTO"
        }
      }

      widget_pie {
        title  = "Batch Flush Reasons"
        row    = 13
        column = 9
        width  = 4
        height = 3

        nrql_query {
          account_id = var.newrelic_account_id
          query      = "SELECT sum(otelcol_icebergexporter_batches_flushed_by_reason) FROM Metric WHERE service.name = 'pipeline-control-gateway' AND clusterName = '${var.pcg_cluster_name}' FACET flush_reason SINCE 6 hours ago"
        }
      }
    }
}

