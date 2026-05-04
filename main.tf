module "setup" {
  source     = "./modules/federated_logs_setup_resource"
  setup_name = var.setup_name
  region     = var.region
}

module "role" {
  source               = "./modules/federated_logs_role"
  setup_name           = module.setup.setup_name
  s3_bucket_name       = module.setup.s3_bucket_name
  glue_catalog_db_name = module.setup.glue_catalog_db_name
  clusters             = var.clusters
  region               = var.region
}

module "partition" {
  source                 = "./modules/federated_logs_partition"
  setup_name             = module.setup.setup_name
  s3_bucket_name         = module.setup.s3_bucket_name
  glue_catalog_db_name   = module.setup.glue_catalog_db_name
  glue_service_role_arn  = module.role.glue_service_role_arn
  default_table_setting  = var.default_table_setting
  partition_tables       = var.partition_tables
  region                 = var.region
  data_retention_enabled = var.data_retention_enabled
}

module "validation" {
  count  = var.validation_config.enabled ? 1 : 0
  source = "./modules/validation"

  s3_bucket_name           = module.setup.s3_bucket_name
  glue_database_name       = module.setup.glue_catalog_db_name
  glue_service_role_arn    = module.role.glue_service_role_arn
  pcg_writer_role_arn      = module.role.pcg_writer_role_arn
  nr_reader_role_arn       = module.role.nr_reader_role_arn
  clusters                 = var.clusters
  enable_permission_checks = var.validation_config.enable_permission_checks
  enable_oidc_validation   = var.validation_config.enable_oidc_validation
}