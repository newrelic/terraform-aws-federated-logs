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
  description = "NGEP entity GUID of the fleet."
  type        = string
}

variable "newrelic_org_id" {
  description = "New Relic organization ID"
  type        = string
}


variable "newrelic_region" {
  description = "New Relic region"
  type        = string
  default     = "US"
  validation {
    condition     = contains(["US", "EU", "STAGING"], var.newrelic_region)
    error_message = "newrelic_region must be 'US', 'EU', or 'STAGING'."
  }
}

variable "fleet_ingest_connection_description" {
  description = "Optional description for the fleet-level newrelic_aws_connection wrapping the PCG base role."
  type        = string
  default     = null
}

# =============================================================================
# FLINK VARIABLES
# =============================================================================

variable "flink_iceberg_commit_worker_version" {
  description = "Version of the flink-iceberg-commit-worker JAR to deploy (e.g. v1.0.0). Defaults to latest."
  type        = string
  default     = "latest"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]+$", var.flink_iceberg_commit_worker_version))
    error_message = "Version must contain only alphanumeric characters, dots, hyphens, and underscores."
  }
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

variable "start_application" {
  description = "Whether to start the Flink application immediately after creation. When true, Terraform transitions the app from READY to RUNNING. Requires kinesisanalyticsv2:StartApplication on the deploying role."
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
# E2E VALIDATION (optional)
# =============================================================================

variable "e2e_validation_config" {
  description = "Configuration for the optional end-to-end validation, run from the data_processing (fleet/PCG) account. When enabled=true, deploys an AWS Lambda inside your VPC that POSTs a synthetic log to PCG, polls NRDB for the log, and reports HEALTHY/UNHEALTHY back to New Relic via the federatedLogsUpdateSetup mutation. Credentials are sourced from NEW_RELIC_LICENSE_KEY and NEW_RELIC_API_KEY env vars on the runner. Unlike the federated_logs setup module, data_processing cannot derive setup_id / nr_account_id (the setup lives in the storage account), so both must be supplied here — copy setup_id from the federated_logs deploy's newrelic_federated_logs_setup_id output. nr_region reuses this module's newrelic_region."
  type = object({
    enabled      = optional(bool, false)
    pcg_endpoint = optional(string, "")
    test_payload = optional(string, "")

    # Cross-account: these cannot be derived here — the setup lives in the
    # storage account. setup_id comes from the federated_logs apply output
    # (newrelic_federated_logs_setup_id); nr_account_id is your NR account ID.
    setup_id      = optional(string, "")
    nr_account_id = optional(number)

    vpc_config = optional(object({
      subnet_ids         = list(string)
      security_group_ids = list(string)
    }))

    lambda_timeout     = optional(number, 180)
    lambda_memory_size = optional(number, 256)

    # Script retry/poll knobs (script defaults apply when omitted).
    max_retries       = optional(number, 3)
    retry_delay       = optional(number, 5)
    initial_read_wait = optional(number, 30)
    read_max_retries  = optional(number, 5)
    read_retry_delay  = optional(number, 15)
  })
  default = {}

  validation {
    condition = !var.e2e_validation_config.enabled || (
      var.e2e_validation_config.pcg_endpoint != "" &&
      var.e2e_validation_config.test_payload != "" &&
      var.e2e_validation_config.vpc_config != null &&
      var.e2e_validation_config.setup_id != "" &&
      var.e2e_validation_config.nr_account_id != null
    )
    error_message = "When e2e_validation_config.enabled is true, pcg_endpoint, test_payload, vpc_config, setup_id, and nr_account_id must all be provided."
  }
}

# =============================================================================
# TAGS
# =============================================================================

variable "tags" {
  description = "A map of tags to apply to all resources."
  type        = map(string)
  default     = {}
}
