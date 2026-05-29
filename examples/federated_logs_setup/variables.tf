variable "fleet_entity_guid" {
  description = "NGEP entity GUID of the fleet. Used to look up the SQS queue ARN from the AWS Connection Entity."
  type        = string
}
