module "federated_logs" {
  source = "../../"

  setup_name = "my-app-logs"

  # AWS region where resources will be created. If not set, uses the provider's configured region.
  #region = "us-east-2"

  clusters = {
    "cluster-1" = {
      k8s_namespace            = "federated-logs"
      auth_mode                = "irsa" # "irsa" or "pod_identity"
      k8s_service_account_name = "pcg-writer-sa"
      oidc_provider_arn        = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-2.amazonaws.com/id/EXAMPLE"
    }
  }

  default_table_setting = {
    table_parameters = {
      "write.target-file-size-bytes"               = "26214400" # 25 MB
      "write.metadata.delete-after-commit.enabled" = "true"
      "write.metadata.previous-versions-max"       = "10"
    }
    optimizer_configuration = {
      orphan_file_deletion = {
        orphan_file_retention_period_in_days = 1
        run_rate_in_hours                    = 3
      }
      snapshot_retention = {
        snapshot_retention_period_in_days = 1
        number_of_snapshots_to_retain     = 1
        clean_expired_files               = true
        run_rate_in_hours                 = 3
      }
      compaction = {
        strategy              = "binpack"
        min_input_files       = 5
        delete_file_threshold = 1
      }
    }
  }

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
