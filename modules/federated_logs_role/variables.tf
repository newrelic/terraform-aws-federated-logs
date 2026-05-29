variable "s3_bucket_name" {
  description = "Name of the S3 bucket containing logs"
  type        = string
}

variable "glue_catalog_db_name" {
  description = "Name of the Glue catalog database"
  type        = string
}

variable "region" {
  description = "AWS region where resources will be created. If not set, uses the provider's configured region."
  type        = string
  default     = null
}

variable "fleet_entity_guid" {
  description = "NGEP entity GUID of the PCG fleet. Used to resolve the base role ARN via the AWS Connection Entity."
  type        = string
}

variable "newrelic_region" {
  description = "New Relic region: 'US', 'EU', or 'STAGING'. Default mirrors the top-level default (STAGING) so standalone module use lands on the same endpoint."
  type        = string
  default     = "STAGING"
  validation {
    condition     = contains(["US", "EU", "STAGING"], var.newrelic_region)
    error_message = "newrelic_region must be 'US', 'EU', or 'STAGING'."
  }
}

variable "setup_name" {
  description = "A name for this federated logs setup, also used in resource naming."
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,24}[a-z0-9]$", var.setup_name))
    error_message = "The setup_name must be all lowercase and alphanumeric, can contain hyphens but not as the first or last character, and must be between 3 and 26 characters long."
  }
}

variable "newrelic_org_id" {
  description = "New Relic organization ID."
  type        = string
}

variable "default_partition_data_retention_days" {
  description = "Number of days to retain logs in the default partition."
  type        = number
  default     = 30
}

variable "setup_description" {
  description = "Optional description for the newrelic_federated_logs_setup resource."
  type        = string
  default     = null
}

variable "query_connection_description" {
  description = "Optional description for the per-setup newrelic_aws_connection wrapping the reader role."
  type        = string
  default     = null
}
