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

  # NR (NGEP) partition names — decoupled from Glue table names.
  # Keyed by the sanitized Glue table name; value is the NR-side partition name
  # Default partition is named "Log_federated" inline by the setup resource.
  nr_partition_names = {
    for raw_key, _ in var.partition_tables :
    substr(replace(lower("${local.setup_naming_prefix}_${raw_key}"), "/[^a-z0-9_]/", "_"), 0, local.max_table_name_length)
    => raw_key
  }

  all_tables = merge(
    { substr(replace(lower("${local.setup_naming_prefix}_${local.default_partition_name}"), "/[^a-z0-9_]/", "_"), 0, local.max_table_name_length) = var.default_table_setting },
    local.sanitized_partition_tables
  )

  # Seed schema name-mapping for the statically-declared schema fields.
  # Iceberg readers fall back to name-based field resolution when data
  # files lack embedded field IDs in their Parquet metadata. Without this
  # property, Glue Catalog's lowercased column view can mask the canonical
  # case declared in the Iceberg schema, leading to case-mismatch errors
  # at read time.
  #
  # SCOPE: this list mirrors ONLY the fields declared in the schema block
  # in main.tf and is applied once at table creation. Field IDs and names
  # MUST stay in sync with that block — if you add, remove, or rename a
  # field there, mirror the change here.
  #
  # Runtime schema additions (columns added later via Iceberg's
  # UpdateSchema API) auto-extend this property in place via Iceberg
  # core, so only the seed fields are Terraform-managed.
  iceberg_schema_name_mapping = jsonencode([
    { "field-id" = 1, "names" = ["logtype"] },
    { "field-id" = 2, "names" = ["message"] },
    { "field-id" = 3, "names" = ["timestamp"] },
    { "field-id" = 4, "names" = ["guid"] },
  ])

  # Parameters you always want set — user values override these
  default_iceberg_params = {
    "format"                                     = "parquet"
    "write.parquet.compression-codec"            = "zstd"
    "write.target-file-size-bytes"               = "67108864" # 64 MB
    "write.metadata.delete-after-commit.enabled" = "true"
    "write.metadata.previous-versions-max"       = "10"

    # Parquet writer tuning for the Glue compaction job. Enables row-group
    # and page-level predicate pushdown in standard query engines.
    "write.parquet.row-group-size-bytes" = "12582912" # 12 MB
    "write.parquet.page-size-bytes"      = "1048576"  # 1 MB
    "write.parquet.page-version"         = "v2"

    # Manifest hygiene — reduces manifest count growth on high-write tables.
    "commit.manifest-merge.enabled"      = "true"
    "commit.manifest.target-size-bytes"  = "8388608" # 8 MB
    "commit.manifest.min-count-to-merge" = "10"

    # Case-sensitive name → field-ID mapping for data files without field IDs.
    "schema.name-mapping.default" = local.iceberg_schema_name_mapping
  }

  # For each table: defaults ← user params (user wins on overlap)
  resolved_table_params = {
    for k, v in local.all_tables :
    k => merge(local.default_iceberg_params, v.table_parameters)
  }

  # Compaction configuration for each table (used in null_resource provisioner)
  compaction_configs = {
    for k, v in local.all_tables : k => merge(
      { strategy = v.optimizer_configuration.compaction.strategy },
      v.optimizer_configuration.compaction.min_input_files != null
      ? { minInputFiles = v.optimizer_configuration.compaction.min_input_files }
      : {},
      v.optimizer_configuration.compaction.delete_file_threshold != null
      ? { deleteFileThreshold = v.optimizer_configuration.compaction.delete_file_threshold }
      : {}
    )
  }

  # Data retention configuration - enabled when data_retention_enabled is true at setup level
  is_data_retention_enabled = var.data_retention_enabled

  # Map of table names to their retention periods (in days)
  table_retention_days = {
    for k, v in local.all_tables :
    k => v.retention_in_days
  }

  # Glue Iceberg optimizer failure metrics (CloudWatch namespace "Glue").
  # Key = optimizer type (used in alarm naming); value = exact CloudWatch metric name.
  optimizer_failure_metrics = {
    compaction      = "Iceberg table compaction failure"
    retention       = "Iceberg table retention failure"
    orphan_deletion = "Iceberg table orphan_file_deletion failure"
  }

}