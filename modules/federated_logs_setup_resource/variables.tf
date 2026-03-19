variable "aws_region" {
  description = "The AWS region to deploy resources in."
  type        = string
  default = null
}

variable "setup_name" {
  description = "A name for this federated logs setup, also used in resource naming."
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{1,33}[a-z0-9])?$", var.setup_name))
    error_message = "The setup_name must be all lowercase and alphanumeric, can contain hyphens but not as the first or last character, and must be between 3 and 35 characters long."
  }
}