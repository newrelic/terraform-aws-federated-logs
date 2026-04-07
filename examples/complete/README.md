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
