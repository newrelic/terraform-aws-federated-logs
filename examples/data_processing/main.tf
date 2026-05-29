module "data_processing" {
  source = "../../modules/data_processing"

  data_processing_module_name = "my-app-logs"
  newrelic_org_id             = "YOUR_NR_ORG_ID"
  fleet_entity_guid           = "YOUR_FLEET_ENTITY_GUID"

  # Flink configuration
  flink_jar_bucket = "my-flink-jars-bucket"

  # Flink parallelism settings (optional - defaults: parallelism=1, parallelism_per_kpu=1, auto_scaling=true)
  # parallelism          = 1
  # parallelism_per_kpu  = 1
  # auto_scaling_enabled = true

  clusters = {
    "cluster-1" = {
      k8s_namespace            = "federated-logs"
      auth_mode                = "irsa" # "irsa" or "pod_identity"
      k8s_service_account_name = "pcg-writer-sa"
      oidc_provider_arn        = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-2.amazonaws.com/id/EXAMPLE"
    }
  }
}
