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

output "federated_logs_setup_id" {
  description = "ID of the New Relic federated logs setup"
  value       = newrelic_federated_logs_setup.this.id
}
