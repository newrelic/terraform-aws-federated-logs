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
      "write.target-file-size-bytes"               = "26214400" # 25 MB
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
}
