locals {
  naming_prefix = "newrelic-fed-logs-fleet-${var.data_processing_module_name}"

  auth_mode = length(var.clusters) > 0 ? values(var.clusters)[0].auth_mode : "irsa"

  nr_graphql_endpoint = var.newrelic_region == "EU" ? "https://api.eu.newrelic.com/graphql" : (
    var.newrelic_region == "STAGING" ? "https://staging-api.newrelic.com/graphql" : "https://api.newrelic.com/graphql"
  )

  # ArnLike pattern for same-account EventBridge rules in the fleet account.
  # Used as the aws:SourceArn condition on the SQS queue policy's same-account
  # statement (events.amazonaws.com service-principal path).
  same_account_eventbridge_rule_arn_pattern = "arn:aws:events:*:${data.aws_caller_identity.current.account_id}:rule/newrelic-fed-logs-*-iceberg-file-created"

  # ArnLike patterns for the per-setup eb-to-sqs IAM roles in each cross-account
  # source account. aws:PrincipalArn for an assumed-role session resolves to the
  # role's IAM ARN, so ArnLike against these patterns is the cross-account trust
  # gate on the SQS queue policy. Empty when allowed_source_account_ids is unset,
  # in which case the cross-account statement is omitted entirely.
  cross_account_eb_role_arn_patterns = [
    for account_id in var.allowed_source_account_ids :
    "arn:aws:iam::${account_id}:role/newrelic-fed-logs-*-eb-to-sqs"
  ]
}
