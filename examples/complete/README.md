# Complete Example

This example demonstrates a full deployment of the federated logs module with:

- Custom default table settings (table parameters + optimizer configuration)
- Multiple partition tables with per-table overrides
- A single EKS cluster configured for PCG writer access

## Usage

```sh
cd examples/complete
terraform init
terraform plan
terraform apply
```

## Post-Deploy Validation

Enable validation on demand via a variable:

```sh
terraform plan -var="enable_validation=true"
```

The example already includes the wiring — `validation_config.enabled` is bound to the `enable_validation` variable (defaults to `false`).

This runs check blocks on every `terraform plan`, surfacing misconfigurations as warnings:

- **Resource existence**: S3 bucket, IAM roles, CloudWatch log groups
- **Trust policy structure**: Glue service trust, OIDC federation on PCG writer, ExternalId on NR reader
- **Permission simulation**: Positive and negative IAM permission checks for all three roles

No resources are created. Disable at any time by setting `enabled = false` or removing the block.

### Prerequisites

| Feature | Permission required |
|---------|-------------------|
| Permission checks (default on) | `iam:SimulatePrincipalPolicy` |

```hcl
validation_config = {
  enabled                  = true
  enable_permission_checks = false  # Skip if lacking iam:SimulatePrincipalPolicy
}
```
