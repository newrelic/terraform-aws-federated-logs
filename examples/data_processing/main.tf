module "data_processing" {
  source = "../../modules/data_processing"

  data_processing_module_name = "my-app-logs"
  newrelic_org_id             = "YOUR_NR_ORG_ID"
  fleet_entity_guid           = "YOUR_FLEET_ENTITY_GUID"

  # Flink configuration
  flink_jar_bucket            = "my-flink-jars-bucket"
  newrelic_license_key_secret = "newrelic/license-key"

  # Flink parallelism settings (defaults optimized for I/O-bound workloads per CDD §5)
  # parallelism         = 8   # Number of parallel tasks
  # parallelism_per_kpu = 8   # Tasks per KPU (8 maximizes cost efficiency for I/O workloads)
  # auto_scaling_enabled = false  # Disabled until meaningful parallelism floor is set

  # Checkpoint-aligned commits for EXACTLY_ONCE semantics (CDD §3.5)
  # checkpoint_based_commits_enabled = true

  clusters = {
    "cluster-1" = {
      k8s_namespace            = "federated-logs"
      auth_mode                = "irsa" # "irsa" or "pod_identity"
      k8s_service_account_name = "pcg-writer-sa"
      oidc_provider_arn        = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-2.amazonaws.com/id/EXAMPLE"
    }
  }
}
