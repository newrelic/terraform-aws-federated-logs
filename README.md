# terraform-aws-federated-logs

Terraform module to provision AWS resources for New Relic Federated Logs. Creates an S3 bucket, Glue catalog database, Iceberg tables with optimizers, and IAM roles for Glue service, New Relic query access, and PCG writer access.

## Usage

```hcl
provider "aws" {
  region = "us-east-1"
}

module "federated_logs" {
  source = "git::https://github.com/newrelic/terraform-aws-federated-logs.git?ref=v1.0.0"

  setup_name = "my-app-logs"

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

## Provider Configuration

This module does **not** include a `provider` block. You must configure the AWS provider in your root module:

```hcl
provider "aws" {
  region = "us-east-1"
}
```

All resources will be created in the region configured in your provider.

### 4. Validate the pipeline (optional)

Add the validation module to verify that AWS resources are accessible and (optionally) that logs flow end-to-end through New Relic.

```hcl
module "federated_logs_validation" {
  source               = "./modules/federated_logs_validation"
  s3_bucket_name       = module.federated_logs_setup_resource.s3_bucket_name
  glue_catalog_db_name = module.federated_logs_setup_resource.glue_catalog_db_name
  newrelic_account_id  = 12345
  newrelic_user_api_key = var.newrelic_user_api_key

  # Layer 1 (AWS resource checks) runs automatically on every plan/apply.
  # Layer 2 (end-to-end ingest + query) runs only when you opt in:
  run_validation    = var.run_validation      # default false
  validation_run_id = var.validation_run_id   # change to force re-run
}
```

**Layer 1 — AWS checks** run automatically on every `terraform plan/apply`. No extra connectivity needed.

**Layer 2 — End-to-end validation** (ingest a test log to S3 → poll New Relic) runs only when triggered:

```sh
terraform apply \
  -var="run_validation=true" \
  -var="validation_run_id=$(date +%s)" \
  -var="newrelic_user_api_key=$NR_USER_API_KEY"
```

> **Prerequisites for Layer 2:** The environment where Terraform runs must have
> network access to both AWS S3 and the New Relic NerdGraph API, plus `aws`,
> `curl`, and `jq` in `$PATH`.

The script can also be run standalone without Terraform:

```sh
S3_BUCKET="newrelic-fed-logs-mysetup" \
GLUE_DB_NAME="newrelic_fed_logs_mysetup" \
NR_ACCOUNT_ID="12345" \
NR_USER_API_KEY="NRAK-xxx" \
  ./modules/federated_logs_validation/scripts/validate_e2e.sh
```
