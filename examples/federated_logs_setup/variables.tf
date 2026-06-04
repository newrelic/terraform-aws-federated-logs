variable "fleet_entity_guid" {
  description = "NGEP entity GUID of the fleet. Used to look up the SQS queue ARN from the AWS Connection Entity."
  type        = string
}

variable "newrelic_org_id" {
  description = "New Relic organization ID (UUID)."
  type        = string
}

variable "newrelic_api_key" {
  description = "New Relic User API key (NRAK-...). Used by the newrelic provider for resource creation."
  type        = string
  sensitive   = true
}

