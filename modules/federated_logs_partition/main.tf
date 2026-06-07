
resource "aws_s3_object" "folder" {
  for_each = local.all_tables
  bucket   = var.s3_bucket_name
  key      = "${var.glue_catalog_db_name}/${each.key}/"
  region   = data.aws_region.current.region
}

resource "aws_glue_catalog_table" "iceberg_table" {
  for_each = local.all_tables

  name          = each.key
  database_name = var.glue_catalog_db_name
  region        = data.aws_region.current.region
  table_type    = "ICEBERG"

  lifecycle {
    ignore_changes = [
      # Iceberg tables are materialized in Glue as EXTERNAL_TABLE with Iceberg
      # metadata pointers, so AWS read-back disagrees with the HCL declaration.
      # Without these ignores, every plan after creation shows spurious drift
      # (and would force destroy/recreate → data loss).
      parameters,              # metadata_location, format-version, etc. — managed by Iceberg
      table_type,              # AWS returns EXTERNAL_TABLE on read
      open_table_format_input, # one-shot CREATE directive; not echoed back on read
      storage_descriptor,      # Iceberg mutates this on each commit
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

# ── Non-default partitions on the New Relic side ─────────────────────────────
# For each entry in var.partition_tables, create a newrelic_federated_logs_partition
# alongside the Glue table.
#
# We iterate over local.sanitized_partition_tables (which excludes the default)
# rather than local.all_tables.
resource "newrelic_federated_logs_partition" "this" {
  for_each = local.sanitized_partition_tables

  account_id  = var.newrelic_account_id
  setup_id    = var.setup_id
  name        = local.nr_partition_names[each.key]
  description = each.value.description

  storage {
    table             = each.key
    data_location_uri = "s3://${var.s3_bucket_name}/${var.glue_catalog_db_name}/${each.key}"
  }

  data_retention_policy {
    duration = each.value.retention_in_days
    unit     = "DAYS"
  }

  dynamic "forwarder_configuration" {
    for_each = each.value.routing_expression != null ? [1] : []
    content {
      type = "PIPELINE_CONTROL"
      pipeline_control {
        partition_rule {
          expression = each.value.routing_expression
        }
      }
    }
  }
}
