locals {

  setup_naming_prefix = "newrelic-fed-logs-${var.setup_name}"

  //TODO: Need to finalise on the account id we wish to move forward with
  nr_source_account = "864899866645" # New Relic AWS account ID for cross-account acces
}