data "aws_region" "current" {
  region = var.region
}

resource "aws_s3_bucket" "this" {
  bucket = local.setup_naming_prefix
  region = data.aws_region.current.id
}

resource "aws_glue_catalog_database" "this" {
  name        = lower(replace(local.setup_naming_prefix, "-", "_"))
  description = "Glue database containing NR resources for federated logs"
  region      = data.aws_region.current.id
}

# AWS Secrets Manager secret to store New Relic API key (always created)
resource "aws_secretsmanager_secret" "newrelic_api_key" {
  name        = "${local.setup_naming_prefix}-newrelic-api-key"
  description = "New Relic API key for NGEP API authentication"
}

resource "aws_secretsmanager_secret_version" "newrelic_api_key" {
  secret_id = aws_secretsmanager_secret.newrelic_api_key.id
  secret_string = jsonencode({
    api_key = var.newrelic_api_key
  })
}