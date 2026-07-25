data "aws_region" "current" {
  region = var.region
}

resource "aws_s3_object" "folder" {
  for_each = local.all_tables
  bucket   = var.s3_bucket_name
  key      = "${var.glue_catalog_db_name}/${each.key}/"
  region   = data.aws_region.current.region

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_glue_catalog_table" "iceberg_table" {
  for_each = local.all_tables

  name          = each.key
  database_name = var.glue_catalog_db_name
  region        = data.aws_region.current.region
  table_type    = "EXTERNAL_TABLE"

  lifecycle {
    prevent_destroy = true
    ignore_changes = [
      # Prevent TF from fighting with Athena/Iceberg over these dynamic keys
      parameters
    ]
  }

  open_table_format_input {
    iceberg_input {
      metadata_operation = "CREATE"
      version            = 2

      iceberg_table_input {
        location = "s3://${var.s3_bucket_name}/${var.glue_catalog_db_name}/${each.key}/"

        properties = local.resolved_table_params[each.key]

        # Seed schema for the table. Fields and IDs declared here are
        # mirrored in `local.iceberg_schema_name_mapping` (locals.tf) so
        # that Iceberg readers can resolve case-sensitive names from data
        # files without embedded field IDs. KEEP THE TWO IN SYNC — any
        # add / remove / rename here needs the same change in locals.tf.
        #
        # Runtime schema additions via Iceberg's UpdateSchema API
        # auto-extend the name-mapping property in place, so only the
        # seed fields below are Terraform-managed.
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
          # NOTE: messageId is intentionally NOT declared as a static field
          # here. PCG generates messageId into attributes["messageId"] via
          # the add_message_id OTEL transform; it's never written as a
          # top-level column. Pre-declaring it (as field-id 5 in previous
          # versions of this module) created a dead column that, once Glue
          # Catalog lower-cased it to `messageid`, collided with the
          # `messageId` column Iceberg added at runtime when PCG started
          # writing the attribute. The collision surfaced as
          # `Multiple entries with same key: messageid=N:messageId:varchar`
          # on Athena/Trino reads. Dropping the static declaration lets PCG
          # (or any other writer) own the field at runtime, and Iceberg
          # auto-extends `schema.name-mapping.default` for it.
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
