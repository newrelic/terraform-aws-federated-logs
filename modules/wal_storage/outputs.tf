output "ebs_csi_role_arn" {
  description = "ARN of the IRSA role assumed by the aws-ebs-csi-driver controller."
  value       = aws_iam_role.ebs_csi.arn
}

output "ebs_csi_addon_arn" {
  description = "ARN of the aws-ebs-csi-driver EKS addon."
  value       = aws_eks_addon.ebs_csi.arn
}

output "storage_class_name" {
  description = "Name of the StorageClass created for the PCG Federated Logs WAL volume."
  value       = kubernetes_storage_class_v1.wal.metadata[0].name
}
