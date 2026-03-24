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
      version            = 2

      iceberg_table_input {
        location = "s3://${var.s3_bucket_name}/${var.glue_catalog_db_name}/${each.key}/"

        schema {
          schema_id = 0
          type      = "struct"

          fields {
            id       = 1
            name     = "logtype"
            required = false
            type     = <<EOF
"string"
EOF
          }
          fields {
            id       = 2
            name     = "message"
            required = false
            type     = <<EOF
"string"
EOF
          }
          fields {
            id       = 3
            name     = "timestamp"
            required = true
            type     = <<EOF
"timestamp"
EOF
          }
          fields {
            id       = 4
            name     = "guid"
            required = false
            type     = <<EOF
"string"
EOF
          }
        }

        partition_spec {
          fields {
            name      = "timestamp_hour"
            source_id = 3
            transform = "hour"
          }
          spec_id = 0
        }
      }
    }
  }
}