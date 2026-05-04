output "validation_summary" {
  description = "Validation module status. Any failures appear as warnings in terraform plan output."
  value       = "Validation checks evaluated. Review any warnings above."
}

output "permission_checks_enabled" {
  description = "Whether IAM policy simulation checks were enabled"
  value       = var.enable_permission_checks
}

output "oidc_validation_enabled" {
  description = "Whether OIDC provider existence checks were enabled"
  value       = var.enable_oidc_validation
}
