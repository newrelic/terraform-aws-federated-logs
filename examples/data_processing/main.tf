module "data_processing" {
  source = "../../modules/data_processing"

  data_processing_module_name = "my-app-logs"
  newrelic_org_id             = "YOUR_NR_ORG_ID"
  fleet_entity_guid           = "YOUR_FLEET_ENTITY_GUID"
  newrelic_region             = "US"
  allowed_source_account_ids  = [] # Cross-account only: list the account ID(s) where the federated_logs setup is deployed

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

  # Optional: run an end-to-end validation after apply.
  # Requires NEW_RELIC_LICENSE_KEY and NEW_RELIC_API_KEY in the runner env.
  # The validation deploys an AWS Lambda inside your VPC that:
  #   1. POSTs a synthetic log to your PCG endpoint
  #   2. Polls NRDB for the log via NRQL
  #   3. Reports HEALTHY/UNHEALTHY back to NR via the
  #      federatedLogsUpdateSetup mutation


  e2e_validation_config = {
    enabled      = false
    pcg_endpoint = "https://pcg.example.com"
    test_payload = jsonencode({ message = "federated-logs e2e test", level = "info" })

    # Subnets need a private route to PCG + outbound internet (NAT) to api.newrelic.com.
    vpc_config = {
      subnet_ids         = ["subnet-0a1b2c3d4e5f60718", "subnet-0a1b2c3d4e5f60719"]
      security_group_ids = ["sg-0a1b2c3d4e5f60710"]
    }

    # data_processing cannot derive these — supply them explicitly:
    #   setup_id      = the federated_logs deploy's `newrelic_federated_logs_setup_id` output
    #   nr_account_id = your New Relic account ID
    setup_id      = "YOUR_FEDERATED_LOGS_SETUP_ID"
    nr_account_id = 1234567

    # Optional tuning — defaults shown:
    # lambda_timeout     = 180
    # lambda_memory_size = 256
    # max_retries        = 3
    # retry_delay        = 5
    # initial_read_wait  = 30
    # read_max_retries   = 5
    # read_retry_delay   = 15
  }
}
