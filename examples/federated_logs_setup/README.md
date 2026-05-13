# Federated Logs Setup Example

This example demonstrates a per-setup federated logs deployment. It is deployed **once per log setup** and requires the data processing module to be deployed first.

It creates:

- An S3 bucket for storing federated logs
- A Glue catalog database
- A `pcg-writer` IAM role that trusts the fleet base role via ABAC tag matching
- A New Relic reader IAM role for cross-account query access
- Iceberg tables with configurable optimizer and retention settings

The `fleet_entity_guid` input comes from the outputs of the `data_processing` module.

## Usage

```sh
cd examples/federated_logs_setup
terraform init
terraform plan
terraform apply
```
