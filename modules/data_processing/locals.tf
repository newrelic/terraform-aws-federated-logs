locals {
  naming_prefix = "newrelic-fed-logs-fleet-${var.data_processing_module_name}"

  auth_mode = length(var.clusters) > 0 ? values(var.clusters)[0].auth_mode : "irsa"

  nr_graphql_endpoint = var.newrelic_region == "EU" ? "https://api.eu.newrelic.com/graphql" : (
    var.newrelic_region == "STAGING" ? "https://staging-api.newrelic.com/graphql" : "https://api.newrelic.com/graphql"
  )
}
