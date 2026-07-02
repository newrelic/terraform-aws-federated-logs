output "base_role_arn" {
  description = "ARN of the fleet-level PCG base role. Pass this to each federated_logs_setup module as base_role_arn."
  value       = module.data_processing.base_role_arn
}

output "base_role_name" {
  description = "Name of the fleet-level PCG base role."
  value       = module.data_processing.base_role_name
}

output "e2e_validation_status" {
  description = "Parsed PASS/FAIL status of the most recent e2e Lambda invocation. null when e2e_validation_config.enabled = false."
  value       = module.data_processing.e2e_validation_status
}

output "e2e_validation_result" {
  description = "JSON result (status, exit_code, stdout, stderr) of the most recent e2e Lambda invocation. null when e2e_validation_config.enabled = false."
  value       = module.data_processing.e2e_validation_result
}

