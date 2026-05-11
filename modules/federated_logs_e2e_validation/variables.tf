variable "pcg_endpoint" {
  description = "PCG ingest endpoint URL to POST the test log payload to."
  type        = string
}

variable "license_key" {
  description = "New Relic license/ingest key used to authenticate the PCG write."
  type        = string
  sensitive   = true
}

variable "partition_name" {
  description = "Target partition (Iceberg table) name the test log is routed into. Must match a table created by the federated_logs_partition module."
  type        = string
}

variable "nr_account_id" {
  description = "New Relic account ID used to run the NRQL read-back query."
  type        = string
}

variable "nr_api_key" {
  description = "New Relic User API key (NRAK-...) used for the GraphQL/NRQL query."
  type        = string
  sensitive   = true
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
