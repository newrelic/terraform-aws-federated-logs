# terraform-aws-federated-logs

Terraform module to provision AWS resources for New Relic Federated Logs. Creates an S3 bucket, Glue catalog database, Iceberg tables with optimizers, and IAM roles for Glue service, New Relic query access, and PCG writer access.

## Architecture

This module is deployed in two stages:

1. **Data Processing** (once per PCG fleet) — Creates a fleet-level IAM base role authenticated via IRSA or Pod Identity, an ABAC policy for assuming per-setup writer roles, and an AWS Connection Entity in New Relic. See the [data_processing module](./modules/data_processing).

2. **Federated Logs Setup** (once per log setup) — Creates an S3 bucket, Glue catalog database, a `pcg-writer` IAM role that trusts the fleet base role via ABAC tag matching, a New Relic reader role for cross-account query access, and Iceberg tables with configurable optimizer and retention settings.

The `fleet_entity_guid` from your PCG installation links the two stages together.

## Usage

```hcl
# Stage 1: Deploy once per PCG fleet
module "data_processing" {
  source = "git::https://github.com/newrelic/terraform-aws-federated-logs.git//modules/data_processing?ref=v1.0.0"

  data_processing_module_name = "my-app-logs"
  newrelic_org_id             = "YOUR_NR_ORG_ID"
  fleet_entity_guid           = "YOUR_FLEET_ENTITY_GUID"

  clusters = {
    "prod-cluster" = {
      k8s_namespace            = "federated-logs"
      auth_mode                = "irsa" # "irsa" or "pod_identity"
      k8s_service_account_name = "pcg-writer-sa"
      oidc_provider_arn        = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE"
    }
  }
}

# Stage 2: Deploy once per log setup
module "federated_logs" {
  source = "git::https://github.com/newrelic/terraform-aws-federated-logs.git?ref=v1.0.0"

  setup_name          = "my-app-logs"
  fleet_entity_guid   = "YOUR_FLEET_ENTITY_GUID"
  newrelic_org_id     = "YOUR_NR_ORG_ID"
  newrelic_account_id = 123456789
  newrelic_region     = "US" # "US" (default), "EU", or "STAGING"

  # AWS region where resources will be created. If not set, uses the provider's configured region.
  #region = "us-east-2"

  # Enable data retention feature (creates Glue job to delete old data)
  data_retention_enabled = true

  # Override default Iceberg table parameters and optimizer settings
  default_table_setting = {
    retention_in_days = 30
    table_parameters = {
      "write.parquet.compression-codec"            = "zstd"
      "write.target-file-size-bytes"               = "67108864" # 64 MB
      "write.metadata.delete-after-commit.enabled" = "true"
      "write.metadata.previous-versions-max"       = "10"
    }
    optimizer_configuration = {
      orphan_file_deletion = {
        orphan_file_retention_period_in_days = 3
        run_rate_in_hours                    = 24
      }
      snapshot_retention = {
        snapshot_retention_period_in_days = 5
        number_of_snapshots_to_retain     = 2
        clean_expired_files               = false
        run_rate_in_hours                 = 24
      }
      compaction = {
        strategy              = "binpack"
        min_input_files       = 5
        delete_file_threshold = 1
      }
    }
  }

  # Define additional partition tables
  # Each entry can override table_parameters, optimizer_configuration,
  # routing_expression, and/or description — or use {} for all defaults
  partition_tables = {
    "application_log" = {
      retention_in_days = 5
    },
    "security_log" = {
      retention_in_days = 10
      optimizer_configuration = {
        compaction = {
          strategy              = "binpack"
          min_input_files       = 10
          delete_file_threshold = 2
        }
      }
    },
    "network_log" = {
      table_parameters = {
        "write.parquet.compression-codec" = "snappy"
        "write.distribution-mode"         = "hash"
      }
    }
  }
}
```

## Prerequisites

Export your New Relic credentials as environment variables before running Terraform:

```sh
export NEW_RELIC_API_KEY="your-new-relic-api-key"
export NEW_RELIC_LICENSE_KEY="your-new-relic-license-key"  # required for data_processing module only
```

- `NEW_RELIC_API_KEY`: Used for NerdGraph API calls (fetching base role ARN, creating entities). Required by both stages.
- `NEW_RELIC_LICENSE_KEY`: Your New Relic license key (used by Flink to send metrics). Required by the data_processing module only.

These are read directly from the environment and are never stored in Terraform state.

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.6.0 |
| aws | >= 6.36.0 |
| newrelic | >= 3.91.0 |

## Inputs

| Name | Description | Type | Required |
|------|-------------|------|----------|
| `setup_name` | A name for this federated logs setup (3–26 lowercase alphanumeric chars, hyphens allowed) | `string` | yes |
| `fleet_entity_guid` | NGEP entity GUID of the PCG fleet (output of the data_processing module) | `string` | yes |
| `newrelic_org_id` | New Relic organization ID | `string` | yes |
| `newrelic_account_id` | New Relic account ID | `number` | yes |
| `newrelic_region` | New Relic region: 'US', 'EU', or 'STAGING' | `string` | no (default: `"US"`) |
| `region` | AWS region where resources will be created. If not set, uses the provider's configured region | `string` | no |
| `data_retention_enabled` | Enable data retention feature (creates Glue job to delete old data based on per-table retention_in_days) | `bool` | no (default: `true`) |
| `default_table_setting` | Settings for the primary federated log table (retention, table parameters, optimizer config) | `object` | no |
| `partition_tables` | Map of additional partition tables, each can override retention, table parameters, optimizer config, routing expression, and description | `map(object)` | no |
| `setup_description` | Optional description for the newrelic_federated_logs_setup resource | `string` | no |
| `query_connection_description` | Optional description for the per-setup newrelic_aws_connection wrapping the reader role | `string` | no |

## Outputs

| Name | Description |
|------|-------------|
| `s3_bucket_name` | Name of the S3 bucket storing federated logs |
| `s3_bucket_arn` | ARN of the S3 bucket |
| `glue_database_name` | Name of the Glue catalog database |
| `glue_service_role_arn` | ARN of the IAM role used by Glue for table maintenance |
| `pcg_writer_role_arn` | ARN of the IAM role for PCG to write federated logs |
| `nr_reader_role_arn` | ARN of the IAM role for New Relic to query federated logs |
| `iceberg_tables` | Map of created Iceberg table names and their configurations |
| `newrelic_federated_logs_setup_id` | ID of the newrelic_federated_logs_setup created for this AWS module |
| `newrelic_default_partition_id` | ID of the default partition created alongside the federated logs setup |
| `newrelic_query_connection_id` | ID of the per-setup newrelic_aws_connection wrapping the reader role |

## Examples

- [Data Processing](./examples/data_processing) — Fleet-level setup (once per PCG fleet): base IAM role, ABAC policy, and AWS Connection Entity
- [Federated Logs Setup](./examples/federated_logs_setup) — Per-setup deployment: S3 bucket, Glue database, Iceberg tables, PCG writer role, and reader role
