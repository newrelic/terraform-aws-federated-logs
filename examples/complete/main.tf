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

  # Post-deploy validation (optional)
  # Validates resource existence, IAM trust policies, and permission boundaries.
  # Creates no resources — only check blocks.
  # Enable on demand:  terraform plan -var="enable_validation=true"
  validation_config = {
    enabled                  = var.enable_validation
    enable_permission_checks = true  # Requires iam:SimulatePrincipalPolicy
    enable_oidc_validation   = false # Requires iam:GetOpenIDConnectProvider
  }
}
