resource "aws_s3_object" "folder" {
  for_each = local.all_tables
  bucket   = var.s3_bucket_name
  key      = "${var.glue_catalog_db_name}/${each.key}/"
}

resource "null_resource" "create_iceberg_table" {
  for_each = local.all_tables

  # Triggers on structural identity. Parameter-only changes do not recreate the
  # table (which would cause data loss); update TBLPROPERTIES via ALTER TABLE manually.
  triggers = {
    table_key  = each.key
    db_name    = var.glue_catalog_db_name
    s3_bucket  = var.s3_bucket_name
    aws_region = var.aws_region
  }

  depends_on = [aws_s3_object.folder]

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      QUERY="CREATE TABLE IF NOT EXISTS ${var.glue_catalog_db_name}.${each.key} (
        logtype   string,
        message   string,
        timestamp timestamp,
        guid      string
      )
      PARTITIONED BY (hour(timestamp))
      LOCATION 's3://${var.s3_bucket_name}/${var.glue_catalog_db_name}/${each.key}/'
      TBLPROPERTIES (
        'table_type'        = 'ICEBERG',
        'write_compression' = 'zstd'
      )"

      QUERY_ID=$(aws athena start-query-execution \
        --query-string "$QUERY" \
        --query-execution-context Database=${var.glue_catalog_db_name} \
        --result-configuration OutputLocation=s3://${var.s3_bucket_name}/athena-query-results/ \
        --region ${var.aws_region} \
        --output text \
        --query QueryExecutionId)

      echo "Creating table ${each.key} — Athena query: $QUERY_ID"

      while true; do
        STATE=$(aws athena get-query-execution \
          --query-execution-id "$QUERY_ID" \
          --region ${var.aws_region} \
          --output text \
          --query 'QueryExecution.Status.State')
        echo "  state: $STATE"
        case "$STATE" in
          SUCCEEDED)
            echo "Table ${each.key} created."
            break
            ;;
          FAILED|CANCELLED)
            REASON=$(aws athena get-query-execution \
              --query-execution-id "$QUERY_ID" \
              --region ${var.aws_region} \
              --output text \
              --query 'QueryExecution.Status.StateChangeReason')
            echo "Query $STATE: $REASON"
            exit 1
            ;;
          *)
            sleep 3
            ;;
        esac
      done
    EOT
  }

  provisioner "local-exec" {
    when = destroy
    command = <<-EOT
      set -e

      QUERY="DROP TABLE IF EXISTS ${self.triggers.db_name}.${self.triggers.table_key}"

      QUERY_ID=$(aws athena start-query-execution \
        --query-string "$QUERY" \
        --query-execution-context Database=${self.triggers.db_name} \
        --result-configuration OutputLocation=s3://${self.triggers.s3_bucket}/athena-query-results/ \
        --region ${self.triggers.aws_region} \
        --output text \
        --query QueryExecutionId)

      echo "Dropping table ${self.triggers.table_key} — Athena query: $QUERY_ID"

      while true; do
        STATE=$(aws athena get-query-execution \
          --query-execution-id "$QUERY_ID" \
          --region ${self.triggers.aws_region} \
          --output text \
          --query 'QueryExecution.Status.State')
        echo "  state: $STATE"
        case "$STATE" in
          SUCCEEDED)
            echo "Table ${self.triggers.table_key} dropped."
            break
            ;;
          FAILED|CANCELLED)
            REASON=$(aws athena get-query-execution \
              --query-execution-id "$QUERY_ID" \
              --region ${self.triggers.aws_region} \
              --output text \
              --query 'QueryExecution.Status.StateChangeReason')
            echo "Query $STATE: $REASON"
            exit 1
            ;;
          *)
            sleep 3
            ;;
        esac
      done
    EOT
  }
}
