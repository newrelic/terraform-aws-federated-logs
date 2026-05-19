module "data_processing" {
  source = "../../modules/data_processing"

  data_processing_module_name = "my-app-logs"
  newrelic_org_id             = "YOUR_NR_ORG_ID"
  fleet_entity_guid           = "YOUR_FLEET_ENTITY_GUID"

  # EventBridge rule ARN from the federated_logs_setup_resource module
  eventbridge_rule_arn = "arn:aws:events:us-east-2:123456789012:rule/newrelic-fed-logs-my-setup-iceberg-file-created"

  # Flink configuration
  flink_jar_bucket            = "my-flink-jars-bucket"
  newrelic_license_key_secret = "newrelic/license-key"

  clusters = {
    "cluster-1" = {
      k8s_namespace            = "federated-logs"
      auth_mode                = "irsa" # "irsa" or "pod_identity"
      k8s_service_account_name = "pcg-writer-sa"
      oidc_provider_arn        = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-2.amazonaws.com/id/EXAMPLE"
    }
  }
}
