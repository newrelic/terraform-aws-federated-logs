locals {
  naming_prefix = "newrelic-fed-logs-fleet-${var.data_processing_module_name}"

  auth_mode = length(var.clusters) > 0 ? values(var.clusters)[0].auth_mode : "irsa"

  nr_graphql_endpoint = var.newrelic_region == "EU" ? "https://api.eu.newrelic.com/graphql" : (
    var.newrelic_region == "STAGING" ? "https://staging-api.newrelic.com/graphql" : "https://api.newrelic.com/graphql"
  )

  # Combine current account with any additional allowed accounts (deduplicated)
  all_allowed_account_ids = distinct(concat(
    [data.aws_caller_identity.current.account_id],
    var.allowed_source_account_ids
  ))

  # ArnLike patterns for SQS policy - one per allowed account
  # Matches EventBridge rules following the newrelic-fed-logs-*-iceberg-file-created naming convention
  sqs_eventbridge_source_arn_patterns = [
    for account_id in local.all_allowed_account_ids :
    "arn:aws:events:*:${account_id}:rule/newrelic-fed-logs-*-iceberg-file-created"
  ]

  # Map of cluster name → OIDC ARN, populated only when:
  #   1. var.validate_oidc_providers is true (opt-in), and
  #   2. auth_mode is "irsa" (Pod Identity clusters don't use OIDC providers).
  # Used by the oidc_providers_exist check in validation.tf.
  oidc_arns_to_validate = (
    var.validate_oidc_providers && local.auth_mode == "irsa"
    ) ? {
    for k, v in var.clusters : k => v.oidc_provider_arn
  } : {}
}
