# CloudWatch Dashboard — Glue Iceberg Optimizer Health
#
# One dashboard per setup, scoped to this setup's Glue database.

locals {
  # Build a SUM(SEARCH(...)) metric math expression aggregated across all tables
  # in this setup's Glue database.
  metric_sum_expressions = {
    for m in [
      "Iceberg table compaction success",
      "Iceberg table compaction failure",
      "Iceberg table compaction number of files compacted",
      "Iceberg table compaction number of bytes compacted",
      "Iceberg table compaction number of DPU allocated to job",
      "Iceberg table retention success",
      "Iceberg table retention failure",
      "Iceberg table retention number of data files deleted",
      "Iceberg table retention number of manifest files deleted",
      "Iceberg table retention number of manifest lists deleted",
      "Iceberg table orphan_file_deletion success",
      "Iceberg table orphan_file_deletion failure",
      "Iceberg table orphan_file_deletion number of orphan files deleted",
    ] : m => "SUM(SEARCH('{AWS/Glue,DATABASE_NAME,TABLE_NAME} \"${m}\" DATABASE_NAME=\"${var.glue_catalog_db_name}\"', 'Sum', 3600))"
  }

  # Average variant for duration metrics.
  metric_avg_expressions = {
    for m in [
      "Iceberg table compaction duration of job (Hours)",
      "Iceberg table retention duration of job (Hours)",
      "Iceberg table orphan_file_deletion duration of job (Hours)",
    ] : m => "AVG(SEARCH('{AWS/Glue,DATABASE_NAME,TABLE_NAME} \"${m}\" DATABASE_NAME=\"${var.glue_catalog_db_name}\"', 'Average', 3600))"
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
      {
        type   = "metric"
        x      = 0
        y      = 5
        width  = 8
        height = 6
        properties = {
          title  = "Compaction — Runs"
          region = data.aws_region.current.region
          view   = "timeSeries"
          metrics = [
            [{ expression = local.metric_sum_expressions["Iceberg table compaction success"], id = "s", label = "Success", color = "#2ca02c" }],
            [{ expression = local.metric_sum_expressions["Iceberg table compaction failure"], id = "f", label = "Failure", color = "#d62728" }],
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
          title  = "Compaction — Files Compacted"
          region = data.aws_region.current.region
          view   = "timeSeries"
          metrics = [
            [{ expression = local.metric_sum_expressions["Iceberg table compaction number of files compacted"], id = "m", label = "Files compacted" }],
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
          title  = "Compaction — Bytes Compacted"
          region = data.aws_region.current.region
          view   = "timeSeries"
          metrics = [
            [{ expression = local.metric_sum_expressions["Iceberg table compaction number of bytes compacted"], id = "m", label = "Bytes compacted" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 11
        width  = 8
        height = 6
        properties = {
          title  = "Compaction — DPU Allocated"
          region = data.aws_region.current.region
          view   = "timeSeries"
          metrics = [
            [{ expression = local.metric_sum_expressions["Iceberg table compaction number of DPU allocated to job"], id = "m", label = "DPUs" }],
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
          title  = "Compaction — Avg Job Duration (hours)"
          region = data.aws_region.current.region
          view   = "timeSeries"
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
      {
        type   = "metric"
        x      = 0
        y      = 19
        width  = 8
        height = 6
        properties = {
          title  = "Retention — Runs"
          region = data.aws_region.current.region
          view   = "timeSeries"
          metrics = [
            [{ expression = local.metric_sum_expressions["Iceberg table retention success"], id = "s", label = "Success", color = "#2ca02c" }],
            [{ expression = local.metric_sum_expressions["Iceberg table retention failure"], id = "f", label = "Failure", color = "#d62728" }],
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
          title  = "Retention — Files Deleted"
          region = data.aws_region.current.region
          view   = "timeSeries"
          metrics = [
            [{ expression = local.metric_sum_expressions["Iceberg table retention number of data files deleted"], id = "df", label = "Data files" }],
            [{ expression = local.metric_sum_expressions["Iceberg table retention number of manifest files deleted"], id = "mf", label = "Manifest files" }],
            [{ expression = local.metric_sum_expressions["Iceberg table retention number of manifest lists deleted"], id = "ml", label = "Manifest lists" }],
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
          metrics = [
            [{ expression = local.metric_avg_expressions["Iceberg table retention duration of job (Hours)"], id = "m", label = "Avg duration (hrs)" }],
          ]
        }
      },

      # ════════════════════════════════════════════════════════════════════
      # ORPHAN FILE DELETION
      # ════════════════════════════════════════════════════════════════════
      {
        type   = "text"
        x      = 0
        y      = 25
        width  = 24
        height = 2
        properties = {
          markdown = "## Orphan File Deletion\nRemoves leftover S3 files not referenced by any Iceberg snapshot, freeing up storage."
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 27
        width  = 8
        height = 6
        properties = {
          title  = "Orphan File Deletion — Runs"
          region = data.aws_region.current.region
          view   = "timeSeries"
          metrics = [
            [{ expression = local.metric_sum_expressions["Iceberg table orphan_file_deletion success"], id = "s", label = "Success", color = "#2ca02c" }],
            [{ expression = local.metric_sum_expressions["Iceberg table orphan_file_deletion failure"], id = "f", label = "Failure", color = "#d62728" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 27
        width  = 8
        height = 6
        properties = {
          title  = "Orphan File Deletion — Files Deleted"
          region = data.aws_region.current.region
          view   = "timeSeries"
          metrics = [
            [{ expression = local.metric_sum_expressions["Iceberg table orphan_file_deletion number of orphan files deleted"], id = "m", label = "Orphan files deleted" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 27
        width  = 8
        height = 6
        properties = {
          title  = "Orphan File Deletion — Avg Job Duration (hours)"
          region = data.aws_region.current.region
          view   = "timeSeries"
          metrics = [
            [{ expression = local.metric_avg_expressions["Iceberg table orphan_file_deletion duration of job (Hours)"], id = "m", label = "Avg duration (hrs)" }],
          ]
        }
      },
    ]
  })
}
