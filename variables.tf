# Input variables for the root module

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "naming_prefix" {
  description = "Prefix for naming Federated logs related AWS resources"
  type        = string
  default     = "nr-fed-logs"
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

variable "non_default_tables" {
  description = "Map of non-default table configurations"
  type = map(object({
    enable_compaction           = bool
    enable_retention            = bool
    enable_orphan_file_deletion = bool
    orphan_file_deletion = object({
      delete_after_days = number
    })
    snapshot_retention = object({
      days_snapshot_kept      = number
      min_snapshots_to_retain = number
      delete_associated_files = bool
    })
    compaction_config = object({
      min_input_files       = number
      delete_file_threshold = number
    })
  }))
}