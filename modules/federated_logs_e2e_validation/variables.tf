variable "pcg_endpoint" {
  description = "PCG ingest endpoint URL to POST the test log payload to."
  type        = string
}

variable "nr_account_id" {
  description = "New Relic account ID used to run the NRQL read-back query."
  type        = string
}

variable "nr_region" {
  description = "New Relic region for the GraphQL read-back query. One of: us, eu, staging."
  type        = string
  default     = "us"
  validation {
    condition     = contains(["us", "eu", "staging"], var.nr_region)
    error_message = "nr_region must be one of: us, eu, staging."
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
  description = "Maximum number of retry attempts for transient HTTP errors."
  type        = number
  default     = 3
}

variable "retry_delay" {
  description = "Seconds to wait between retry attempts."
  type        = number
  default     = 5
}

variable "initial_read_wait" {
  description = "Seconds to wait after writing before querying New Relic for the test log."
  type        = number
  default     = 30
}
