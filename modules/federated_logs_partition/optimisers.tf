# ------------------------------------------------------------------
# 3. OPTIMIZER: COMPACTION
# ------------------------------------------------------------------
# Consolidates small files into larger ones to improve query performance.
resource "aws_glue_catalog_table_optimizer" "compaction" {
  for_each = { for k, v in local.all_tables : k => v if v.enable_compaction }

  catalog_id    = var.aws_account_id
  database_name = var.glue_catalog_db_name
  table_name    = aws_glue_catalog_table.iceberg_table[each.key].name
  type          = "compaction"

  configuration {
    role_arn = var.glue_service_role_arn
    enabled  = true
  }
}

# ------------------------------------------------------------------
# 4. OPTIMIZER: SNAPSHOT RETENTION
# ------------------------------------------------------------------
# Cleans up old metadata snapshots to save S3 space and improve performance.
resource "aws_glue_catalog_table_optimizer" "retention" {
  for_each = { for k, v in local.all_tables : k => v if v.enable_retention }

  catalog_id    = var.aws_account_id
  database_name = var.glue_catalog_db_name
  table_name    = aws_glue_catalog_table.iceberg_table[each.key].name
  type          = "retention"

  configuration {
    role_arn = var.glue_service_role_arn
    enabled  = true
    retention_configuration {
      iceberg_configuration {
        snapshot_retention_period_in_days = each.value.snapshot_retention.days_snapshot_kept
        number_of_snapshots_to_retain     = each.value.snapshot_retention.min_snapshots_to_retain
        clean_expired_files               = each.value.snapshot_retention.delete_associated_files
      }
    }
  }
}

# ------------------------------------------------------------------
# 5. OPTIMIZER: ORPHAN FILE DELETION
# ------------------------------------------------------------------
# Deletes S3 files that are no longer referenced by any Iceberg metadata.
resource "aws_glue_catalog_table_optimizer" "orphan_deletion" {
  for_each = { for k, v in local.all_tables : k => v if v.enable_orphan_file_deletion }

  catalog_id    = var.aws_account_id
  database_name = var.glue_catalog_db_name
  table_name    = aws_glue_catalog_table.iceberg_table[each.key].name
  type          = "orphan_file_deletion"

  configuration {
    role_arn = var.glue_service_role_arn
    enabled  = true

    orphan_file_deletion_configuration {
      iceberg_configuration {
        orphan_file_retention_period_in_days = each.value.orphan_file_deletion.delete_after_days
      }
    }
  }
}