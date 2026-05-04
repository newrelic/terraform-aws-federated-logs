variable "enable_validation" {
  description = "Enable post-deploy validation checks. Use: terraform plan -var='enable_validation=true'"
  type        = bool
  default     = false
}
