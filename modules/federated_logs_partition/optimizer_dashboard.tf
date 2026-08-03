# CloudWatch Dashboard — Glue Iceberg Optimizer Health
#
# One dashboard per setup, scoped to this setup's Glue database.
# Layout: title → Compaction section → Retention section → Orphan File Deletion section.
#
# NOTE: CloudWatch Metrics Insights allows only ONE SELECT expression per widget.
# Every widget below has exactly one SELECT expression.

locals {
  # Reusable Metrics Insights fragment: schema + database filter.
  # Every expression appends its own SELECT prefix in front of this.
  glue_metrics_query = "FROM SCHEMA(\"AWS/Glue\", DATABASE_NAME, TABLE_NAME) WHERE DATABASE_NAME = '${var.glue_catalog_db_name}'"

  # Helper: build a SUM expression for a named metric.
  metric_sum_expressions = {
    for m in [
      "Iceberg table compaction success",
      "Iceberg table compaction failure",
      "Iceberg table compaction number of files compacted",
      "Iceberg table compaction number of bytes compacted",
      "Iceberg table compaction number of DPU allocated to job",
      "Iceberg table compaction duration of job (Hours)",
      "Iceberg table retention success",
      "Iceberg table retention failure",
      "Iceberg table retention number of data files deleted",
      "Iceberg table retention number of manifest files deleted",
      "Iceberg table retention number of manifest lists deleted",
      "Iceberg table retention duration of job (Hours)",
      "Iceberg table orphan_file_deletion success",
      "Iceberg table orphan_file_deletion failure",
      "Iceberg table orphan_file_deletion number of orphan files deleted",
      "Iceberg table orphan_file_deletion duration of job (Hours)",
    ] : m => "SELECT SUM(\"${m}\") ${local.glue_metrics_query}"
  }

  # Average variant — used for duration metrics (avg across concurrent table runs).
  metric_avg_expressions = {
    for m in [
      "Iceberg table compaction duration of job (Hours)",
      "Iceberg table retention duration of job (Hours)",
      "Iceberg table orphan_file_deletion duration of job (Hours)",
    ] : m => "SELECT AVG(\"${m}\") ${local.glue_metrics_query}"
  }
}

resource "aws_cloudwatch_dashboard" "glue_optimizer" {
  dashboard_name = "${local.setup_naming_prefix}_glue_optimizer"

  dashboard_body = jsonencode({
    widgets = [

      # ── Title ────────────────────────────────────────────────────────────
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 3
        properties = {
          markdown = "# Glue Iceberg Optimizer Health — `${var.glue_catalog_db_name}`\nMonitors the 3 automatic Iceberg table optimizers (**compaction**, **retention**, **orphan file deletion**) that keep this setup's federated-log tables healthy."
        }
      },

      # ════════════════════════════════════════════════════════════════════
      # COMPACTION
      # ════════════════════════════════════════════════════════════════════
      {
        type   = "text"
        x      = 0
        y      = 3
        width  = 24
        height = 2
        properties = {
          markdown = "## Compaction\nMerges many small Parquet files into fewer large ones to keep queries fast."
        }
      },
      # Row: runs + DPU
      {
        type   = "metric"
        x      = 0
        y      = 5
        width  = 8
        height = 6
        properties = {
          title  = "Compaction — Successful Runs"
          region = data.aws_region.current.region
          view   = "timeSeries"
          period = 3600
          metrics = [
            [{ expression = local.metric_sum_expressions["Iceberg table compaction success"], id = "m", label = "Success", color = "#2ca02c" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 5
        width  = 8
        height = 6
        properties = {
          title  = "Compaction — Failed Runs"
          region = data.aws_region.current.region
          view   = "timeSeries"
          period = 3600
          metrics = [
            [{ expression = local.metric_sum_expressions["Iceberg table compaction failure"], id = "m", label = "Failure", color = "#d62728" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 5
        width  = 8
        height = 6
        properties = {
          title  = "Compaction — DPU Allocated"
          region = data.aws_region.current.region
          view   = "timeSeries"
          period = 3600
          metrics = [
            [{ expression = local.metric_sum_expressions["Iceberg table compaction number of DPU allocated to job"], id = "m", label = "DPUs" }],
          ]
        }
      },
      # Row: file/byte stats + duration
      {
        type   = "metric"
        x      = 0
        y      = 11
        width  = 8
        height = 6
        properties = {
          title  = "Compaction — Files Compacted"
          region = data.aws_region.current.region
          view   = "timeSeries"
          period = 3600
          metrics = [
            [{ expression = local.metric_sum_expressions["Iceberg table compaction number of files compacted"], id = "m", label = "Files compacted" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 11
        width  = 8
        height = 6
        properties = {
          title  = "Compaction — Bytes Compacted"
          region = data.aws_region.current.region
          view   = "timeSeries"
          period = 3600
          metrics = [
            [{ expression = local.metric_sum_expressions["Iceberg table compaction number of bytes compacted"], id = "m", label = "Bytes compacted" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 11
        width  = 8
        height = 6
        properties = {
          title  = "Compaction — Avg Job Duration (hours)"
          region = data.aws_region.current.region
          view   = "timeSeries"
          period = 3600
          metrics = [
            [{ expression = local.metric_avg_expressions["Iceberg table compaction duration of job (Hours)"], id = "m", label = "Avg duration (hrs)" }],
          ]
        }
      },

      # ════════════════════════════════════════════════════════════════════
      # RETENTION
      # ════════════════════════════════════════════════════════════════════
      {
        type   = "text"
        x      = 0
        y      = 17
        width  = 24
        height = 2
        properties = {
          markdown = "## Snapshot Retention\nDeletes old Iceberg snapshots and their associated data/manifest files beyond the configured retention window."
        }
      },
      # Row: runs + duration
      {
        type   = "metric"
        x      = 0
        y      = 19
        width  = 8
        height = 6
        properties = {
          title  = "Retention — Successful Runs"
          region = data.aws_region.current.region
          view   = "timeSeries"
          period = 3600
          metrics = [
            [{ expression = local.metric_sum_expressions["Iceberg table retention success"], id = "m", label = "Success", color = "#2ca02c" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 19
        width  = 8
        height = 6
        properties = {
          title  = "Retention — Failed Runs"
          region = data.aws_region.current.region
          view   = "timeSeries"
          period = 3600
          metrics = [
            [{ expression = local.metric_sum_expressions["Iceberg table retention failure"], id = "m", label = "Failure", color = "#d62728" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 19
        width  = 8
        height = 6
        properties = {
          title  = "Retention — Avg Job Duration (hours)"
          region = data.aws_region.current.region
          view   = "timeSeries"
          period = 3600
          metrics = [
            [{ expression = local.metric_avg_expressions["Iceberg table retention duration of job (Hours)"], id = "m", label = "Avg duration (hrs)" }],
          ]
        }
      },
      # Row: files deleted (one widget per file type)
      {
        type   = "metric"
        x      = 0
        y      = 25
        width  = 8
        height = 6
        properties = {
          title  = "Retention — Data Files Deleted"
          region = data.aws_region.current.region
          view   = "timeSeries"
          period = 3600
          metrics = [
            [{ expression = local.metric_sum_expressions["Iceberg table retention number of data files deleted"], id = "m", label = "Data files deleted" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 25
        width  = 8
        height = 6
        properties = {
          title  = "Retention — Manifest Files Deleted"
          region = data.aws_region.current.region
          view   = "timeSeries"
          period = 3600
          metrics = [
            [{ expression = local.metric_sum_expressions["Iceberg table retention number of manifest files deleted"], id = "m", label = "Manifest files deleted" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 25
        width  = 8
        height = 6
        properties = {
          title  = "Retention — Manifest Lists Deleted"
          region = data.aws_region.current.region
          view   = "timeSeries"
          period = 3600
          metrics = [
            [{ expression = local.metric_sum_expressions["Iceberg table retention number of manifest lists deleted"], id = "m", label = "Manifest lists deleted" }],
          ]
        }
      },

      # ════════════════════════════════════════════════════════════════════
      # ORPHAN FILE DELETION
      # ════════════════════════════════════════════════════════════════════
      {
        type   = "text"
        x      = 0
        y      = 31
        width  = 24
        height = 2
        properties = {
          markdown = "## Orphan File Deletion\nRemoves leftover S3 files not referenced by any Iceberg snapshot, freeing up storage."
        }
      },
      # Row: runs + files deleted + duration
      {
        type   = "metric"
        x      = 0
        y      = 33
        width  = 8
        height = 6
        properties = {
          title  = "Orphan File Deletion — Successful Runs"
          region = data.aws_region.current.region
          view   = "timeSeries"
          period = 3600
          metrics = [
            [{ expression = local.metric_sum_expressions["Iceberg table orphan_file_deletion success"], id = "m", label = "Success", color = "#2ca02c" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 33
        width  = 8
        height = 6
        properties = {
          title  = "Orphan File Deletion — Failed Runs"
          region = data.aws_region.current.region
          view   = "timeSeries"
          period = 3600
          metrics = [
            [{ expression = local.metric_sum_expressions["Iceberg table orphan_file_deletion failure"], id = "m", label = "Failure", color = "#d62728" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 33
        width  = 8
        height = 6
        properties = {
          title  = "Orphan File Deletion — Files Deleted"
          region = data.aws_region.current.region
          view   = "timeSeries"
          period = 3600
          metrics = [
            [{ expression = local.metric_sum_expressions["Iceberg table orphan_file_deletion number of orphan files deleted"], id = "m", label = "Orphan files deleted" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 39
        width  = 8
        height = 6
        properties = {
          title  = "Orphan File Deletion — Avg Job Duration (hours)"
          region = data.aws_region.current.region
          view   = "timeSeries"
          period = 3600
          metrics = [
            [{ expression = local.metric_avg_expressions["Iceberg table orphan_file_deletion duration of job (Hours)"], id = "m", label = "Avg duration (hrs)" }],
          ]
        }
      },
    ]
  })
}
