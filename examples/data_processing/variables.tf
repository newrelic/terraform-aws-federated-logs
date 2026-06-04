variable "newrelic_api_key" {
  description = "New Relic User API key (NRAK-...). Used by the newrelic provider for resource creation."
  type        = string
  sensitive   = true
}

variable "newrelic_license_key" {
  description = "New Relic Ingest license key (NRAL-...). Injected into Flink application properties as 'newrelic.license.key'."
  type        = string
  sensitive   = true
}
