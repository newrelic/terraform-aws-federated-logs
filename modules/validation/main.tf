data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  s3_bucket_arn  = "arn:aws:s3:::${var.s3_bucket_name}"
  s3_object_arn  = "arn:aws:s3:::${var.s3_bucket_name}/*"
  glue_catalog   = "arn:aws:glue:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:catalog"
  glue_db_arn    = "arn:aws:glue:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:database/${var.glue_database_name}"
  glue_table_arn = "arn:aws:glue:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:table/${var.glue_database_name}/*"

  glue_role_name       = element(split("/", var.glue_service_role_arn), length(split("/", var.glue_service_role_arn)) - 1)
  pcg_writer_role_name = element(split("/", var.pcg_writer_role_arn), length(split("/", var.pcg_writer_role_arn)) - 1)
  nr_reader_role_name  = element(split("/", var.nr_reader_role_arn), length(split("/", var.nr_reader_role_arn)) - 1)
  oidc_arns = var.enable_oidc_validation ? {
    for k, v in var.clusters : k => v.oidc_provider_arn
  } : {}
}

# ──────────────────────────────────────────────────────────────
# OIDC Provider Existence Check
#
# Verifies that each cluster's OIDC provider ARN actually exists
# in the AWS account. A typo or deleted OIDC provider will cause
# AssumeRoleWithWebIdentity to fail at runtime with a cryptic
# "Not authorized to perform sts:AssumeRoleWithWebIdentity" error.
#
# Requires: iam:GetOpenIDConnectProvider
# Gated by: var.enable_oidc_validation (default false)
# ──────────────────────────────────────────────────────────────

data "aws_iam_openid_connect_provider" "cluster" {
  for_each = local.oidc_arns
  arn      = each.value
}

check "oidc_providers_exist" {
  assert {
    condition = !var.enable_oidc_validation || alltrue([
      for k, v in local.oidc_arns :
      data.aws_iam_openid_connect_provider.cluster[k].arn == v
    ])
    error_message = "One or more OIDC provider ARNs from the clusters map do not exist in this AWS account. EKS pods will not be able to assume the PCG writer role."
  }
}