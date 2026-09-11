variable "setup_name" {
  description = "A name for this federated logs setup, also used in resource naming."
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,24}[a-z0-9]$", var.setup_name))
    error_message = "The setup_name must be all lowercase and alphanumeric, can contain hyphens but not as the first or last character, and must be between 3 and 26 characters long."
  }
}

variable "region" {
  description = "AWS region where resources will be created. If not set, uses the provider's configured region."
  type        = string
  default     = null
}

variable "force_destroy" {
  description = "When true, `aws_s3_bucket.force_destroy` is enabled so the bucket can be deleted even when it holds objects, and a destroy-time guard permits `terraform destroy`. Default false keeps the bucket delete-protected as long as it has content."
  type        = bool
  default     = false
}
