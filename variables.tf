variable "region" {
  description = "AWS region where resources will be created. If not set, uses the provider's configured region."
  type        = string
  default     = null
}

variable "setup_name" {
  description = "A name for this federated logs setup, also used in resource naming."
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,24}[a-z0-9]$", var.setup_name))
    error_message = "The setup_name must be all lowercase and alphanumeric, can contain hyphens but not as the first or last character, and must be between 3 and 26 characters long."
  }
}

variable "fleet_entity_guid" {
  description = "NGEP entity GUID of the PCG fleet (output of the data_processing module)."
  type        = string
}

variable "newrelic_org_id" {
  description = "New Relic organization ID."
  type        = string
}

variable "newrelic_account_id" {
  description = "New Relic account ID."
  type        = number
}

variable "setup_description" {
  description = "Optional description for the newrelic_federated_logs_setup resource."
  type        = string
  default     = null
}

variable "query_connection_description" {
  description = "Optional description for the per-setup newrelic_aws_connection wrapping the reader role."
  type        = string
  default     = null
}

variable "newrelic_region" {
  description = "New Relic region: 'US', 'EU', or 'STAGING'."
  type        = string
  default     = "US"
  validation {
    condition     = contains(["US", "EU", "STAGING"], var.newrelic_region)
    error_message = "newrelic_region must be 'US', 'EU', or 'STAGING'."
  }
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
  description = "Settings for the primary federated log table, including Iceberg table parameters and optimizer configuration"
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
  description = "Map of additional partition tables. Each entry can override table_parameters, optimizer_configuration, routing_expression, and/or description — or use {} for all defaults."
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

