variable "pcg_endpoint" {
  description = "PCG ingest endpoint URL to POST the test log payload to."
  type        = string
}

variable "nr_account_id" {
  description = "New Relic account ID used to run the NRQL read-back query."
  type        = number
}

variable "nr_region" {
  description = "New Relic region for the GraphQL read-back query. One of: US, EU, STAGING."
  type        = string
  default     = "US"
  validation {
    condition     = contains(["US", "EU", "STAGING"], var.nr_region)
    error_message = "nr_region must be one of: US, EU, STAGING."
  }
}

variable "setup_id" {
  description = "Federated logs setup entity GUID for reporting health status via the federatedLogsUpdateSetup mutation."
  type        = string
}

variable "test_payload" {
  description = "JSON log payload to POST to the PCG endpoint during E2E validation."
  type        = string
}

variable "max_retries" {
  description = "Maximum number of retry attempts for transient HTTP errors (5xx / connection failures) on health, write, and mutation calls."
  type        = number
  default     = 3
}

variable "retry_delay" {
  description = "Seconds to wait between transient HTTP retry attempts."
  type        = number
  default     = 5
}

variable "initial_read_wait" {
  description = "Seconds to wait after writing before the first NRQL read attempt."
  type        = number
  default     = 30
}

variable "read_max_retries" {
  description = "Maximum number of NRQL read attempts when the test log has not yet appeared in New Relic. Each attempt is separated by read_retry_delay seconds."
  type        = number
  default     = 5
}

variable "read_retry_delay" {
  description = "Seconds to wait between NRQL read attempts when polling for the test log to surface."
  type        = number
  default     = 15
}

# =============================================================================
# Lambda + VPC + Secrets configuration
# =============================================================================

variable "vpc_config" {
  description = "VPC subnets and security groups the validation Lambda will be attached to."
  type = object({
    subnet_ids         = list(string)
    security_group_ids = list(string)
  })

  validation {
    condition     = length(var.vpc_config.subnet_ids) > 0 && length(var.vpc_config.security_group_ids) > 0
    error_message = "vpc_config.subnet_ids and vpc_config.security_group_ids must each have at least one entry."
  }
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds. Default 180 covers the worst case: cold start (~5s) + health (~2s) + write (~2s) + initial_read_wait (30s) + read_max_retries × read_retry_delay (75s) + mutation (~2s) ≈ 120s, with headroom."
  type        = number
  default     = 180

  validation {
    condition     = var.lambda_timeout >= 60 && var.lambda_timeout <= 900
    error_message = "lambda_timeout must be between 60 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Lambda function memory size in MB. 256 is sufficient for boto3 + the script's stdlib HTTP calls."
  type        = number
  default     = 256
}
