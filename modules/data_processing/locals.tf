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
}
