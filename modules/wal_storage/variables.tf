variable "wal_storage_module_name" {
  description = "Short suffix used to name the resources this module creates (IAM role, etc.). Keep it stable and unique per cluster."
  type        = string

  validation {
    condition     = length(var.wal_storage_module_name) > 0 && length(var.wal_storage_module_name) <= 38
    error_message = "wal_storage_module_name must be non-empty and at most 38 characters (IAM role name length budget)."
  }
}

variable "cluster_name" {
  description = "Name of the EKS cluster to install the aws-ebs-csi-driver addon into."
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the cluster's IAM OIDC provider (arn:aws:iam::<account>:oidc-provider/oidc.eks.<region>.amazonaws.com/id/<id>). Used to grant the EBS CSI controller service account credentials via IRSA, so no node-role policy or IMDS hop-limit change is required."
  type        = string
}

variable "storage_class_name" {
  description = "Name of the StorageClass the PCG Federated Logs WAL uses. Must match the storageClassName the pipeline-control-gateway chart requests for the WAL volume (gp3-wal)."
  type        = string
  default     = "gp3-wal"
}

variable "volume_type" {
  description = "EBS volume type for the WAL StorageClass."
  type        = string
  default     = "gp3"
}

variable "encrypted" {
  description = "Whether volumes provisioned by the WAL StorageClass are EBS-encrypted."
  type        = bool
  default     = true
}

variable "kms_key_id" {
  description = "Optional KMS key ID/ARN for WAL volume encryption. When null, the account's default EBS encryption key is used."
  type        = string
  default     = null
}

variable "make_default_storage_class" {
  description = "Whether to mark the WAL StorageClass as the cluster default. Leave false so it does not affect other workloads."
  type        = bool
  default     = false
}

variable "ebs_csi_addon_version" {
  description = "Optional aws-ebs-csi-driver addon version to pin (e.g. v1.38.1-eksbuild.2). When null, EKS selects the default version for the cluster."
  type        = string
  default     = null
}

variable "ebs_csi_service_account_namespace" {
  description = "Namespace of the EBS CSI controller service account (used in the IRSA trust condition)."
  type        = string
  default     = "kube-system"
}

variable "ebs_csi_service_account_name" {
  description = "Name of the EBS CSI controller service account (used in the IRSA trust condition)."
  type        = string
  default     = "ebs-csi-controller-sa"
}

variable "tags" {
  description = "Additional tags applied to the IAM role and EKS addon."
  type        = map(string)
  default     = {}
}
