output "base_role_arn" {
  description = "ARN of the fleet-level PCG base role. Pass this to each federated_logs_setup module as base_role_arn."
  value       = aws_iam_role.base_role.arn
}

output "base_role_name" {
  description = "Name of the fleet-level PCG base role."
  value       = aws_iam_role.base_role.name
}

output "aws_connection_entity_name" {
  description = "Name of the AWS Connection entity created in New Relic. Use this to look up the entity in the NR UI."
  value       = "${local.naming_prefix}-aws-connection"
}

output "base_role_tags" {
  description = "Tags applied to the fleet-level base role."
  value       = aws_iam_role.base_role.tags
}

output "abac_policy_json" {
  description = "JSON of the ABAC inline policy attached to the base role."
  value       = aws_iam_role_policy.abac_assume_policy.policy
}