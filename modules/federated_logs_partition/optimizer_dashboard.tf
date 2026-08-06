# CloudWatch Dashboard — Glue Iceberg Optimizer Health
#
# One dashboard per setup, scoped to this setup's Glue database.

locals {
  # Build a SUM(SEARCH(...)) metric math expression aggregated across all tables
  # in this setup's Glue database.
  metric_sum_expressions = {
    for m in [
      # Compaction — run counts (Iceberg-prefixed names)
      "Iceberg table compaction success",
      "Iceberg table compaction failure",
      # Compaction — per-run stats
      "Number of files compacted",
      "Number of bytes compacted",
      "Number of DPUs allocated to compaction job",
      "DPU-hours of a compaction job",
      "Number of data files removed",
      "Number of delete files removed",
      "Number of data file bytes removed",
      "Number of delete file bytes removed",
      # Retention — run counts
      "Iceberg table retention success",
      "Iceberg table retention failure",
      # Retention — per-run stats
      "Number of data files deleted",
      "Number of manifest files deleted",
      "Number of manifest lists deleted",
      "Number of DPUs allocated to retention job",
      # Orphan file deletion — run counts
      "Iceberg table orphan_file_deletion success",
      "Iceberg table orphan_file_deletion failure",
      # Orphan file deletion — per-run stats
      "Number of orphan files deleted",
      "Number of DPUs allocated to orphan_file_deletion job",
    ] : m => "SUM(SEARCH('{AWS/Glue,DATABASE_NAME,TABLE_NAME} \"${m}\" DATABASE_NAME=\"${var.glue_catalog_db_name}\"', 'Sum', 3600))"
  }

  # "Duration of job (hours)" is shared across all 3 optimizer types — AVG aggregation.
  avg_job_duration_expression = "AVG(SEARCH('{AWS/Glue,DATABASE_NAME,TABLE_NAME} \"Duration of job (hours)\" DATABASE_NAME=\"${var.glue_catalog_db_name}\"', 'Average', 3600))"
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
            [{ expression = local.metric_sum_expressions["Number of files compacted"], id = "m", label = "Files compacted" }],
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
            [{ expression = local.metric_sum_expressions["Number of bytes compacted"], id = "m", label = "Bytes compacted" }],
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
            [{ expression = local.metric_sum_expressions["Number of DPUs allocated to compaction job"], id = "m", label = "DPUs" }],
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
          title  = "Compaction — DPU-Hours"
          region = data.aws_region.current.region
          view   = "timeSeries"
          metrics = [
            [{ expression = local.metric_sum_expressions["DPU-hours of a compaction job"], id = "m", label = "DPU-hours" }],
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
          title  = "Compaction — Files Removed"
          region = data.aws_region.current.region
          view   = "timeSeries"
          metrics = [
            [{ expression = local.metric_sum_expressions["Number of data files removed"], id = "df", label = "Data files" }],
            [{ expression = local.metric_sum_expressions["Number of delete files removed"], id = "del", label = "Delete files" }],
          ]
        }
      },

      {
        type   = "metric"
        x      = 0
        y      = 17
        width  = 8
        height = 6
        properties = {
          title  = "Compaction — Data File Bytes Removed"
          region = data.aws_region.current.region
          view   = "timeSeries"
          metrics = [
            [{ expression = local.metric_sum_expressions["Number of data file bytes removed"], id = "m", label = "Data file bytes removed" }],
          ]
        }
      },

      # ════════════════════════════════════════════════════════════════════
      # RETENTION
      # ════════════════════════════════════════════════════════════════════
      {
        type   = "text"
        x      = 0
        y      = 23
        width  = 24
        height = 2
        properties = {
          markdown = "## Snapshot Retention\nDeletes old Iceberg snapshots and their associated data/manifest files beyond the configured retention window."
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 25
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
        y      = 25
        width  = 8
        height = 6
        properties = {
          title  = "Retention — Files Deleted"
          region = data.aws_region.current.region
          view   = "timeSeries"
          metrics = [
            [{ expression = local.metric_sum_expressions["Number of data files deleted"], id = "df", label = "Data files" }],
            [{ expression = local.metric_sum_expressions["Number of manifest files deleted"], id = "mf", label = "Manifest files" }],
            [{ expression = local.metric_sum_expressions["Number of manifest lists deleted"], id = "ml", label = "Manifest lists" }],
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
          title  = "Retention — DPU Allocated"
          region = data.aws_region.current.region
          view   = "timeSeries"
          metrics = [
            [{ expression = local.metric_sum_expressions["Number of DPUs allocated to retention job"], id = "m", label = "DPUs" }],
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
      {
        type   = "metric"
        x      = 0
        y      = 33
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
        y      = 33
        width  = 8
        height = 6
        properties = {
          title  = "Orphan File Deletion — Files Deleted"
          region = data.aws_region.current.region
          view   = "timeSeries"
          metrics = [
            [{ expression = local.metric_sum_expressions["Number of orphan files deleted"], id = "m", label = "Orphan files deleted" }],
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
          title  = "Orphan File Deletion — DPU Allocated"
          region = data.aws_region.current.region
          view   = "timeSeries"
          metrics = [
            [{ expression = local.metric_sum_expressions["Number of DPUs allocated to orphan_file_deletion job"], id = "m", label = "DPUs" }],
          ]
        }
      },

      # ════════════════════════════════════════════════════════════════════
      # JOB DURATION (shared metric across all optimizer types)
      # ════════════════════════════════════════════════════════════════════
      {
        type   = "text"
        x      = 0
        y      = 39
        width  = 24
        height = 2
        properties = {
          markdown = "## Job Duration\n`Duration of job (hours)` is a shared metric emitted by all 3 optimizer types. This widget shows average run duration across all optimizer jobs for this setup."
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 41
        width  = 8
        height = 6
        properties = {
          title  = "All Optimizers — Avg Job Duration (hours)"
          region = data.aws_region.current.region
          view   = "timeSeries"
          metrics = [
            [{ expression = local.avg_job_duration_expression, id = "m", label = "Avg duration (hrs)" }],
          ]
        }
      },
    ]
  })
}
