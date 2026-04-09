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

# =============================================================================
# Flink Application Configuration
# =============================================================================

variable "flink_jar_bucket" {
  description = "S3 bucket containing the Flink application JAR"
  type        = string
}

variable "flink_jar_key" {
  description = "S3 key for the Flink application JAR file"
  type        = string
}

variable "flink_runtime" {
  description = "Flink runtime environment version"
  type        = string
  default     = "FLINK-1_18"
}

variable "parallelism" {
  description = "Flink application parallelism"
  type        = number
  default     = 1
}

variable "checkpoint_interval_ms" {
  description = "Flink checkpoint interval in milliseconds"
  type        = number
  default     = 60000
}

variable "snapshots_enabled" {
  description = "Whether Flink application snapshots are enabled"
  type        = bool
  default     = true
}

# =============================================================================
# SQS Configuration
# =============================================================================

variable "sqs_batch_size" {
  description = "Number of messages to receive per SQS batch"
  type        = number
  default     = 10
}

variable "sqs_visibility_timeout" {
  description = "SQS main queue visibility timeout in seconds"
  type        = number
  default     = 300
}

variable "sqs_message_retention" {
  description = "SQS message retention period in seconds"
  type        = number
  default     = 1209600
}

variable "sqs_max_receive_count" {
  description = "Maximum number of receives before a message is moved to the DLQ"
  type        = number
  default     = 5
}

# =============================================================================
# Monitoring Configuration
# =============================================================================

variable "newrelic_license_key_secret" {
  description = "AWS Secrets Manager secret name for the New Relic license key"
  type        = string
}

variable "newrelic_metrics_endpoint" {
  description = "New Relic metrics API endpoint"
  type        = string
  default     = "https://metric-api.newrelic.com/metric/v1"
}

variable "log_retention_days" {
  description = "CloudWatch log group retention in days"
  type        = number
  default     = 30
}

# =============================================================================
# IAM Configuration
# =============================================================================

variable "flink_role_arn" {
  description = "ARN of the IAM role for the Flink commit worker application"
  type        = string
}

# =============================================================================
# Tags
# =============================================================================

variable "tags" {
  description = "A map of tags to apply to all resources"
  type        = map(string)
  default     = {}
}
