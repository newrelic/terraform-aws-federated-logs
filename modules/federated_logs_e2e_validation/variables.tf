variable "pcg_endpoint" {
  description = "PCG ingest endpoint URL to POST the test log payload to."
  type        = string
}

variable "nr_account_id" {
  description = "New Relic account ID used to run the NRQL read-back query."
  type        = string
}

variable "nr_region" {
  description = "New Relic region for the GraphQL read-back query. One of: us, eu."
  type        = string
  default     = "us"
  validation {
    condition     = contains(["us", "eu"], var.nr_region)
    error_message = "nr_region must be either 'us' or 'eu'."
  }
}

variable "setup_id" {
  description = "Federated logs setup entity GUID for reporting health status via the federatedLogsUpdateSetup mutation."
  type        = string
  default     = ""
}
