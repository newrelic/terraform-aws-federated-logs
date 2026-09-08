# PCG Federated Logs WAL — cluster storage prerequisites.
#
# The WAL durability architecture attaches a per-pod ephemeral EBS volume to the
# pipeline-control-gateway Deployment (see the pipeline-control-gateway Helm chart,
# `wal.enabled`). For that to work the cluster needs:
#   1. the aws-ebs-csi-driver EKS addon (to dynamically provision EBS volumes), and
#   2. a StorageClass named `gp3-wal` backed by ebs.csi.aws.com.
#
# This module provisions both, granting the EBS CSI controller AWS permissions via
# IRSA (a dedicated OIDC-federated role) rather than the node instance role. That is
# the recommended pattern and avoids the IMDSv2 hop-limit pitfall that otherwise
# leaves the controller unable to fetch credentials on default managed nodegroups.

locals {
  naming_prefix = "newrelic-fed-logs-wal-${var.wal_storage_module_name}"

  # Strip the "arn:aws:iam::<account>:oidc-provider/" prefix to get the issuer host/path,
  # which is the condition-key prefix for the IRSA trust policy. Mirrors data_processing.
  oidc_issuer = replace(var.oidc_provider_arn, "/^arn:aws:iam::.*:oidc-provider//", "")
}

# IRSA role assumed by the EBS CSI controller service account.
resource "aws_iam_role" "ebs_csi" {
  name        = "${local.naming_prefix}-ebs-csi"
  description = "IRSA role for the aws-ebs-csi-driver controller, used by the PCG Federated Logs WAL storage class."

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRoleWithWebIdentity"
        Principal = {
          Federated = var.oidc_provider_arn
        }
        Condition = {
          StringEquals = {
            "${local.oidc_issuer}:sub" = "system:serviceaccount:${var.ebs_csi_service_account_namespace}:${var.ebs_csi_service_account_name}"
            "${local.oidc_issuer}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# aws-ebs-csi-driver EKS addon, wired to the IRSA role above.
resource "aws_eks_addon" "ebs_csi" {
  cluster_name             = var.cluster_name
  addon_name               = "aws-ebs-csi-driver"
  addon_version            = var.ebs_csi_addon_version
  service_account_role_arn = aws_iam_role.ebs_csi.arn

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = var.tags

  depends_on = [aws_iam_role_policy_attachment.ebs_csi]
}

# StorageClass the PCG WAL volume is provisioned from. WaitForFirstConsumer so each
# per-pod volume is created in the pod's AZ (single-attach, no Multi-Attach).
resource "kubernetes_storage_class_v1" "wal" {
  metadata {
    name = var.storage_class_name
    annotations = var.make_default_storage_class ? {
      "storageclass.kubernetes.io/is-default-class" = "true"
    } : {}
  }

  storage_provisioner    = "ebs.csi.aws.com"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true
  reclaim_policy         = "Delete"

  parameters = merge(
    {
      type      = var.volume_type
      encrypted = tostring(var.encrypted)
    },
    var.kms_key_id == null ? {} : { kmsKeyId = var.kms_key_id }
  )

  depends_on = [aws_eks_addon.ebs_csi]
}
