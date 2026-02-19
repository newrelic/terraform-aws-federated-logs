variable "resource_naming_prefix" {
  description = "Mandatory lowercase alphanumeric prefix for all resources (e.g., 'acmelogs2026')"
  type        = string
  validation {
    # ^[a-z]       -> Must start with a lowercase letter
    # [a-z0-9]{2,39} -> Followed by 2 to 39 alphanumeric chars
    # $            -> End of string
    condition     = can(regex("^[a-z][a-z0-9]{2,39}$", var.resource_naming_prefix))
    error_message = "The naming_prefix must start with a lowercase letter (a-z) and contain only lowercase letters and numbers (3-40 characters total)."
  }
}

variable "aws_account_id" {
  description = "The AWS account ID."
  type        = string
}

variable "aws_region" {
  description = "The AWS region to deploy resources in."
  type        = string
}

variable "setup_name" {
  description = "A name for this federated logs setup, used in tagging and resource naming."
  type        = string
}