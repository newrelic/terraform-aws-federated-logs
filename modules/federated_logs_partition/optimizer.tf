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

  # The max-age property must be on the table before snapshot_retention_period_in_days
  # is dropped: with neither set, Glue falls back to its 5-day default.
  depends_on = [null_resource.snapshot_max_age_property]

  configuration {
    role_arn = var.glue_service_role_arn
    enabled  = true
    retention_configuration {
      iceberg_configuration {
        # null (the default) omits the field, so Glue reads the table's
        # history.expire.max-snapshot-age-ms instead. The API only takes whole
        # days (minimum 1), so leaving it unset is the only way below ~25 h.
        snapshot_retention_period_in_days = each.value.optimizer_configuration.snapshot_retention.snapshot_retention_period_in_days
        number_of_snapshots_to_retain     = each.value.optimizer_configuration.snapshot_retention.number_of_snapshots_to_retain
        clean_expired_files               = each.value.optimizer_configuration.snapshot_retention.clean_expired_files
        run_rate_in_hours                 = each.value.optimizer_configuration.snapshot_retention.run_rate_in_hours
      }
    }
  }
}

# Sets history.expire.max-snapshot-age-ms on every table through an Iceberg
# commit (Athena ALTER TABLE; vacuum_max_snapshot_age_seconds maps to it).
# Terraform has no safe way to change an existing table's Iceberg
# properties: open_table_format_input is create-only (see main.tf), and Glue
# parameters aren't what the retention optimizer reads. Idempotent, so it
# also runs harmlessly right after a table is created. Retried because the
# commit can lose a race with the Flink commit worker.
resource "null_resource" "snapshot_max_age_property" {
  for_each = local.all_tables

  triggers = {
    table_key           = each.key
    max_snapshot_age_ms = tostring(each.value.optimizer_configuration.snapshot_retention.max_snapshot_age_ms)
  }

  depends_on = [aws_glue_catalog_table.iceberg_table]

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      echo "Setting history.expire.max-snapshot-age-ms=${each.value.optimizer_configuration.snapshot_retention.max_snapshot_age_ms} on ${each.key}..."
      for attempt in 1 2 3; do
        QID=$(aws athena start-query-execution \
          --work-group primary \
          --query-execution-context Database=${var.glue_catalog_db_name} \
          --result-configuration OutputLocation=s3://${aws_s3_bucket.newrelic_artifacts.bucket}/athena-results/ \
          --query-string "ALTER TABLE ${each.key} SET TBLPROPERTIES ('vacuum_max_snapshot_age_seconds'='${floor(each.value.optimizer_configuration.snapshot_retention.max_snapshot_age_ms / 1000)}')" \
          --region ${data.aws_region.current.region} \
          --query QueryExecutionId --output text)
        STATE=RUNNING
        for i in $(seq 1 60); do
          STATE=$(aws athena get-query-execution --query-execution-id "$QID" \
            --region ${data.aws_region.current.region} \
            --query QueryExecution.Status.State --output text)
          case "$STATE" in SUCCEEDED|FAILED|CANCELLED) break ;; esac
          sleep 5
        done
        if [ "$STATE" = "SUCCEEDED" ]; then
          echo "Max snapshot age set on ${each.key}."
          exit 0
        fi
        echo "Attempt $attempt: Athena query $QID ended $STATE:" >&2
        aws athena get-query-execution --query-execution-id "$QID" \
          --region ${data.aws_region.current.region} \
          --query QueryExecution.Status.StateChangeReason --output text >&2 || true
        sleep 10
      done
      exit 1
    EOT
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