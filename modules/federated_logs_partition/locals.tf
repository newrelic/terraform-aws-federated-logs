locals {

  setup_naming_prefix = "newrelic_fed_logs_${var.setup_name}"

  default_partition_name = "Log_Federated"

  max_table_name_length = 255

  # SANITIZED TABLE MAP
  # We create a new map where the keys are the "clean" names
  sanitized_partition_tables = {
    for raw_key, config in var.partition_tables :
    # 1. Lowercase everything
    # 2. Replace hyphens (or any non-alphanumeric) with underscores
    # 3. Truncate to the max length
    substr(replace(lower("${local.setup_naming_prefix}_${raw_key}"), "/[^a-z0-9_]/", "_"), 0, local.max_table_name_length) => config
  }

  all_tables = merge(
    { substr(replace(lower("${local.setup_naming_prefix}_${local.default_partition_name}"), "/[^a-z0-9_]/", "_"), 0, local.max_table_name_length) = var.default_table_setting },
    local.sanitized_partition_tables
  )

  # Parameters you always want set — user values override these
  default_iceberg_params = {
    "format"                                     = "parquet"
    "write.target-file-size-bytes"               = "26214400" # 25 MB
    "write.metadata.delete-after-commit.enabled" = "true"
    "write.metadata.previous-versions-max"       = "10"
  }

  # For each table: defaults ← user params (user wins on overlap)
  resolved_table_params = {
    for k, v in local.all_tables :
    k => merge(local.default_iceberg_params, v.table_parameters)
  }

}