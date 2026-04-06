locals {
  run_id = var.validation_run_id != "" ? var.validation_run_id : formatdate("YYYYMMDDhhmmss", timestamp())
}
