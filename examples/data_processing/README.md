# Data Processing Module Example

This example demonstrates the fleet-level data processing setup, which is deployed **once per PCG fleet**.

It creates:

- A fleet-level IAM base role authenticated via IRSA or Pod Identity
- An ABAC inline policy allowing the base role to assume any per-setup `pcg-writer` role tagged with the matching `PCG_Instance` value
- An AWS Connection Entity in New Relic NGEP storing the base role ARN as a credential
- An `APPLY_TO` relationship from the fleet entity to the AWS Connection Entity

The outputs (`base_role_arn`, `pcg_instance_name`) are consumed by each `federated_logs_setup` deployment.

## Usage

```sh
cd examples/data_processing
terraform init
terraform plan
terraform apply
```
