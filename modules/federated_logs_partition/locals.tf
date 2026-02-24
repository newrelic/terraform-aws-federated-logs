locals {
  default_partition_name = "Log_Federated"

  max_table_name_length = 255

  # SANITIZED TABLE MAP
  # We create a new map where the keys are the "clean" names
  sanitized_partition_tables = {
    for raw_key, config in var.partition_tables : 
    # 1. Lowercase everything
    # 2. Replace hyphens (or any non-alphanumeric) with underscores
    # 3. Truncate to the max length
    substr(replace(lower("${var.resource_naming_prefix}_${raw_key}"), "/[^a-z0-9_]/", "_"), 0, local.max_table_name_length) => config
  }

  all_tables = merge(
    { "${lower(local.default_partition_name)}" = var.default_table_setting },
    local.sanitized_partition_tables
  )

}