variable "s3_bucket_name" {
  description = "Name of the S3 bucket storing federated logs (from module output)"
  type        = string
}

variable "glue_database_name" {
  description = "Name of the Glue catalog database (from module output)"
  type        = string
}

variable "glue_service_role_arn" {
  description = "ARN of the Glue service IAM role (from module output)"
  type        = string
}

variable "pcg_writer_role_arn" {
  description = "ARN of the PCG writer IAM role (from module output)"
  type        = string
}

variable "nr_reader_role_arn" {
  description = "ARN of the New Relic reader IAM role (from module output)"
  type        = string
}

variable "enable_permission_checks" {
  description = "Enable IAM policy simulation checks. Requires iam:SimulatePrincipalPolicy permission on the Terraform execution identity. Set to false if this permission cannot be granted."
  type        = bool
  default     = true
}
