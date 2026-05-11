output "validation_id" {
  description = "null_resource id of the validation run. Check the local-exec stdout above for PASS/FAIL and the injected test UUID."
  value       = null_resource.e2e_validation.id
}

output "script_path" {
  description = "Absolute path to the e2e_test.py script. Useful for manual invocation outside Terraform."
  value       = "${path.module}/scripts/e2e_test.py"
}
