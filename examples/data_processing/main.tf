module "data_processing" {
  source = "../../modules/data_processing"

  data_processing_module_name = "my-app-logs"
  newrelic_org_id             = "YOUR_NR_ORG_ID"
  newrelic_api_key            = "YOUR_NR_API_KEY"
  fleet_entity_guid           = "YOUR_FLEET_ENTITY_GUID"

  clusters = {
    "cluster-1" = {
      k8s_namespace            = "federated-logs"
      auth_mode                = "irsa" # "irsa" or "pod_identity"
      k8s_service_account_name = "pcg-writer-sa"
      oidc_provider_arn        = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-2.amazonaws.com/id/EXAMPLE"
    }
  }
}
