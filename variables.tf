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

# =============================================================================
# Data Processing (Flink Commit Worker) Configuration
# =============================================================================

variable "flink_jar_bucket" {
  description = "S3 bucket containing the Flink application JAR"
  type        = string
}

variable "flink_jar_key" {
  description = "S3 key for the Flink application JAR file"
  type        = string
}

variable "flink_runtime" {
  description = "Flink runtime environment version"
  type        = string
  default     = "FLINK-1_18"
}

variable "parallelism" {
  description = "Flink application parallelism"
  type        = number
  default     = 1
}

variable "checkpoint_interval_ms" {
  description = "Flink checkpoint interval in milliseconds"
  type        = number
  default     = 60000
}

variable "snapshots_enabled" {
  description = "Whether Flink application snapshots are enabled"
  type        = bool
  default     = true
}

variable "sqs_batch_size" {
  description = "Number of messages to receive per SQS batch"
  type        = number
  default     = 10
}

variable "sqs_visibility_timeout" {
  description = "SQS main queue visibility timeout in seconds"
  type        = number
  default     = 300
}

variable "sqs_message_retention" {
  description = "SQS message retention period in seconds"
  type        = number
  default     = 1209600
}

variable "sqs_max_receive_count" {
  description = "Maximum number of receives before a message is moved to the DLQ"
  type        = number
  default     = 5
}

variable "newrelic_license_key_secret" {
  description = "AWS Secrets Manager secret name for the New Relic license key"
  type        = string
  default     = ""
}

variable "newrelic_metrics_endpoint" {
  description = "New Relic metrics API endpoint"
  type        = string
  default     = "https://metric-api.newrelic.com/metric/v1"
}

variable "log_retention_days" {
  description = "CloudWatch log group retention in days for Flink application"
  type        = number
  default     = 30
}

variable "secrets_manager_prefix" {
  description = "Secrets Manager path prefix for secrets the Flink commit worker can access"
  type        = string
  default     = "pcg/flink-iceberg-commit-worker"
}

variable "permissions_boundary_arn" {
  description = "ARN of the IAM permissions boundary to attach to the Flink role. If null, no boundary is applied."
  type        = string
  default     = null
}

variable "tags" {
  description = "A map of tags to apply to data processing resources"
  type        = map(string)
  default     = {}
}