# Data Processing Module Example

This example demonstrates the fleet-level data processing setup, which is deployed **once per PCG fleet**.

It creates:

- A fleet-level IAM base role authenticated via IRSA or Pod Identity
- An ABAC inline policy allowing the base role to assume any per-setup `pcg-writer` role tagged with the matching `fleet_entity_guid` value
- An AWS Connection Entity in New Relic NGEP storing the base role ARN as a credential
- A `HAS_FED_LOGS_BASE_ROLE` relationship from the fleet entity to the AWS Connection Entity

The `fleet_entity_guid` is passed directly to each [federated_logs_setup](../federated_logs_setup) deployment.

## Prerequisites

Export your New Relic credentials as environment variables before running Terraform:

```sh
export NEW_RELIC_API_KEY="your-new-relic-api-key"
export NEW_RELIC_LICENSE_KEY="your-new-relic-license-key"
```

- `NEW_RELIC_API_KEY`: Used for NerdGraph API calls (fetching base role ARN, creating entities)
- `NEW_RELIC_LICENSE_KEY`: Your New Relic license key (used by Flink to send metrics to New Relic)

## Inputs

| Name | Description | Type | Required |
|------|-------------|------|----------|
| `data_processing_module_name` | Name for this data processing setup (3–26 lowercase alphanumeric, hyphens allowed) | `string` | yes |
| `newrelic_org_id` | New Relic organization ID | `string` | yes |
| `fleet_entity_guid` | NGEP entity GUID of the PCG fleet | `string` | yes |
| `clusters` | Map of EKS cluster configs for base role trust policy (auth via IRSA or Pod Identity) | `map(object)` | yes |
| `parallelism` | Flink parallelism setting | `number` | no (default: `1`) |
| `parallelism_per_kpu` | Flink parallelism per KPU | `number` | no (default: `1`) |
| `auto_scaling_enabled` | Enable Flink auto scaling | `bool` | no (default: `true`) |
| `allowed_source_account_ids` | Cross-account only: AWS account ID(s) where the `federated_logs` setup lives, allowed to send EventBridge events to the SQS queue | `list(string)` | no (default: `[]`) |
| `e2e_validation_config` | Optional end-to-end validation Lambda, run from this account (see below) | `object` | no (default: disabled) |

## Outputs

| Name | Description |
|------|-------------|
| `base_role_arn` | ARN of the fleet-level PCG base role |
| `base_role_name` | Name of the fleet-level PCG base role |
| `e2e_validation_status` | PASS/FAIL of the most recent e2e validation run (null when disabled) |
| `e2e_validation_result` | Full JSON result of the most recent e2e validation run (null when disabled) |

## Cross-account & end-to-end validation

For a **cross-account** deployment (fleet/PCG in this AWS account, storage bucket + Glue in another):

- Set `allowed_source_account_ids = ["<storage-account-id>"]` so the SQS queue policy trusts
  the storage account's `eb-to-sqs` role. Without it, EventBridge cross-account delivery is
  silently denied and no Iceberg metadata is ever committed.
- Run the **end-to-end validation from this module** (not from `federated_logs`). The validation
  Lambda must sit in a VPC that can reach PCG — which lives in this account, not the storage
  account. Because `data_processing` cannot derive them, `e2e_validation_config` additionally
  requires `setup_id` (copy it from the `federated_logs` deploy's `newrelic_federated_logs_setup_id`
  output) and `nr_account_id`. `nr_region` reuses this module's `newrelic_region`.

For a **same-account** deployment you may run the validation from either module; leave
`allowed_source_account_ids` unset. See the commented `e2e_validation_config` block in `main.tf`.
Both require `NEW_RELIC_LICENSE_KEY` and `NEW_RELIC_API_KEY` in the runner env at apply time.

## Usage

1. Update `main.tf` with your values:
   - `data_processing_module_name` — a unique name for this fleet
   - `newrelic_org_id` — your New Relic org ID
   - `fleet_entity_guid` — the GUID of your PCG fleet entity
   - `clusters` — your EKS cluster(s) with OIDC provider ARN or cluster name

2. Update `providers.tf` with your AWS region and New Relic account ID.

3. Run:

```sh
cd examples/data_processing
terraform init
terraform plan
terraform apply
```
