# Data Processing Module Example

This example demonstrates the fleet-level data processing setup, which is deployed **once per PCG fleet**.

It creates:

- A fleet-level IAM base role authenticated via IRSA or Pod Identity
- An ABAC inline policy allowing the base role to assume any per-setup `pcg-writer` role tagged with the matching `fleet_entity_guid` value
- An AWS Connection Entity in New Relic NGEP storing the base role ARN as a credential
- A `HAS_FED_LOGS_BASE_ROLE` relationship from the fleet entity to the AWS Connection Entity

The `base_role_arn` output is available for reference. The `fleet_entity_guid` is passed directly to each `federated_logs_setup` deployment.

## Prerequisites

Export your New Relic credentials as environment variables before running Terraform:

```sh
export NEW_RELIC_API_KEY="your-new-relic-api-key"
export NEW_RELIC_LICENSE_KEY="your-new-relic-license-key"
```

- `NEW_RELIC_API_KEY`: Used for NerdGraph API calls (fetching base role ARN, creating entities)
- `NEW_RELIC_LICENSE_KEY`: Your New Relic license key (used by Flink to send metrics to New Relic)

## Usage

```sh
cd examples/data_processing
terraform init
terraform plan
terraform apply
```
