# Creates the base resources: S3 bucket and Glue catalog database
module "federated_logs_setup_resource" {
  source         = "./modules/federated_logs_setup_resource"
  naming_prefix  = var.naming_prefix
  aws_account_id = var.aws_account_id
}

# Creates the necessary permissions for all the components to work together
module "federated_logs_role" {
  source               = "./modules/federated_logs_role"
  s3_bucket_name       = module.federated_logs_setup_resource.s3_bucket_name
  glue_catalog_db_name = module.federated_logs_setup_resource.glue_catalog_db_name
  nr_user_key          = "NRAK-1234-****"
  nr_account_id        = "12345678"
  clusters             = var.clusters
}

module "federated_logs_partition" {
  source = "./modules/federated_logs_partition"

  s3_bucket_name        = module.federated_logs_setup_resource.s3_bucket_name
  glue_catalog_db_name  = module.federated_logs_setup_resource.glue_catalog_db_name
  glue_service_role_arn = module.federated_logs_role.glue_service_role_arn
  aws_connection_entity = module.federated_logs_role.aws_connection_entity
  aws_account_id        = var.aws_account_id

  nr_user_key          = "NRAK-1234-****"
  log_retention_policy = "5 DAYS" # this is NR specific log retention policy for a partition 

  # The name of default table will be fixed.
  # Below are optimisation setting for default table
  default_table_setting = {
    enable_compaction           = true
    enable_retention            = true
    enable_orphan_file_deletion = true

    orphan_file_deletion = {
      delete_after_days = 3
    }

    # Snapshot Retention params OPTIONAL
    snapshot_retention = {
      days_snapshot_kept      = 5
      min_snapshots_to_retain = 2
      delete_associated_files = true
    }

    # Compaction related params OPTIONAL
    compaction_config = {
      min_input_files       = 50
      delete_file_threshold = 5
    }
  }

  non_default_tables = var.non_default_tables
}