module "data_processing" {
  source = "../../modules/data_processing"

  data_processing_module_name = "my-app-logs"
  newrelic_org_id             = "YOUR_NR_ORG_ID"
  fleet_entity_guid           = "YOUR_FLEET_ENTITY_GUID"

  # Flink parallelism settings (optional - defaults: parallelism=1, parallelism_per_kpu=1, auto_scaling=true)
  # parallelism          = 1
  # parallelism_per_kpu  = 1
  # auto_scaling_enabled = true

  clusters = {
    "cluster-1" = {
      k8s_namespace            = "federated-logs"
      auth_mode                = "irsa" # "irsa" or "pod_identity"
      k8s_service_account_name = "pcg-writer-sa"
      oidc_provider_arn        = "arn:aws:iam::864899866645:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/DEADBEEFDEADBEEFDEADBEEFDEADBEEF"
    }
  }

  # Optional: verify each IRSA cluster's oidc_provider_arn exists in the AWS account.
  # Requires iam:GetOpenIDConnectProvider on the deploy role. Skipped automatically
  # for Pod Identity clusters.
  # validate_oidc_providers = false
}
