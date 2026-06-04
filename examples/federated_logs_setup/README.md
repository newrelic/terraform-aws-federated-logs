# Federated Logs Setup Example

This example demonstrates a per-setup federated logs deployment. It is deployed **once per log setup** and requires the data processing module to be deployed first.

A **fleet** is a New Relic PCG (Pipeline Control Gateway) deployment — a group of collectors running in your Kubernetes cluster that ship logs to New Relic. Each fleet has a unique `fleet_entity_guid` assigned during PCG setup, which is used here to scope IAM trust and tag AWS resources.

It creates:

- An S3 bucket for storing federated logs
- A Glue catalog database
- A `pcg-writer` IAM role that trusts the fleet base role via ABAC tag matching
- A New Relic reader IAM role for cross-account query access
- Iceberg tables with configurable optimizer and retention settings

The `fleet_entity_guid` is the GUID of your PCG fleet entity in New Relic, available from your PCG installation.

## Prerequisites

Pass your New Relic User API key (`NRAK-...`) as the `newrelic_api_key` input variable. The variable is marked `sensitive` (redacted from CLI output; still written to state — protect your state backend accordingly).

## Usage

```sh
cd examples/federated_logs_setup
terraform init
terraform plan  -var='newrelic_api_key=NRAK-XXXXXXXXXXXXXXXXXXXX'
terraform apply -var='newrelic_api_key=NRAK-XXXXXXXXXXXXXXXXXXXX'
```

You can also set it via a `*.tfvars` file or `TF_VAR_newrelic_api_key` env var.
