output "function_name" {
  description = "Name of the validation Lambda. Use this to invoke on-demand: aws lambda invoke --function-name <name> /dev/stdout."
  value       = aws_lambda_function.e2e_validation.function_name
}

output "function_arn" {
  description = "ARN of the validation Lambda."
  value       = aws_lambda_function.e2e_validation.arn
}

output "execution_role_arn" {
  description = "ARN of the Lambda execution role. Useful when auditing the IAM permission footprint of the validation feature."
  value       = aws_iam_role.e2e_lambda.arn
}

output "invocation_result" {
  description = "Result of the most recent Lambda invocation as a JSON string. Includes status (PASS/FAIL), exit_code, stdout, and stderr from the e2e script. Empty when validation runs for the first time and the invocation hasn't completed yet."
  value       = aws_lambda_invocation.e2e_validation.result
}

output "invocation_status" {
  description = "Parsed PASS/FAIL status of the most recent invocation. PASS means all 5 e2e steps succeeded; FAIL means at least one step failed (see invocation_result for details)."
  value       = try(jsondecode(aws_lambda_invocation.e2e_validation.result).status, "UNKNOWN")
}
