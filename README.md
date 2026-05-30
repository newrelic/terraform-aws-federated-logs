# terraform-aws-federated-logs

Terraform module to provision AWS resources for New Relic Federated Logs. Creates an S3 bucket, Glue catalog database, Iceberg tables with optimizers, and IAM roles for Glue service, New Relic query access, and PCG writer access.

## Usage

```hcl
module "federated_logs" {
  source = "git::https://github.com/newrelic/terraform-aws-federated-logs.git?ref=v1.0.0"

  setup_name = "my-app-logs"

  # Optional: set true to enable retention 
  data_retention_enabled = true  

  # AWS region where resources will be created. If not set, uses the provider's configured region.
  #region = "us-east-2"

  clusters = {
    "prod-cluster" = {
      k8s_namespace            = "federated-logs"
      k8s_service_account_name = "pcg-writer-sa"
      oidc_provider_arn        = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE"
    }
  }

  # Optional: override default Iceberg table parameters and optimizer settings
  default_table_setting = {
    table_parameters = {
      "write.target-file-size-bytes"               = "26214400" # 25 MB
      "write.metadata.delete-after-commit.enabled" = "true"
      "write.metadata.previous-versions-max"       = "10"
    }
  }

  # Optional: define additional partition tables
  # Each entry can override table_parameters and/or optimizer_configuration,
  # or use {} for all defaults
  partition_tables = {
    "application_log" = {},
    "security_log" = {
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

Export your New Relic API key as an environment variable before running Terraform:

```sh
export NEWRELIC_API_KEY="your-new-relic-api-key"
```

This is used to make New Relic API calls (fetching the base role ARN). It is read directly from the environment and is never stored in Terraform state.

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.4.0 |
| aws | >= 5.0 |

## Inputs

| Name | Description | Type | Required |
|------|-------------|------|----------|
| `setup_name` | A name for this federated logs setup (3–26 lowercase alphanumeric chars, hyphens allowed) | `string` | yes |
| `clusters` | Map of EKS cluster configurations for PCG writer role OIDC authentication | `map(object)` | yes |
| `default_table_setting` | Settings for the primary federated log table (table parameters + optimizer config) | `object` | no |
| `partition_tables` | Map of additional partition tables, each can override table parameters and optimizer config | `map(object)` | no |

## Outputs

| Name | Description |
|------|-------------|
| `s3_bucket_name` | Name of the S3 bucket storing federated logs |
| `s3_bucket_arn` | ARN of the S3 bucket |
| `glue_database_name` | Name of the Glue catalog database |
| `glue_service_role_arn` | ARN of the IAM role used by Glue for table maintenance |
| `pcg_writer_role_arn` | ARN of the IAM role for PCG to write federated logs |
| `nr_reader_role_arn` | ARN of the IAM role for New Relic to query federated logs |
| `iceberg_tables` | Map of created Iceberg table names and ARNs |

## Examples

- [Complete](./examples/complete) — Full deployment with custom table settings and multiple partition tables
