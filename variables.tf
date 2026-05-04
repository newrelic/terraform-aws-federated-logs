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

variable "clusters" {
  description = "A map of cluster configurations for federated logging. Set auth_mode to 'irsa' (default) or 'pod_identity'. NOTE: 'pod_identity' requires the 'eks-pod-identity-agent' addon to be installed on each cluster — manage that in your EKS cluster module."
  type = map(object({
    auth_mode                = optional(string, "irsa")
    k8s_namespace            = string
    k8s_service_account_name = string
    oidc_provider_arn        = optional(string)
    cluster_name             = optional(string)
  }))
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
  description = "Map of additional partition tables. Each entry can override table_parameters and/or optimizer_configuration, or use {} for all defaults."
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
}

variable "validation_config" {
  description = "Configuration for post-deploy validation checks. Set enabled = true to run resource existence, trust policy, and IAM permission checks on every terraform plan."
  type = object({
    enabled                  = optional(bool, false)
    enable_permission_checks = optional(bool, true)
    enable_oidc_validation   = optional(bool, false)
  })
  default = {}
}