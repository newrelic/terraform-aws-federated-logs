resource "null_resource" "e2e_validation" {
  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    on_failure  = continue
    working_dir = path.module
    command     = "python3 ${path.module}/scripts/e2e_test.py"

    environment = {
      PCG_ENDPOINT   = var.pcg_endpoint
      NR_LICENSE_KEY = var.license_key
      PARTITION_NAME = var.partition_name
      NR_ACCOUNT_ID  = var.nr_account_id
      NR_API_KEY     = var.nr_api_key
      NR_REGION      = var.nr_region
    }
  }
}
