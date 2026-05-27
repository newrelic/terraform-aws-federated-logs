locals {
  setup_naming_prefix = "newrelic-fed-logs-${var.setup_name}"

  # Logging Federated
  nr_source_account = "531948421264"

  # WARNING [DO NOT CHANGE]: Cross-repo contract with the NR hub. 
  # Editing this suffix will break cross-account
  # assumption at runtime.
  nr_reader_role_suffix = "nr-query"

  nr_graphql_endpoint = var.newrelic_region == "EU" ? "https://api.eu.newrelic.com/graphql" : (
    var.newrelic_region == "STAGING" ? "https://staging-api.newrelic.com/graphql" : "https://api.newrelic.com/graphql"
  )

  # Glue table name for the default partition. Syncs with the partition module's
  # naming convention so the table name on
  # newrelic_federated_logs_setup.default_partition.storage.table matches the
  # aws_glue_catalog_table the partition module actually creates for the default.
  default_partition_table = substr(replace(lower("newrelic_fed_logs_${var.setup_name}_Log_Federated"), "/[^a-z0-9_]/", "_"), 0, 255)

}