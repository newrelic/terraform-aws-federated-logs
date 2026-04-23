output "base_role_arn" {
  description = "ARN of the fleet-level PCG base role. Pass this to each federated_logs_setup module as base_role_arn."
  value       = aws_iam_role.base_role.arn
}

output "base_role_name" {
  description = "Name of the fleet-level PCG base role."
  value       = aws_iam_role.base_role.name
}

output "pcg_instance_name" {
  description = "The PCG_Instance tag value. Pass this to each federated_logs_setup module as pcg_instance_name."
  value       = var.setup_name
}

# TODO: Expose aws_connection_entity_id and data_processing_entity_id once mutations are stable.
