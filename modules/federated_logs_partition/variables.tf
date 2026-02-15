variable aws_account_id {
  description = "AWS account ID"
  type        = string
}

variable nr_user_key {
  description = "New Relic user API key"
  type        = string
}

variable log_retention_policy {
  description = "Retention policy for logs in days"
  type        = string
}

variable aws_connection_entity {
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
    enable_compaction           = optional(bool, true)
    enable_retention            = optional(bool, true)
    enable_orphan_file_deletion = optional(bool, true)
    
    orphan_file_deletion = optional(object({
      delete_after_days      = optional(number, 3)
    }), { delete_after_days = 3, job_run_interval_hours = 24 })

    snapshot_retention = optional(object({
      days_snapshot_kept      = optional(number, 5)
      min_snapshots_to_retain = optional(number, 2)
      delete_associated_files = optional(bool, true)
    }), { days_snapshot_kept = 5, min_snapshots_to_retain = 2, delete_associated_files = true })

    compaction_config = optional(object({
      min_input_files       = optional(number, 50)
      delete_file_threshold = optional(number, 5)
    }), { min_input_files = 50, delete_file_threshold = 5 })
  })
}

variable "non_default_tables" {
  description = "Map of extra tables using the exact same structure as the default"
  # We wrap the same object structure in a map()
  type = map(object({
    enable_compaction           = optional(bool, true)
    enable_retention            = optional(bool, true)
    enable_orphan_file_deletion = optional(bool, true)
    
    orphan_file_deletion = optional(object({
      delete_after_days      = optional(number, 3)
    }), { delete_after_days = 3, job_run_interval_hours = 24 })

    snapshot_retention = optional(object({
      days_snapshot_kept      = optional(number, 5)
      min_snapshots_to_retain = optional(number, 2)
      delete_associated_files = optional(bool, true)
    }), { days_snapshot_kept = 5, min_snapshots_to_retain = 2, delete_associated_files = true })

    compaction_config = optional(object({
      min_input_files       = optional(number, 50)
      delete_file_threshold = optional(number, 5)
    }), { min_input_files = 50, delete_file_threshold = 5 })
  }))
  default = {}
}