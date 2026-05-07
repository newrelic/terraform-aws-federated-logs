variable "setup_name" {
  description = "A name for this federated logs setup, also used in resource naming."
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,24}[a-z0-9]$", var.setup_name))
    error_message = "The setup_name must be all lowercase and alphanumeric, can contain hyphens but not as the first or last character, and must be between 3 and 26 characters long."
  }
}

variable "s3_bucket_name" {
  description = "Name of the S3 bucket storing federated logs"
  type        = string
}

variable "glue_catalog_db_name" {
  description = "Name of the Glue catalog database"
  type        = string
}

variable "flink_jar_bucket" {
  description = "S3 bucket containing the Flink application JAR"
  type        = string
}

variable "sqs_queue_arn" {
  description = "ARN of the SQS queue for Iceberg file events"
  type        = string
}

variable "secrets_manager_prefix" {
  description = "Secrets Manager path prefix for secrets the Flink commit worker can access"
  type        = string
}

variable "permissions_boundary_arn" {
  description = "ARN of the IAM permissions boundary to attach to roles. If null, no boundary is applied."
  type        = string
  default     = null
}

variable "tags" {
  description = "A map of tags to apply to all resources"
  type        = map(string)
  default     = {}
}
