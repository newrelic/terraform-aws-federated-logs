module "data_processing" {
  source = "../../../../modules/data_processing"

  data_processing_module_name = var.data_processing_name
  newrelic_org_id             = var.newrelic_org_id
  fleet_entity_guid           = var.fleet_entity_guid
  newrelic_region             = var.newrelic_region

  clusters = {
    "test-cluster" = {
      auth_mode                = "irsa"
      k8s_namespace            = "federated-logs-test"
      k8s_service_account_name = "pcg-writer-sa-test"
      oidc_provider_arn        = "arn:aws:iam::000000000000:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/PLACEHOLDER"
    }
  }
}

module "setup" {
  source     = "../../../../modules/federated_logs_setup_resource"
  setup_name = var.setup_name
  region     = var.aws_region
}

module "role" {
  source               = "../../../../modules/federated_logs_role"
  setup_name           = var.setup_name
  s3_bucket_name       = module.setup.s3_bucket_name
  glue_catalog_db_name = module.setup.glue_catalog_db_name
  fleet_entity_guid    = var.fleet_entity_guid
  newrelic_org_id      = var.newrelic_org_id
  newrelic_account_id  = var.newrelic_account_id
  newrelic_region      = var.newrelic_region
  region               = var.aws_region

  depends_on = [module.data_processing]
}

module "partition" {
  source                = "../../../../modules/federated_logs_partition"
  setup_name            = var.setup_name
  s3_bucket_name        = module.setup.s3_bucket_name
  glue_catalog_db_name  = module.setup.glue_catalog_db_name
  glue_service_role_arn = module.role.glue_service_role_arn
  setup_id              = module.role.setup_id
  newrelic_account_id   = var.newrelic_account_id
  default_table_setting = var.default_table_setting
  partition_tables      = var.partition_tables
  region                = var.aws_region
}
