variable "s3_bucket_name" {
  description = "Name of the S3 bucket for table data"
  type        = string
}

variable "glue_catalog_db_name" {
  description = "Name of the Glue catalog database"
  type        = string
}

variable "region" {
  description = "AWS region where resources will be created. If not set, uses the provider's configured region."
  type        = string
  default     = null
}

variable "glue_service_role_arn" {
  description = "ARN of the Glue service role for table maintenance"
  type        = string
}

#──────────────────────────────────────────────────────────────
# Optimizer configuration defaults (for both variables below):
#   orphan_file_deletion:
#     orphan_file_retention_period_in_days = 3
#     run_rate_in_hours                    = 24
#   snapshot_retention:
#     snapshot_retention_period_in_days    = 5
#     number_of_snapshots_to_retain        = 2
#     clean_expired_files                  = false
#     run_rate_in_hours                    = 24
#   compaction:
#     strategy                             = "binpack"
#     min_input_files                      = 5
#     delete_file_threshold                = 1
#──────────────────────────────────────────────────────────────

variable "data_retention_enabled" {
  description = "Enable data retention feature. When true, creates Glue job to delete old data based on per-table retention_in_days."
  type        = bool
  default     = false
}

variable "default_table_setting" {
  description = "Settings for the primary 'Log' table"
  type = object({
    retention_in_days = optional(number, 30)
    table_parameters  = optional(map(string), {})
    optimizer_configuration = optional(object({
      orphan_file_deletion = optional(object({
        orphan_file_retention_period_in_days = optional(number, 3)
        run_rate_in_hours                    = optional(number, 24)
      }), {})
      snapshot_retention = optional(object({
        snapshot_retention_period_in_days = optional(number, 5)
        number_of_snapshots_to_retain     = optional(number, 2)
        clean_expired_files               = optional(bool, false)
        run_rate_in_hours                 = optional(number, 24)
      }), {})

      compaction = optional(object({
        strategy              = optional(string, "binpack")
        min_input_files       = optional(number, 5)
        delete_file_threshold = optional(number, 1)
      }), {})

    }), {})
  })
  default = {}
}

variable "partition_tables" {
  description = "Map of extra tables using the exact same structure as the default"
  type = map(object({
    retention_in_days = optional(number, 30)
    table_parameters  = optional(map(string), {})
    optimizer_configuration = optional(object({
      orphan_file_deletion = optional(object({
        orphan_file_retention_period_in_days = optional(number, 3)
        run_rate_in_hours                    = optional(number, 24)
      }), {})
      snapshot_retention = optional(object({
        snapshot_retention_period_in_days = optional(number, 5)
        number_of_snapshots_to_retain     = optional(number, 2)
        clean_expired_files               = optional(bool, false)
        run_rate_in_hours                 = optional(number, 24)
      }), {})
      compaction = optional(object({
        strategy              = optional(string, "binpack")
        min_input_files       = optional(number, 5)
        delete_file_threshold = optional(number, 1)
      }), {})
    }), {})
  }))
  default = {}

  validation {
    condition     = !contains([for k in keys(var.partition_tables) : lower(k)], "log_federated")
    error_message = "The table name 'Log_Federated' (case-insensitive) is reserved for the default table. Use default_table_setting to configure it."
  }
}

variable "setup_name" {
  description = "A name for this federated logs setup, also used in resource naming."
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,24}[a-z0-9]$", var.setup_name))
    error_message = "The setup_name must be all lowercase and alphanumeric, can contain hyphens but not as the first or last character, and must be between 3 and 26 characters long."
  }
}
