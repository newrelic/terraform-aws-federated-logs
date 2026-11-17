data "aws_caller_identity" "current" {}

resource "aws_glue_catalog_table_optimizer" "compaction" {
  for_each      = local.all_tables
  catalog_id    = data.aws_caller_identity.current.account_id
  database_name = var.glue_catalog_db_name
  table_name    = aws_glue_catalog_table.iceberg_table[each.key].name
  type          = "compaction"
  region        = data.aws_region.current.region

  configuration {
    role_arn = var.glue_service_role_arn
    enabled  = true

    # Part of the optimizer itself (provider >= 6.58.0), so a replaced optimizer
    # comes back with these settings and drift shows in the plan. Without
    # min_input_files Glue waits for 100 files in one partition, which an hourly
    # partition at low volume never reaches.
    compaction_configuration {
      iceberg_configuration {
        strategy              = each.value.optimizer_configuration.compaction.strategy
        min_input_files       = each.value.optimizer_configuration.compaction.min_input_files
        delete_file_threshold = each.value.optimizer_configuration.compaction.delete_file_threshold
      }
    }
  }
}

resource "aws_glue_catalog_table_optimizer" "retention" {
  for_each      = local.all_tables
  catalog_id    = data.aws_caller_identity.current.account_id
  database_name = var.glue_catalog_db_name
  table_name    = aws_glue_catalog_table.iceberg_table[each.key].name
  type          = "retention"
  region        = data.aws_region.current.region

  configuration {
    role_arn = var.glue_service_role_arn
    enabled  = true
    retention_configuration {
      iceberg_configuration {
        # snapshot_retention_period_in_days is deliberately not set: with it
        # omitted, Glue reads the table's history.expire.max-snapshot-age-ms.
        number_of_snapshots_to_retain = each.value.optimizer_configuration.snapshot_retention.number_of_snapshots_to_retain
        clean_expired_files           = each.value.optimizer_configuration.snapshot_retention.clean_expired_files
        run_rate_in_hours             = each.value.optimizer_configuration.snapshot_retention.run_rate_in_hours
      }
    }
  }
}


resource "aws_glue_catalog_table_optimizer" "orphan_deletion" {
  for_each      = local.all_tables
  catalog_id    = data.aws_caller_identity.current.account_id
  database_name = var.glue_catalog_db_name
  table_name    = aws_glue_catalog_table.iceberg_table[each.key].name
  type          = "orphan_file_deletion"
  region        = data.aws_region.current.region

  configuration {
    role_arn = var.glue_service_role_arn
    enabled  = true

    orphan_file_deletion_configuration {
      iceberg_configuration {
        orphan_file_retention_period_in_days = each.value.optimizer_configuration.orphan_file_deletion.orphan_file_retention_period_in_days
        run_rate_in_hours                    = each.value.optimizer_configuration.orphan_file_deletion.run_rate_in_hours
      }
    }
  }
}
