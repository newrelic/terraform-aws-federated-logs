variable "s3_bucket_name" {
  description = "Name of the S3 bucket where federated logs land."
  type        = string
}

variable "glue_catalog_db_name" {
  description = "Glue catalog database name (used as S3 prefix for test log)."
  type        = string
}

variable "newrelic_account_id" {
  description = "New Relic account ID to validate log queryability."
  type        = number
}

variable "newrelic_user_api_key" {
  description = "New Relic User API key (NerdGraph). Marked sensitive."
  type        = string
  sensitive   = true
}

variable "newrelic_region" {
  description = "New Relic region: US or EU."
  type        = string
  default     = "US"
  validation {
    condition     = contains(["US", "EU"], var.newrelic_region)
    error_message = "newrelic_region must be US or EU."
  }
}

variable "run_validation" {
  description = "Set to true to trigger the end-to-end validation. False by default so it never runs unless explicitly requested."
  type        = bool
  default     = false
}

variable "validation_run_id" {
  description = "A unique token to force re-execution (e.g. a timestamp). Change this value each time you want a fresh run."
  type        = string
  default     = ""
}

variable "max_wait_seconds" {
  description = "Maximum time (seconds) to wait for log to appear in New Relic."
  type        = number
  default     = 300
}

variable "poll_interval_seconds" {
  description = "Seconds between New Relic polling attempts."
  type        = number
  default     = 15
}
