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
        snapshot_retention_period_in_days = each.value.optimizer_configuration.snapshot_retention.snapshot_retention_period_in_days
        number_of_snapshots_to_retain     = each.value.optimizer_configuration.snapshot_retention.number_of_snapshots_to_retain
        clean_expired_files               = each.value.optimizer_configuration.snapshot_retention.clean_expired_files
        run_rate_in_hours                 = each.value.optimizer_configuration.snapshot_retention.run_rate_in_hours
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

# null_resource is used here because aws_glue_catalog_table_optimizer does not yet support
# compaction_configuration in the Terraform AWS provider. This calls update-table-optimizer
# via the AWS CLI to set strategy/min_input_files/delete_file_threshold.
resource "null_resource" "compaction_configuration" {
  for_each = local.all_tables

  triggers = {
    table_key             = each.key
    strategy              = each.value.optimizer_configuration.compaction.strategy
    min_input_files       = each.value.optimizer_configuration.compaction.min_input_files != null ? tostring(each.value.optimizer_configuration.compaction.min_input_files) : ""
    delete_file_threshold = each.value.optimizer_configuration.compaction.delete_file_threshold != null ? tostring(each.value.optimizer_configuration.compaction.delete_file_threshold) : ""
    role_arn              = var.glue_service_role_arn
  }

  depends_on = [aws_glue_catalog_table_optimizer.compaction]

  provisioner "local-exec" {
    environment = {
      CONFIG = jsonencode({
        roleArn = var.glue_service_role_arn
        enabled = true
        compactionConfiguration = {
          icebergConfiguration = local.compaction_configs[each.key]
        }
      })
    }
    command = <<-EOT
      set -e
      echo "Configuring compaction for table ${each.key} (strategy: ${each.value.optimizer_configuration.compaction.strategy})..."
      aws glue update-table-optimizer \
        --catalog-id ${data.aws_caller_identity.current.account_id} \
        --database-name ${var.glue_catalog_db_name} \
        --table-name ${each.key} \
        --table-optimizer-configuration "$CONFIG" \
        --type compaction \
        --region ${data.aws_region.current.region}
      echo "Compaction configured for ${each.key}."
    EOT
  }
}