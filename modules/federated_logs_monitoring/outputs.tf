output "dashboard_guid" {
  description = "GUID of the created New Relic dashboard."
  value       = newrelic_one_dashboard.this.guid
}

output "dashboard_permalink" {
  description = "Permalink URL to the dashboard in the New Relic UI."
  value       = newrelic_one_dashboard.this.permalink
}
