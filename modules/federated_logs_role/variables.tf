variable "s3_bucket_name" {
  description = "Name of the S3 bucket containing logs"
  type        = string
}

variable "glue_catalog_db_name" {
  description = "Name of the Glue catalog database"
  type        = string
}

variable "nr_user_key" {
  description = "New Relic user API key for query access"
  type        = string
}

variable "nr_account_id" {
  description = "New Relic account ID for query access"
  type        = string
}

variable "clusters" {
  description = "A map of cluster configurations for federated logging"
  type = map(object({
    k8s_namespace            = string
    k8s_service_account_name = string
    oidc_provider_arn        = string
  }))

  # Validation: Ensure names aren't empty
  validation {
    condition     = alltrue([for c in var.clusters : length(c.k8s_namespace) > 0 && length(c.k8s_service_account_name) > 0 && length(c.oidc_provider_arn) > 0])
    error_message = "All fields (k8s_namespace, k8s_service_account_name, oidc_provider_arn) must be non-empty for each cluster."
  }
}

