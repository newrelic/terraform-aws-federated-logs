module "setup" {
  source     = "./modules/federated_logs_setup_resource"
  setup_name = var.setup_name
  region     = var.region
}

module "role" {
  source                       = "./modules/federated_logs_role"
  setup_name                   = var.setup_name
  s3_bucket_name               = module.setup.s3_bucket_name
  glue_catalog_db_name         = module.setup.glue_catalog_db_name
  fleet_entity_guid            = var.fleet_entity_guid
  newrelic_region              = var.newrelic_region
  newrelic_org_id              = var.newrelic_org_id
  newrelic_account_id          = var.newrelic_account_id
  region                       = var.region
  setup_description            = var.setup_description
  query_connection_description = var.query_connection_description
  default_table_setting        = var.default_table_setting
}

module "notifications" {
  source              = "./modules/federated_logs_setup_notifications"
  setup_name          = module.setup.setup_name
  s3_bucket_id        = module.setup.s3_bucket_name
  pcg_writer_role_arn = module.role.pcg_writer_role_arn
  sqs_queue_arn       = module.role.sqs_queue_arn_from_ngep
}

module "partition" {
  source                 = "./modules/federated_logs_partition"
  setup_name             = var.setup_name
  setup_id               = module.role.setup_id
  s3_bucket_name         = module.setup.s3_bucket_name
  glue_catalog_db_name   = module.setup.glue_catalog_db_name
  glue_service_role_arn  = module.role.glue_service_role_arn
  default_table_setting  = var.default_table_setting
  partition_tables       = var.partition_tables
  region                 = var.region
  data_retention_enabled = var.data_retention_enabled
  newrelic_account_id    = var.newrelic_account_id
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

module "e2e_validation" {
  count  = var.e2e_validation_config.enabled ? 1 : 0
  source = "./modules/federated_logs_e2e_validation"

  pcg_endpoint  = var.e2e_validation_config.pcg_endpoint
  nr_account_id = var.e2e_validation_config.nr_account_id
  nr_region     = var.e2e_validation_config.nr_region
  setup_id      = module.role.setup_id

  depends_on = [module.setup, module.role, module.partition]
}