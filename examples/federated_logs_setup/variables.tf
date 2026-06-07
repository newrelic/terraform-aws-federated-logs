variable "fleet_entity_guid" {
  description = "NGEP entity GUID of the fleet. Used to look up the SQS queue ARN from the AWS Connection Entity."
  type        = string
}
variable "enable_validation" {
  description = "Enable post-deploy validation checks. Use: terraform plan -var='enable_validation=true'"
  type        = bool
  default     = false
}

variable "newrelic_org_id" {
  description = "New Relic organization ID (UUID)."
  type        = string
}

