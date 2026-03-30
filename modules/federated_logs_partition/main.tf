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
  table_type    = "EXTERNAL_TABLE"

  parameters = local.resolved_table_params[each.key]

  open_table_format_input {
    iceberg_input {
      metadata_operation = "CREATE"
    }
  }

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