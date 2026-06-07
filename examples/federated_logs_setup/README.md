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

Export your New Relic API key as an environment variable before running Terraform:

```sh
export NEW_RELIC_API_KEY="your-new-relic-api-key"
```

## Usage

```sh
cd examples/federated_logs_setup
terraform init
terraform plan
terraform apply
```
