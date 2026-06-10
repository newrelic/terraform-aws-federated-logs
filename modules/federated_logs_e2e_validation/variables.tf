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
