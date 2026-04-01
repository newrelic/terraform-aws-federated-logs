// Hardcoded scope for now , as the entities are moved to account scope. PR is yet to be merged
resource "newrelic_federated_logs_partition" "this" {
  for_each = local.all_tables

  scope_id           = "7d17d19f-637d-4bcb-8c94-8473c334b3ec"
  scope_type         = "ORGANIZATION"
  setup_id           = var.federated_logs_setup_id
  name               = "Log_Partition-${each.key}"
  is_default         = is_default = each.key == substr(replace(lower("${local.setup_naming_prefix}_${local.default_partition_name}"), "/[^a-z0-9_]/", "_"), 0, local.max_table_name_length)
  partition_database = var.glue_catalog_db_name
  partition_table    = each.key
  data_location_uri  = "s3://${var.s3_bucket_name}/${var.glue_catalog_db_name}/${each.key}"
  nr_account_id      = var.nr_account_id
  status             = "CREATING"

  depends_on = [aws_glue_catalog_table.iceberg_table, aws_s3_object.folder]
}

resource "aws_s3_object" "folder" {
  for_each = local.all_tables
  bucket   = var.s3_bucket_name
  key      = "${var.glue_catalog_db_name}/${each.key}/"
}

resource "aws_glue_catalog_table" "iceberg_table" {
  for_each = local.all_tables

  name          = each.key
  database_name = var.glue_catalog_db_name

  lifecycle {
    ignore_changes = [
      # Prevent TF from fighting with Athena/Iceberg over these dynamic keys
      parameters["previous_metadata_location"],
      parameters["metadata_location"],
      parameters["current-snapshot-id"],
      parameters["current-snapshot-timestamp-ms"],
      parameters["current-snapshot-summary"],
      parameters["snapshot-count"]
    ]
  }

  open_table_format_input {
    iceberg_input {
      metadata_operation = "CREATE"
      version            = 2

      iceberg_table_input {
        location = "s3://${var.s3_bucket_name}/${var.glue_catalog_db_name}/${each.key}/"

        properties = local.resolved_table_params[each.key]

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
          fields {
            id       = 5
            name     = "messageId"
            required = true
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
