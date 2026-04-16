module "setup" {
  source           = "./modules/federated_logs_setup_resource"
  setup_name       = var.setup_name
  region           = var.region
  newrelic_api_key = var.newrelic_api_key
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
  source                = "./modules/federated_logs_partition"
  setup_name            = module.setup.setup_name
  s3_bucket_name        = module.setup.s3_bucket_name
  glue_catalog_db_name  = module.setup.glue_catalog_db_name
  glue_service_role_arn = module.role.glue_service_role_arn
  default_table_setting = var.default_table_setting
  partition_tables      = var.partition_tables
  retention_period      = var.retention_period
}