# terraform-federated-logs

## Setup

### 1. Configure the AWS provider

The child modules do not contain AWS provider configuration — they inherit it from the calling module. You must configure the AWS provider in your `providers.tf`:

```hcl
terraform {
  required_version = ">= 1.4.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1" # Region which is used to deploy all AWS resources
}
```

### 2. Initialize Terraform

```sh
terraform init
```

If the modules or providers have been upgraded, use:

```sh
terraform init -upgrade
```

### Usage Example

```hcl
module "federated_logs_setup_resource" {
  source     = "./modules/federated_logs_setup_resource"
  setup_name = "logint-fed-logs-test-setup"
}

module "federated_logs_role" {
  source               = "./modules/federated_logs_role"
  setup_name           = module.federated_logs_setup_resource.setup_name
  s3_bucket_name       = module.federated_logs_setup_resource.s3_bucket_name
  glue_catalog_db_name = module.federated_logs_setup_resource.glue_catalog_db_name
  clusters             = {
    "cluster-1" = {
            k8s_namespace            = "federated-logs"
            k8s_service_account_name = "pcg-writer-sa"
            oidc_provider_arn        = "arn:aws:iam::xxxxx:oidc-provider/oidc.eks.us-east-2.amazonaws.com/id/xxxxxxxx"
        }
    }
}

module "federated_logs_partition" {
  source                = "./modules/federated_logs_partition"
  setup_name            = module.federated_logs_setup_resource.setup_name
  s3_bucket_name        = module.federated_logs_setup_resource.s3_bucket_name
  glue_catalog_db_name  = module.federated_logs_setup_resource.glue_catalog_db_name
  glue_service_role_arn = module.federated_logs_role.glue_service_role_arn

  # Optional: override default Iceberg table parameters
  default_table_setting = {
    table_parameters = {
      "write.target-file-size-bytes"               = "26214400" # 25 MB
      "write.metadata.delete-after-commit.enabled" = "true"
      "write.metadata.previous-versions-max"       = "10"
    }
  }

  # Define additional partition tables — each can override table_parameters
  # and/or optimizer_configuration, or use {} for all defaults
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

### 3. Plan and apply

```sh
terraform plan
terraform apply
```
