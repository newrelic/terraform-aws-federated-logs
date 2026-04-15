# terraform-aws-federated-logs

Terraform module to provision AWS resources for New Relic Federated Logs. Creates an S3 bucket, Glue catalog database, Iceberg tables with optimizers, and IAM roles for Glue service, New Relic query access, and PCG writer access.

## Usage

```hcl
module "federated_logs" {
  source = "git::https://github.com/newrelic/terraform-aws-federated-logs.git?ref=v1.0.0"

  setup_name = "my-app-logs"

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

## Data Retention (Optional)

Automatically delete old log data from **all tables** to manage storage costs and compliance:

```hcl
module "federated_logs" {
  source = "git::https://github.com/newrelic/terraform-aws-federated-logs.git?ref=v1.0.0"

  setup_name = "my-app-logs"
  
  # New Relic API key (mandatory - stored in AWS Secrets Manager)
  newrelic_api_key = var.newrelic_api_key
  
  # Optional: Data retention period applied to ALL tables
  retention_period = "7 DAYS"  # Set to enable retention, null to disable
  
  clusters = {
    # ... cluster configuration ...
  }
  
  default_table_setting = {
    # ... other settings ...
  }
  
  partition_tables = {
    # All tables inherit the same retention_period
    "application_log" = {}
    "security_log"    = {}
  }
}
```

**Retention Period Format:** `<number> DAYS` or `<number> DAY` (e.g., "7 DAYS", "90 DAYS", "1 DAY")

**How It Works:**
- Set `retention_period` at the module level to enable automatic deletion for **all tables**
- EventBridge triggers a Glue Spark job daily at midnight UTC (00:00)
- Job deletes data older than the retention period from all tables using Iceberg DELETE
- Deletion aligned to midnight for efficient whole-partition drops (metadata-only, no CoW rewrites)
- Existing Glue optimizers clean up physical S3 files
- Job continues processing even if individual tables fail
- New Relic API key stored securely in AWS Secrets Manager

**Cost:** ~$2.65/month per setup (Secrets Manager + Glue Spark ETL execution)

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
