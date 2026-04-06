output "validation_run_id" {
  description = "The run ID used for this validation invocation."
  value       = var.run_validation ? local.run_id : null
}

output "validation_executed" {
  description = "Whether end-to-end validation was executed."
  value       = var.run_validation
}
