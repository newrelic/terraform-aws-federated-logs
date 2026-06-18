variable "setup_name" {
  description = "Setup name."
  type        = string
}

variable "data_processing_name" {
  description = "Name for the data_processing module."
  type        = string
}

variable "fleet_entity_guid" {
  description = "Pre-provisioned NGEP fleet entity GUID."
  type        = string
}

variable "newrelic_org_id" {
  description = "New Relic org ID."
  type        = string
}

variable "newrelic_account_id" {
  description = "New Relic account ID."
  type        = number
}

variable "newrelic_region" {
  description = "New Relic region: 'US', 'EU', or 'STAGING'."
  type        = string
  default     = "US"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "default_table_setting" {
  description = "Settings for the primary federated log table."
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
  description = "Map of additional partition tables."
  type = map(object({
    retention_in_days  = optional(number, 30)
    routing_expression = optional(string)
    description        = optional(string)
    table_parameters   = optional(map(string), {})
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
}
