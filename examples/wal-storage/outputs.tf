output "ebs_csi_role_arn" {
  description = "ARN of the IRSA role assumed by the aws-ebs-csi-driver controller."
  value       = module.wal_storage.ebs_csi_role_arn
}

output "storage_class_name" {
  description = "Name of the StorageClass created for the PCG Federated Logs WAL volume."
  value       = module.wal_storage.storage_class_name
}
