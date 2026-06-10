# Federated Logs Setup Example

This example demonstrates a per-setup federated logs deployment. It is deployed **once per log setup** and requires the [data_processing](../data_processing) module to be deployed first.

A **fleet** is a New Relic PCG (Pipeline Control Gateway) deployment — a group of collectors running in your Kubernetes cluster that ship logs to New Relic. Each fleet has a unique `fleet_entity_guid` assigned during PCG setup, which is used here to scope IAM trust and tag AWS resources.

It creates:

- An S3 bucket for storing federated logs
- A Glue catalog database
- A `pcg-writer` IAM role that trusts the fleet base role via ABAC tag matching
- A New Relic reader IAM role for cross-account query access
- Iceberg tables with configurable optimizer and retention settings

## Prerequisites

1. Deploy the [data_processing](../data_processing) module first to create the fleet-level base role.
2. Export your New Relic API key:

```sh
export NEW_RELIC_API_KEY="your-new-relic-api-key"
```

## Inputs

| Name | Description | Type | Required |
|------|-------------|------|----------|
| `fleet_entity_guid` | NGEP entity GUID of the PCG fleet (from your PCG installation) | `string` | yes |
| `newrelic_org_id` | New Relic organization ID | `string` | yes |
| `newrelic_account_id` | New Relic account ID | `number` | yes |
| `setup_name` | Name for this log setup (3–26 lowercase alphanumeric, hyphens allowed) | `string` | yes |
| `newrelic_region` | New Relic region: 'US', 'EU', or 'STAGING' | `string` | no (default: `"US"`) |
| `data_retention_enabled` | Enable Glue job to delete old data based on per-table retention_in_days | `bool` | no (default: `true`) |
| `default_table_setting` | Settings for the primary table (retention, table parameters, optimizer config) | `object` | no |
| `partition_tables` | Map of additional partition tables with per-table overrides | `map(object)` | no |

## Outputs

| Name | Description |
|------|-------------|
| `s3_bucket_name` | Name of the S3 bucket storing federated logs |
| `glue_database_name` | Name of the Glue catalog database |
| `glue_service_role_arn` | ARN of the IAM role used by Glue for table maintenance |
| `pcg_writer_role_arn` | ARN of the IAM role for PCG to write federated logs |
| `nr_reader_role_arn` | ARN of the IAM role for New Relic to query federated logs |
| `iceberg_tables` | Map of created Iceberg table names and ARNs |

## Usage

1. Update `main.tf` with your values:
   - `fleet_entity_guid` — the GUID of your PCG fleet entity
   - `newrelic_org_id` — your New Relic org ID
   - `newrelic_account_id` — your New Relic account ID
   - Optionally configure `default_table_setting` and `partition_tables`

2. Run:

```sh
cd examples/federated_logs_setup
terraform init
terraform plan
terraform apply
```
