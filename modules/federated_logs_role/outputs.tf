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

output "aws_connection_entity" {
  description = "AWS connection entity details"
  value       = ""
}
