locals {

  setup_naming_prefix = "newrelic-fed-logs-${var.setup_name}"

  //TODO: Need to finalise on the account id we wish to move forward with
  nr_source_account = "864899866645" # New Relic AWS account ID for cross-account access

  # Derive auth mode for pcg-writer-role (all clusters are validated to use the same value)
  pcg_auth_mode = length(var.clusters) > 0 ? values(var.clusters)[0].auth_mode : "irsa"
}