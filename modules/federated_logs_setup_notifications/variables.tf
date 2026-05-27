variable "setup_name" {
  description = "Name of the federated logs setup, used in resource naming."
  type        = string
}

variable "s3_bucket_id" {
  description = "ID of the S3 bucket to enable EventBridge notifications on."
  type        = string
}

variable "pcg_writer_role_arn" {
  description = "ARN of the PCG writer IAM role. Injected into EventBridge message for Flink commit worker to AssumeRole."
  type        = string
}

variable "fleet_entity_guid" {
  description = "NGEP entity GUID of the fleet. Used to look up the SQS queue ARN from the AWS Connection Entity."
  type        = string
}

variable "newrelic_region" {
  description = "New Relic region: 'US', 'EU', or 'STAGING'."
  type        = string
  default     = "US"
  validation {
    condition     = contains(["US", "EU", "STAGING"], var.newrelic_region)
    error_message = "newrelic_region must be 'US', 'EU', or 'STAGING'."
  }
}
