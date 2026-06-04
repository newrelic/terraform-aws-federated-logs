# Data Processing Module Example

This example demonstrates the fleet-level data processing setup, which is deployed **once per PCG fleet**.

It creates:

- A fleet-level IAM base role authenticated via IRSA or Pod Identity
- An ABAC inline policy allowing the base role to assume any per-setup `pcg-writer` role tagged with the matching `fleet_entity_guid` value
- An AWS Connection Entity in New Relic NGEP storing the base role ARN as a credential
- A `HAS_FED_LOGS_BASE_ROLE` relationship from the fleet entity to the AWS Connection Entity

The `base_role_arn` output is available for reference. The `fleet_entity_guid` is passed directly to each `federated_logs_setup` deployment.

## Prerequisites

Pass your New Relic credentials as Terraform input variables. Both are marked `sensitive` (redacted from CLI output; still written to state — protect your state backend accordingly).

- `newrelic_api_key` — User API key (`NRAK-...`). Used by the newrelic provider for NerdGraph calls (fetching base role ARN, creating entities).
- `newrelic_license_key` — Ingest license key (`NRAL-...`). Injected into the Flink application as `newrelic.license.key` so it can send metrics to New Relic.

## Usage

```sh
cd examples/data_processing
terraform init
terraform plan \
  -var='newrelic_api_key=NRAK-XXXXXXXXXXXXXXXXXXXX' \
  -var='newrelic_license_key=NRAL-XXXXXXXXXXXXXXXXXXXX'
terraform apply \
  -var='newrelic_api_key=NRAK-XXXXXXXXXXXXXXXXXXXX' \
  -var='newrelic_license_key=NRAL-XXXXXXXXXXXXXXXXXXXX'
```

You can also set them via a `*.tfvars` file or `TF_VAR_newrelic_api_key` / `TF_VAR_newrelic_license_key` env vars.
