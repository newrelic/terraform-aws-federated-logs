# =============================================================================
# NerdGraph lookup — resolve base role from data_processing entity
# =============================================================================

locals {
  nr_endpoint = var.newrelic_region == "EU" ? "https://api.eu.newrelic.com/graphql" : "https://api.newrelic.com/graphql"
}

data "http" "data_processing_entity" {
  url    = local.nr_endpoint
  method = "POST"

  request_headers = {
    Content-Type = "application/json"
    API-Key      = var.newrelic_user_api_key
  }

  request_body = jsonencode({
    query = <<-GRAPHQL
      {
        actor {
          entity(guid: "${var.data_processing_entity_id}") {
            ... on FederatedLogsDataProcessingEntity {
              baseRoleArn
              name
            }
          }
        }
      }
    GRAPHQL
  })

  lifecycle {
    postcondition {
      condition     = self.status_code == 200
      error_message = "NerdGraph API returned status ${self.status_code}."
    }
  }
}

locals {
  entity_response = jsondecode(data.http.data_processing_entity.response_body)
  base_role_arn   = local.entity_response.data.actor.entity.baseRoleArn
  pcg_instance_id = local.entity_response.data.actor.entity.name
}

# =============================================================================
# Setup resources — S3 bucket + Glue database
# =============================================================================

module "setup" {
  source     = "./modules/federated_logs_setup_resource"
  setup_name = var.setup_name
}

# =============================================================================
# IAM roles — Glue service, PCG writer (trusts base role), NR reader
# =============================================================================

module "role" {
  source               = "./modules/federated_logs_role"
  setup_name           = module.setup.setup_name
  s3_bucket_name       = module.setup.s3_bucket_name
  glue_catalog_db_name = module.setup.glue_catalog_db_name
  base_role_arn        = local.base_role_arn
  pcg_instance_id      = local.pcg_instance_id
}

module "partition" {
  source                = "./modules/federated_logs_partition"
  setup_name            = module.setup.setup_name
  s3_bucket_name        = module.setup.s3_bucket_name
  glue_catalog_db_name  = module.setup.glue_catalog_db_name
  glue_service_role_arn = module.role.glue_service_role_arn
  default_table_setting = var.default_table_setting
  partition_tables      = var.partition_tables
}