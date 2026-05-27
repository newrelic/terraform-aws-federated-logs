variable "data_processing_module_name" {
  description = "Name for this data processing setup. Used in resource naming."
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,24}[a-z0-9]$", var.data_processing_module_name))
    error_message = "data_processing_module_name must be lowercase alphanumeric with hyphens (not first/last), 3–26 chars."
  }
}

variable "clusters" {
  description = "Map of EKS cluster configs used to build the base role trust policy. All clusters must share the same auth_mode."
  type = map(object({
    auth_mode                = optional(string, "irsa") # "irsa" or "pod_identity"
    k8s_namespace            = string
    k8s_service_account_name = string
    oidc_provider_arn        = optional(string) # Required when auth_mode = "irsa"
    cluster_name             = optional(string) # Required when auth_mode = "pod_identity"
  }))

  validation {
    condition     = alltrue([for c in var.clusters : length(c.k8s_namespace) > 0 && length(c.k8s_service_account_name) > 0])
    error_message = "k8s_namespace and k8s_service_account_name must be non-empty for each cluster."
  }

  validation {
    condition     = alltrue([for c in var.clusters : contains(["irsa", "pod_identity"], c.auth_mode)])
    error_message = "auth_mode must be either 'irsa' or 'pod_identity'."
  }

  validation {
    condition     = length(distinct([for c in var.clusters : c.auth_mode])) <= 1
    error_message = "All clusters must use the same auth_mode. Mixing 'irsa' and 'pod_identity' is not supported."
  }

  validation {
    condition     = alltrue([for c in var.clusters : c.auth_mode != "irsa" || try(length(c.oidc_provider_arn) > 0, false)])
    error_message = "oidc_provider_arn must be set for clusters using auth_mode = 'irsa'."
  }

  validation {
    condition     = alltrue([for c in var.clusters : c.auth_mode != "pod_identity" || try(length(c.cluster_name) > 0, false)])
    error_message = "cluster_name must be set for clusters using auth_mode = 'pod_identity'."
  }
}

variable "fleet_entity_guid" {
  description = "NGEP entity GUID of the fleet (e.g. FederatedLogsDataProcessingEntity). A relationship of type HAS_FED_LOGS_BASE_ROLE will be created from this entity to the AWS Connection Entity."
  type        = string
}

variable "newrelic_org_id" {
  description = "New Relic organization ID (GUID) used to scope NGEP entities at the ORGANIZATION level."
  type        = string
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

# =============================================================================
# FLINK VARIABLES
# =============================================================================

variable "flink_iceberg_commit_worker_version" {
  description = "Version of the flink-iceberg-commit-worker JAR to deploy (e.g. v1.0.0). Defaults to latest."
  type        = string
  default     = "latest"
}

variable "flink_jar_bucket" {
  description = "S3 bucket in customer's AWS account where the Flink JAR will be copied. The Flink application will read the JAR from this bucket."
  type        = string
}

variable "flink_runtime" {
  description = "Flink runtime environment version."
  type        = string
  default     = "FLINK-1_18"
}

variable "parallelism" {
  description = "Flink application parallelism."
  type        = number
  default     = 1
}

variable "parallelism_per_kpu" {
  description = "Parallelism per KPU."
  type        = number
  default     = 1
}

variable "auto_scaling_enabled" {
  description = "Enable Flink auto-scaling."
  type        = bool
  default     = true
}

variable "checkpoint_interval_ms" {
  description = "Flink checkpoint interval in milliseconds."
  type        = number
  default     = 60000
}

variable "snapshots_enabled" {
  description = "Whether Flink application snapshots are enabled."
  type        = bool
  default     = true
}

variable "newrelic_metrics_endpoint" {
  description = "New Relic metrics API endpoint."
  type        = string
  default     = "https://metric-api.newrelic.com/metric/v1"
}

variable "log_retention_days" {
  description = "CloudWatch log group retention in days."
  type        = number
  default     = 30
}

# =============================================================================
# SQS VARIABLES
# =============================================================================

variable "sqs_batch_size" {
  description = "Number of messages to receive per SQS batch."
  type        = number
  default     = 10
}

variable "sqs_visibility_timeout" {
  description = "SQS main queue visibility timeout in seconds."
  type        = number
  default     = 300
}

variable "sqs_message_retention" {
  description = "SQS message retention period in seconds."
  type        = number
  default     = 1209600
}

variable "sqs_max_receive_count" {
  description = "Maximum number of receives before a message is moved to the DLQ (CDD recommends 3)."
  type        = number
  default     = 3
}

# =============================================================================
# CROSS-ACCOUNT SUPPORT
# =============================================================================

variable "allowed_source_account_ids" {
  description = "Additional AWS account IDs allowed to send EventBridge events to the SQS queue. Use this when federated_logs_setup_resource is deployed in different accounts. The current account is always included automatically."
  type        = list(string)
  default     = []
}

# =============================================================================
# TAGS
# =============================================================================

variable "tags" {
  description = "A map of tags to apply to all resources."
  type        = map(string)
  default     = {}
}
