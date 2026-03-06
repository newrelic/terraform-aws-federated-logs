resource "aws_s3_object" "folder" {
  for_each = local.all_tables
  bucket   = var.s3_bucket_name
  key      = "${var.glue_catalog_db_name}/${each.key}/"
}

resource "aws_glue_catalog_table" "iceberg_table" {
  for_each = local.all_tables

  name          = each.key
  database_name = var.glue_catalog_db_name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    "format"                                     = "parquet"
    "write.target-file-size-bytes"               = each.value.table_parameters.write_target_file_size_bytes
    "write.metadata.delete-after-commit.enabled" = tostring(each.value.table_parameters.write_metadata_delete_after_commit_enabled)
    "write.metadata.previous-versions-max"       = each.value.table_parameters.write_metadata_previous_versions_max
  }
  open_table_format_input {
    iceberg_input {
      metadata_operation = "CREATE"
    }
  }

  storage_descriptor {
    # Partitions data by table name: s3://my-bucket/Log/ or s3://my-bucket/Security/
    location = "s3://${var.s3_bucket_name}/${var.glue_catalog_db_name}/${each.key}"
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