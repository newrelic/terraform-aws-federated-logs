# Creates the base resources: S3 bucket and Glue catalog database

module "federated_logs_setup_resource" {
  source     = "./modules/federated_logs_setup_resource"
  setup_name = var.setup_name
}

# Creates the necessary permissions for all the components to work together
module "federated_logs_role" {
  source                 = "./modules/federated_logs_role"
  s3_bucket_name       = module.federated_logs_setup_resource.s3_bucket_name
  glue_catalog_db_name = module.federated_logs_setup_resource.glue_catalog_db_name
  clusters             = var.clusters
  setup_name           = var.setup_name
}

module "federated_logs_partition" {
  source                = "./modules/federated_logs_partition"
  s3_bucket_name        = module.federated_logs_setup_resource.s3_bucket_name
  glue_catalog_db_name  = module.federated_logs_setup_resource.glue_catalog_db_name
  glue_service_role_arn = module.federated_logs_role.glue_service_role_arn
  setup_name            = var.setup_name
  default_table_setting = {
    table_parameters = {
      write_target_file_size_bytes               = "5242880" # 5 MB
      write_metadata_delete_after_commit_enabled = "true"
      write_metadata_previous_versions_max       = "1"
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
    }
  }
  partition_tables = {
    "Log_federated_application_log" = {
      table_parameters = {
        write_target_file_size_bytes               = "26214400" # 25 MB
        write_metadata_delete_after_commit_enabled = "true"
        write_metadata_previous_versions_max       = "10"
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
      }
    },
    "Log_federated_security_log" = {
      table_parameters = {
        write_target_file_size_bytes               = "26214400" # 25 MB
        write_metadata_delete_after_commit_enabled = "true"
        write_metadata_previous_versions_max       = "10"
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
      }
    }
  }
}
