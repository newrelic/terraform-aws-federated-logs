output "glue_service_role_arn" {
  description = "ARN of the IAM role used by Glue for table maintenance"
  value       = aws_iam_role.glue_service_role.arn
}

output "pcg_writer_role_arn" {
  description = "ARN of the IAM role for PCG to write federated logs"
  value       = aws_iam_role.pcg-writer-role.arn
}

output "nr_reader_role_arn" {
  description = "ARN of the IAM role for New Relic to query federated logs"
  value       = aws_iam_role.reader-role.arn
}

# Policy document outputs for testing/validation
output "glue_service_policy_json" {
  description = "JSON policy document for the Glue service role"
  value       = aws_iam_policy.glue_service_policy.policy
}

output "pcg_writer_policy_json" {
  description = "JSON policy document for the PCG writer role"
  value       = aws_iam_policy.writer_policy.policy
}

output "nr_reader_policy_json" {
  description = "JSON policy document for the NR reader role"
  value       = aws_iam_policy.reader_policy.policy
}

output "glue_service_trust_policy_json" {
  description = "Trust policy (assume role policy) for the Glue service role"
  value       = aws_iam_role.glue_service_role.assume_role_policy
}

output "pcg_writer_trust_policy_json" {
  description = "Trust policy (assume role policy) for the PCG writer role"
  value       = aws_iam_role.pcg-writer-role.assume_role_policy
}

output "nr_reader_trust_policy_json" {
  description = "Trust policy (assume role policy) for the NR reader role"
  value       = aws_iam_role.reader-role.assume_role_policy
}

output "base_role_arn_from_ngep" {
  description = "Base role ARN resolved from NR NGEP via fleet_entity_guid tag lookup."
  value       = data.external.base_role.result["role_arn"]
}

output "fleet_ingest_connection_id" {
  description = "NGEP guid of the fleet-level AWS Connection entity."
  value       = data.external.base_role.result["base_role_connection_id"]
}

output "sqs_queue_arn_from_ngep" {
  description = "SQS queue ARN resolved from NR NGEP via fleet_entity_guid tag lookup."
  value       = data.external.base_role.result["sqs_queue_arn"]
}

output "flink_base_role_arn_from_ngep" {
  description = "Flink base role ARN resolved from NR NGEP via fleet_entity_guid tag lookup."
  value       = data.external.base_role.result["flink_base_role_arn"]
}

output "pcg_writer_role_tags" {
  description = "Tags applied to the PCG writer role."
  value       = aws_iam_role.pcg-writer-role.tags
}

output "query_connection_id" {
  description = "Entity GUID of the per-setup AWS Connection wrapping the reader role."
  value       = newrelic_aws_connection.query_connection.id
}

output "setup_id" {
  description = "Entity GUID of the newrelic_federated_logs_setup."
  value       = newrelic_federated_logs_setup.this.id
}

output "default_partition_id" {
  description = "Entity GUID of the default partition created alongside the federated logs setup."
  value       = newrelic_federated_logs_setup.this.default_partition_id
}
