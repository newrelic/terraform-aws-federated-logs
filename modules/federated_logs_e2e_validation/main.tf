resource "null_resource" "e2e_validation" {
  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    on_failure  = continue
    working_dir = path.module
    command     = "python3 scripts/e2e_test.py"

    environment = {
      PCG_ENDPOINT              = var.pcg_endpoint
      NR_ACCOUNT_ID             = var.nr_account_id
      NR_REGION                 = var.nr_region
      NR_FEDERATEDLOGS_SETUP_ID = var.setup_id
      TEST_PAYLOAD              = var.test_payload
      E2E_MAX_RETRIES           = var.max_retries
      E2E_RETRY_DELAY           = var.retry_delay
      E2E_INITIAL_READ_WAIT     = var.initial_read_wait
    }
  }
}
