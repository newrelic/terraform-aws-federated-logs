module "federated_logs" {
  source = "../../"

  setup_name          = "my-app-logs-pptt"
  fleet_entity_guid   = var.fleet_entity_guid
  newrelic_org_id     = var.newrelic_org_id
  newrelic_account_id = 0    # Replace with your NR account ID.
  newrelic_region     = "US" # "US" (default), "EU", or "STAGING"

  # AWS region where resources will be created. If not set, uses the provider's configured region.
  #region = "us-east-2"

  # Enable data retention feature (creates Glue job to delete old data)
  data_retention_enabled = true

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

  partition_tables = {
    "application_log" = {
      retention_in_days = 5
    },
    "security_log" = {
      retention_in_days = 10
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
    "audit_log" = {
      table_parameters = {
        "write.target-file-size-bytes"               = "52428800" # 50 MB
        "write.metadata.delete-after-commit.enabled" = "false"
        "write.metadata.previous-versions-max"       = "5"
      }
    },
    "network_log" = {
      table_parameters = {
        "write.parquet.page-row-limit"    = "20000"
        "write.parquet.compression-codec" = "snappy"
        "write.distribution-mode"         = "hash"
      }
    }
  }

  # Optional: run an end-to-end validation after apply.
  #
  # The validation deploys an AWS Lambda inside your VPC that:
  #   1. POSTs a synthetic log to your PCG endpoint
  #   2. Polls NRDB for the log via NRQL
  #   3. Reports HEALTHY/UNHEALTHY back to NR via the
  #      federatedLogsUpdateSetup mutation
  e2e_validation_config = {
    enabled      = true
    pcg_endpoint = "https://pcg.example.com"
    test_payload = jsonencode({ message = "federated-logs e2e test", level = "info" })

    # Replace these with the actual IDs from your VPC. Subnets must have a
    # private route to PCG and outbound internet access (typically via NAT)
    # to reach api.newrelic.com.
    vpc_config = {
      subnet_ids         = ["subnet-0a1b2c3d4e5f60718", "subnet-0a1b2c3d4e5f60719"]
      security_group_ids = ["sg-0a1b2c3d4e5f60710"]
    }

    # Optional Lambda tuning — defaults shown:
    # lambda_timeout     = 180  # seconds; covers cold start + script worst-case
    # lambda_memory_size = 256  # MB

    # Optional script tuning — defaults shown:
    # max_retries       = 3   # transient HTTP retries (5xx / connection)
    # retry_delay       = 5
    # initial_read_wait = 30
    # read_max_retries  = 5   # NRQL read polls while the log ingests
    # read_retry_delay  = 15
  }
}
