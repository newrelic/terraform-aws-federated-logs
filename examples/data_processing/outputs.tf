output "base_role_arn" {
  description = "ARN of the fleet-level PCG base role. Pass this to each federated_logs_setup module as base_role_arn."
  value       = module.data_processing.base_role_arn
}

output "base_role_name" {
  description = "Name of the fleet-level PCG base role."
  value       = module.data_processing.base_role_name
}

output "pcg_instance_name" {
  description = "The PCG_Instance tag value. Pass this to each federated_logs_setup module as pcg_instance_name."
  value       = module.data_processing.pcg_instance_name
}
