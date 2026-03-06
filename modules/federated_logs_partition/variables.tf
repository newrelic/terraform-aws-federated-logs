variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}

variable "nr_user_api_key" {
  description = "New Relic user API key"
  type        = string
}

variable "log_retention_policy" {
  description = "Retention policy for logs in days"
  type        = string
}

variable "aws_connection_entity" {
  description = "Entity for AWS connection"
  type        = string
}

variable "s3_bucket_name" {
  description = "Name of the S3 bucket for table data"
  type        = string
}

variable "glue_catalog_db_name" {
  description = "Name of the Glue catalog database"
  type        = string
}

variable "glue_service_role_arn" {
  description = "ARN of the Glue service role for table maintenance"
  type        = string
}

variable "default_table_setting" {
  description = "Settings for the primary 'Log' table"
  type = object({
    table_parameters = optional(object({
      format                                     = optional(string, "parquet")
      write_target_file_size_bytes               = optional(string, "26214400")
      write_metadata_delete_after_commit_enabled = optional(bool, true)
      write_metadata_previous_versions_max       = optional(string, "10")
      }), {
      write_target_file_size_bytes               = "26214400"
      write_metadata_delete_after_commit_enabled = true
      write_metadata_previous_versions_max       = "10"
    })
    optimizer_configuration = optional(object({
      orphan_file_deletion = optional(object({
        orphan_file_retention_period_in_days = optional(number, 3)
        run_rate_in_hours                    = optional(number, 24)
      }), { orphan_file_retention_period_in_days = 3, run_rate_in_hours = 24 })

      snapshot_retention = optional(object({
        snapshot_retention_period_in_days = optional(number, 5)
        number_of_snapshots_to_retain     = optional(number, 2)
        clean_expired_files               = optional(bool, false)
        run_rate_in_hours                 = optional(number, 24)
      }), { snapshot_retention_period_in_days = 5, number_of_snapshots_to_retain = 2, clean_expired_files = false, run_rate_in_hours = 24 })

      }), {
      orphan_file_deletion = { orphan_file_retention_period_in_days = 3, run_rate_in_hours = 24 }
      snapshot_retention   = { snapshot_retention_period_in_days = 5, number_of_snapshots_to_retain = 2, clean_expired_files = false, run_rate_in_hours = 24 }
    })
  })
  default = {}
}

variable "partition_tables" {
  description = "Map of extra tables using the exact same structure as the default"
  # We wrap the same object structure in a map()
  type = map(object({
    table_parameters = optional(object({
      format                                     = optional(string, "parquet")
      write_target_file_size_bytes               = optional(string, "26214400")
      write_metadata_delete_after_commit_enabled = optional(bool, true)
      write_metadata_previous_versions_max       = optional(string, "10")
      }), {
      write_target_file_size_bytes               = "26214400"
      write_metadata_delete_after_commit_enabled = true
      write_metadata_previous_versions_max       = "10"
    })
    optimizer_configuration = optional(object({
      orphan_file_deletion = optional(object({
        orphan_file_retention_period_in_days = optional(number, 3)
        run_rate_in_hours                    = optional(number, 24)
      }), { orphan_file_retention_period_in_days = 3, run_rate_in_hours = 24 })

      snapshot_retention = optional(object({
        snapshot_retention_period_in_days = optional(number, 5)
        number_of_snapshots_to_retain     = optional(number, 2)
        clean_expired_files               = optional(bool, false)
        run_rate_in_hours                 = optional(number, 24)
      }), { snapshot_retention_period_in_days = 5, number_of_snapshots_to_retain = 2, clean_expired_files = false, run_rate_in_hours = 24 })

      }), {
      orphan_file_deletion = { orphan_file_retention_period_in_days = 3, run_rate_in_hours = 24 }
      snapshot_retention   = { snapshot_retention_period_in_days = 5, number_of_snapshots_to_retain = 2, clean_expired_files = false, run_rate_in_hours = 24 }
    })
  }))
  default = {}

  validation {
    condition     = !contains([for k in keys(var.partition_tables) : lower(k)], "log_federated")
    error_message = "The table name 'Log_Federated' (case-insensitive) is reserved for the default table. Use default_table_setting to configure it."
  }
}

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
}

variable "resource_naming_prefix" {
  description = "Lowercase alphanumeric prefix for all resources (e.g., 'acmelogs2026')"
  default     = "nr"
  type        = string
  validation {
    # ^[a-z]       -> Must start with a lowercase letter
    # [a-z0-9]{2,39} -> Followed by 2 to 39 alphanumeric chars
    # $            -> End of string
    condition     = can(regex("^[a-z][a-z0-9]{2,39}$", var.resource_naming_prefix))
    error_message = "The naming_prefix must start with a lowercase letter (a-z) and contain only lowercase letters and numbers (3-40 characters total)."
  }
}