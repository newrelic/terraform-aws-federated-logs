# PCG Federated Logs WAL — cluster storage prerequisites.
#
# Run this once per EKS cluster that will run the PCG gateway with the WAL
# durability architecture enabled. It installs the aws-ebs-csi-driver addon
# (via IRSA) and creates the `gp3-wal` StorageClass the gateway's WAL volume
# is provisioned from. After applying, enable `wal` from Fleet Control and deploy.

module "wal_storage" {
  source = "../../modules/wal_storage"

  wal_storage_module_name = "my-app-logs"
  cluster_name            = var.cluster_name
  oidc_provider_arn       = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-2.amazonaws.com/id/EXAMPLE"

  # Optional — defaults shown:
  # storage_class_name         = "gp3-wal"   # must match the pipeline-control-gateway chart's WAL storageClassName
  # volume_type                = "gp3"
  # encrypted                  = true
  # kms_key_id                 = null        # null = account default EBS encryption key
  # make_default_storage_class = false
  # ebs_csi_addon_version      = null        # null = EKS-selected default version

  tags = {
    team = "federated-logs"
  }
}
