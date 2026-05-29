resource "null_resource" "e2e_validation" {
  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    on_failure  = continue
    working_dir = path.module
    command     = "python3 ${path.module}/scripts/e2e_test.py"

    environment = {
      PCG_ENDPOINT              = var.pcg_endpoint
      NR_ACCOUNT_ID             = var.nr_account_id
      NR_REGION                 = var.nr_region
      NR_FEDERATEDLOGS_SETUP_ID = var.setup_id
    }
  }
}
