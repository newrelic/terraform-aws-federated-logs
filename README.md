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

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.6.0 |
| aws | >= 5.0 |

## Inputs

| Name | Description | Type | Required |
|------|-------------|------|----------|
| `setup_name` | A name for this federated logs setup (3–26 lowercase alphanumeric chars, hyphens allowed) | `string` | yes |
| `clusters` | Map of EKS cluster configurations for PCG writer role OIDC authentication | `map(object)` | yes |
| `default_table_setting` | Settings for the primary federated log table (table parameters + optimizer config) | `object` | no |
| `partition_tables` | Map of additional partition tables, each can override table parameters and optimizer config | `map(object)` | no |
| `validation_config` | Post-apply validation settings: `enabled` (default `false`), `enable_permission_checks` (default `true`), `enable_oidc_validation` (default `false`) | `object` | no |

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
| `clusters` | Map of cluster configurations with resolved role ARNs |
| `validation_summary` | Validation results (only when `validation_config.enabled = true`) |

## Examples

- [Complete](./examples/complete) — Full deployment with custom table settings and multiple partition tables

## E2E Validation

After deploying the module, run the E2E script to verify the full ingest pipeline — send a test log to the PCG endpoint and confirm it appears in New Relic via NRQL.

```sh
python3 scripts/e2e_test.py \
  --pcg-endpoint "https://pcg.example.com/v1/logs" \
  --license-key "INGEST-KEY-..." \
  --partition "application_log" \
  --nr-account-id "1234567" \
  --nr-api-key "NRAK-..."
```

| Flag | Env var | Description |
|---|---|---|
| `--pcg-endpoint` | `PCG_ENDPOINT` | PCG ingest URL |
| `--license-key` | `NR_LICENSE_KEY` | New Relic ingest/license key |
| `--partition` | `PARTITION_NAME` | Partition (table) name to query |
| `--nr-account-id` | `NR_ACCOUNT_ID` | New Relic account ID |
| `--nr-api-key` | `NR_API_KEY` | New Relic User API key |
| `--region` | `NR_REGION` | `us` (default) or `eu` |
| `--staging` | `NR_STAGING` | Use the staging GraphQL endpoint |
| `--graphql-url` | `NR_GRAPHQL_URL` | Override GraphQL URL directly |
| `--payload` | `TEST_PAYLOAD` | Custom JSON payload (optional) |

The script generates a UUID, injects it into the payload, sends it to PCG, waits for ingestion, then queries New Relic for that UUID. Exit code 0 on success, 1 on failure.

### Testing the E2E script itself

The `tests/e2e/` directory contains a MockServer-based test suite that verifies the correctness of the E2E script — its retry logic, error handling, and exit codes. This does **not** test the actual federated logs pipeline; it tests that the script behaves correctly against mock HTTP responses.

**Prerequisites:** Docker

```sh
./tests/e2e/run_tests.sh
```

This spins up a [MockServer](https://www.mock-server.com/) container, loads expectation configs for each scenario, runs the E2E script against `localhost:1080`, and checks exit codes. The test suite covers:

| Test | Expectations | Expected exit |
|------|-------------|---------------|
| Happy path | Write 202, read returns results | 0 |
| Write retry then success | Write 500 once → 202, read returns results | 0 |
| Read retry then success | Write 202, read empty once → returns results | 0 |
| Write permanent failure | Write always 503 | 1 |
| Read permanent empty | Write 202, read always empty | 1 |

Expectation files live in `tests/e2e/expectations/` and can be extended to cover additional scenarios.
