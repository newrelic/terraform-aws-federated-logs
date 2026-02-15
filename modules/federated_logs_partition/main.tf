

resource "aws_glue_catalog_table" "iceberg_table" {
  for_each = local.all_tables

  name          = "${local.iceberg_table_name_prefix}-${lower(each.key)}"
  database_name = var.glue_catalog_db_name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    "format"                                     = "parquet"
    "write.compact.min-input-files"  = each.value.compaction_config.min_input_files
    "write.upsert.enabled"           = "true"
    "write.delete.threshold"         = each.value.compaction_config.delete_file_threshold
    "write.target-file-size-bytes"               = "26214400" # 25 MB
    "write.metadata.delete-after-commit.enabled" = "true"
    "write.metadata.previous-versions-max"       = "10"

    # --- SNAPSHOT RETENTION PROPERTIES ---
    # How many snapshots to keep regardless of age
    "history.expire.min-snapshots-to-keep" = tostring(each.value.snapshot_retention.min_snapshots_to_retain)
    
    # How long to keep snapshots (converted from days to milliseconds for Iceberg)
    "history.expire.max-snapshot-age-ms"   = tostring(each.value.snapshot_retention.days_snapshot_kept * 86400000)
    
    # Whether to delete the data files associated with the expired snapshots
    "write.metadata.delete-after-commit.enabled" = tostring(each.value.snapshot_retention.delete_associated_files)
  }
  open_table_format_input {
    iceberg_input {
      metadata_operation = "CREATE"
    }
  }

  storage_descriptor {
    # Partitions data by table name: s3://my-bucket/Log/ or s3://my-bucket/Security/
    location      = "s3://${var.s3_bucket_name}/${var.glue_catalog_db_name}/${local.iceberg_table_name_prefix}-${lower(each.key)}"
    columns {
      name = "logtype"
      type = "string"
      parameters = {
        "iceberg.field.current"  = "true"
        "iceberg.field.id"       = "1"
        "iceberg.field.optional" = "true"
      }
    }
    columns {
      name = "message"
      type = "string"
      parameters = {
        "iceberg.field.current"  = "true"
        "iceberg.field.id"       = "2"
        "iceberg.field.optional" = "true"
      }
    }
    columns {
      name = "timestamp"
      type = "timestamp"
      parameters = {
        "iceberg.field.current"  = "true"
        "iceberg.field.id"       = "3"
        "iceberg.field.optional" = "false"
      }
    }
    columns {
      name = "guid"
      type = "string"
      parameters = {
        "iceberg.field.current"  = "true"
        "iceberg.field.id"       = "4"
        "iceberg.field.optional" = "true"
      }
    }
  }
}