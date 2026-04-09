output "flink_role_arn" {
  description = "ARN of the IAM role used by Flink commit worker"
  value       = aws_iam_role.flink_commit_worker.arn
}
