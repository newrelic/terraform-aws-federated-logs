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

module "data_processing" {
  source                      = "./modules/data_processing"
  setup_name                  = module.setup.setup_name
  s3_bucket_name              = module.setup.s3_bucket_name
  flink_jar_bucket            = var.flink_jar_bucket
  flink_jar_key               = var.flink_jar_key
  flink_role_arn              = module.data_processing_role.flink_role_arn
  flink_runtime               = var.flink_runtime
  parallelism                 = var.parallelism
  checkpoint_interval_ms      = var.checkpoint_interval_ms
  snapshots_enabled           = var.snapshots_enabled
  sqs_batch_size              = var.sqs_batch_size
  sqs_visibility_timeout      = var.sqs_visibility_timeout
  sqs_message_retention       = var.sqs_message_retention
  sqs_max_receive_count       = var.sqs_max_receive_count
  newrelic_license_key_secret = var.newrelic_license_key_secret
  newrelic_metrics_endpoint   = var.newrelic_metrics_endpoint
  log_retention_days          = var.log_retention_days
  tags                        = var.tags
}

module "data_processing_role" {
  source                   = "./modules/data_processing_role"
  setup_name               = module.setup.setup_name
  s3_bucket_name           = module.setup.s3_bucket_name
  glue_catalog_db_name     = module.setup.glue_catalog_db_name
  flink_jar_bucket         = var.flink_jar_bucket
  sqs_queue_arn            = module.data_processing.sqs_queue_arn
  secrets_manager_prefix   = var.secrets_manager_prefix
  permissions_boundary_arn = var.permissions_boundary_arn
  tags                     = var.tags
}