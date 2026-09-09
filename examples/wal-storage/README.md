# Example: wal-storage

Installs the PCG Federated Logs **WAL** cluster prerequisites into an EKS cluster:
the `aws-ebs-csi-driver` addon (via IRSA) and the `gp3-wal` StorageClass. Run this once
per cluster, then enable `wal` from Fleet Control and deploy.

See [`../../modules/wal_storage`](../../modules/wal_storage) for details.

## Usage

```bash
terraform init
terraform apply -var 'cluster_name=my-eks-cluster'
```

Before applying, edit `main.tf` to set `oidc_provider_arn` (your cluster's IAM OIDC
provider ARN) and adjust the region in `providers.tf`. The `kubernetes` provider is
wired automatically from the EKS cluster data sources in `providers.tf`.
