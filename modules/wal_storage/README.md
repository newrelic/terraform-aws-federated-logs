# wal_storage

Cluster storage prerequisites for the PCG **Federated Logs WAL** (write-ahead-log)
durability architecture.

When WAL is enabled, the `pipeline-control-gateway` Helm chart attaches a per-pod
**ephemeral EBS volume** to the gateway Deployment and mounts it at `/var/wal`. The
iceberg exporter buffers records to that disk and drains them to S3, so records
survive pod restarts instead of living only in memory. For the volume to provision,
the EKS cluster needs two things this module creates:

1. the **`aws-ebs-csi-driver`** EKS addon (dynamic EBS provisioning), and
2. a **StorageClass named `gp3-wal`** backed by `ebs.csi.aws.com` — the exact name the
   chart requests for the WAL volume.

## Why this module exists

Without it, these steps are done by hand (`aws eks create-addon`, attaching
`AmazonEBSCSIDriverPolicy`, `kubectl apply` a StorageClass), and on a default managed
nodegroup the EBS CSI **controller cannot fetch AWS credentials** — it falls back to
IMDS, which is blocked by the default hop limit of 1, and CrashLoops. The usual manual
workaround is bumping the instance metadata hop limit to 2.

This module avoids that entirely by giving the EBS CSI controller its own **IRSA role**
(`service_account_role_arn` on the addon), the AWS-recommended pattern. No node-role
policy attachment and no IMDS hop-limit change are needed.

## What it creates

| Resource | Replaces the manual step |
|---|---|
| `aws_iam_role.ebs_csi` (+ `AmazonEBSCSIDriverPolicy` attachment) | `aws iam attach-role-policy ... AmazonEBSCSIDriverPolicy` (but scoped to an IRSA role, not the node role) |
| `aws_eks_addon.ebs_csi` (wired to the IRSA role) | `aws eks create-addon --addon-name aws-ebs-csi-driver` |
| `kubernetes_storage_class_v1.wal` (`gp3-wal`) | `kubectl apply` of the `gp3-wal` StorageClass |
| — (IRSA removes the need) | `aws ec2 modify-instance-metadata-options --http-put-response-hop-limit 2` |

## Providers

Because it creates a StorageClass, this module needs a **`kubernetes`** provider pointed
at the target cluster, in addition to `aws`. See `examples/wal-storage` for wiring the
kubernetes provider from the EKS cluster data sources.

## Usage

```hcl
module "wal_storage" {
  source = "github.com/newrelic/terraform-aws-federated-logs//modules/wal_storage?ref=<tag>"

  wal_storage_module_name = "my-app-logs"
  cluster_name            = "my-eks-cluster"
  oidc_provider_arn       = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-2.amazonaws.com/id/EXAMPLE"
}
```

Apply this once per cluster **before** enabling WAL from Fleet Control. It is independent
of the `data_processing` and root (`federated_logs`) modules and can run before or after
them.

## Inputs

| Name | Description | Default |
|---|---|---|
| `wal_storage_module_name` | Suffix for named resources (unique per cluster) | — (required) |
| `cluster_name` | EKS cluster to install the addon into | — (required) |
| `oidc_provider_arn` | Cluster IAM OIDC provider ARN (for the EBS CSI IRSA trust) | — (required) |
| `storage_class_name` | WAL StorageClass name (must match the chart) | `gp3-wal` |
| `volume_type` | EBS volume type | `gp3` |
| `encrypted` | Encrypt WAL volumes | `true` |
| `kms_key_id` | KMS key for encryption (null = account default) | `null` |
| `make_default_storage_class` | Mark the StorageClass cluster-default | `false` |
| `ebs_csi_addon_version` | Pin the addon version (null = EKS default) | `null` |
| `ebs_csi_service_account_namespace` | EBS CSI SA namespace (IRSA trust) | `kube-system` |
| `ebs_csi_service_account_name` | EBS CSI SA name (IRSA trust) | `ebs-csi-controller-sa` |
| `tags` | Extra tags for the IAM role and addon | `{}` |

## Outputs

| Name | Description |
|---|---|
| `ebs_csi_role_arn` | ARN of the EBS CSI IRSA role |
| `ebs_csi_addon_arn` | ARN of the aws-ebs-csi-driver addon |
| `storage_class_name` | Name of the WAL StorageClass |
