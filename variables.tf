# Input variables for the root module

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "aws_account_id" {
  description = "AWS account ID where resources will be deployed"
  type        = string
}

variable "clusters" {
  description = "Map of cluster configurations for PCG writer role authentication"
  type = map(object({
    k8s_namespace            = string
    k8s_service_account_name = string
    oidc_provider_arn        = string
  }))
}

variable "partition_tables" {
  description = "Map of non-default table configurations"
  type = map(object({
    orphan_file_deletion = object({
      delete_after_days = number
    })
    snapshot_retention = object({
      snapshot_retention_period_in_days = number
      number_of_snapshots_to_retain     = number
      clean_expired_files               = bool
    })
    compaction_config = object({
      min_input_files       = number
      delete_file_threshold = number
    })
  }))
}

variable "setup_name" {
  description = "A name for this federated logs setup, used in tagging and resource naming."
  type        = string
  default     = "test-fed-logs-setup"
}

variable "resource_naming_prefix" {
  description = "The prefix for resource names."
  type        = string
}
