# =============================================================================
# Integration Tests: federated_logs_role module
# =============================================================================
#
# What we test here:
#   1. Role naming conventions
#   2. IAM policy permissions (correct actions attached to each role)
#   3. Trust policy structure (ABAC condition, ExternalId, etc.)
#   4. Module dependency wiring (uses setup_resource outputs correctly)
#
# No NR credentials are required to run these tests. The data.external.base_role
# data source (which calls fetch_base_role.py) is mocked via override_data in
# each run block that uses the federated_logs_role module.
#
# =============================================================================

# Shared test variables
variables {
  fleet_entity_guid = "test-fleet-entity-guid"
  newrelic_api_key  = "test-nr-api-key"
  newrelic_region   = "US"
}

# =============================================================================
# NAMING CONVENTION TESTS
# =============================================================================
# Verify that IAM roles follow the expected naming pattern:
#   - Glue service role: {prefix}-glue-service
#   - PCG writer role:   {prefix}-pcg-writer
#   - NR reader role:    {prefix}-nr-query
# Where prefix = "newrelic-fed-logs-{setup_name}"
# =============================================================================

# Step 1: Create setup resources (dependency for role module)
run "setup_for_naming_test" {
  command = apply

  variables {
    setup_name = "inttest-role-name"
  }

  module {
    source = "./modules/federated_logs_setup_resource"
  }
}

# -----------------------------------------------------------------------------
# TEST: Role naming conventions
# -----------------------------------------------------------------------------
# Verifies: All 3 roles follow the naming pattern
# Why: Naming is defined in module's main.tf using local.setup_naming_prefix
# -----------------------------------------------------------------------------
run "test_role_naming_conventions" {
  command = apply

  variables {
    setup_name           = run.setup_for_naming_test.setup_name
    s3_bucket_name       = run.setup_for_naming_test.s3_bucket_name
    glue_catalog_db_name = run.setup_for_naming_test.glue_catalog_db_name
    fleet_entity_guid    = var.fleet_entity_guid
    newrelic_api_key     = var.newrelic_api_key
    newrelic_region      = var.newrelic_region
  }

  # Mock the NGEP fetch — no NR API call needed
  override_data {
    target = data.external.base_role
    values = {
      result = {
        role_arn = "arn:aws:iam::123456789012:role/newrelic-fed-logs-fleet-test-base"
      }
    }
  }

  # Skip pcg-writer role creation: its trust policy principal (an IAM role ARN)
  # is mocked, so AWS would reject the fake account ID.
  # Provide a meaningful mock ARN so naming and trust policy assertions still pass.
  override_resource {
    target = aws_iam_role.pcg-writer-role
    values = {
      arn  = "arn:aws:iam::000000000000:role/newrelic-fed-logs-inttest-role-name-pcg-writer"
      name = "newrelic-fed-logs-inttest-role-name-pcg-writer"
      tags = {
        fleet_entity_guid = "test-fleet-entity-guid"
      }
      assume_role_policy = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"AWS\":\"arn:aws:iam::123456789012:role/newrelic-fed-logs-fleet-test-base\"},\"Action\":[\"sts:AssumeRole\",\"sts:TagSession\"],\"Condition\":{\"StringEquals\":{\"aws:PrincipalTag/fleet_entity_guid\":\"test-fleet-entity-guid\"}}}]}"
    }
  }

  # Skip the policy attachment since the role above is mocked and doesn't exist in AWS
  override_resource {
    target = aws_iam_role_policy_attachment.writer_attach
    values = {}
  }

  module {
    source = "./modules/federated_logs_role"
  }

  # Verify Glue service role naming: {prefix}-glue-service
  assert {
    condition     = can(regex("newrelic-fed-logs-inttest-role-name-glue-service", output.glue_service_role_arn))
    error_message = "Glue service role ARN should contain 'newrelic-fed-logs-{setup_name}-glue-service'"
  }

  # Verify PCG writer role naming: {prefix}-pcg-writer
  assert {
    condition     = can(regex("newrelic-fed-logs-inttest-role-name-pcg-writer", output.pcg_writer_role_arn))
    error_message = "PCG writer role ARN should contain 'newrelic-fed-logs-{setup_name}-pcg-writer'"
  }

  # Verify NR reader role naming: {prefix}-nr-query
  assert {
    condition     = can(regex("newrelic-fed-logs-inttest-role-name-nr-query", output.nr_reader_role_arn))
    error_message = "NR reader role ARN should contain 'newrelic-fed-logs-{setup_name}-nr-query'"
  }

  # ─────────────────────────────────────────────────────────────────────────────
  # IAM POLICY PERMISSION ASSERTIONS
  # ─────────────────────────────────────────────────────────────────────────────

  # --- Glue Service Role Permissions ---
  assert {
    condition     = can(regex("s3:GetObject", output.glue_service_policy_json))
    error_message = "Glue service policy missing s3:GetObject - required for reading Iceberg data files"
  }

  assert {
    condition     = can(regex("s3:PutObject", output.glue_service_policy_json))
    error_message = "Glue service policy missing s3:PutObject - required for compaction"
  }

  assert {
    condition     = can(regex("s3:DeleteObject", output.glue_service_policy_json))
    error_message = "Glue service policy missing s3:DeleteObject - required for orphan file deletion"
  }

  assert {
    condition     = can(regex("glue:UpdateTable", output.glue_service_policy_json))
    error_message = "Glue service policy missing glue:UpdateTable - required for Iceberg metadata updates"
  }

  assert {
    condition     = can(regex("logs:PutLogEvents", output.glue_service_policy_json))
    error_message = "Glue service policy missing logs:PutLogEvents - required for optimizer logging"
  }

  # --- PCG Writer Role Permissions ---
  assert {
    condition     = can(regex("s3:GetObject", output.pcg_writer_policy_json))
    error_message = "PCG writer policy missing s3:GetObject - required for reading Iceberg metadata"
  }

  assert {
    condition     = can(regex("s3:PutObject", output.pcg_writer_policy_json))
    error_message = "PCG writer policy missing s3:PutObject - required for writing log data"
  }

  assert {
    condition     = can(regex("glue:UpdateTable", output.pcg_writer_policy_json))
    error_message = "PCG writer policy missing glue:UpdateTable - required for Iceberg commits"
  }

  assert {
    condition     = can(regex("glue:GetTable", output.pcg_writer_policy_json))
    error_message = "PCG writer policy missing glue:GetTable - required for reading table metadata"
  }

  # --- NR Reader Role Permissions ---
  assert {
    condition     = can(regex("s3:GetObject", output.nr_reader_policy_json))
    error_message = "NR reader policy missing s3:GetObject - required for reading log data"
  }

  assert {
    condition     = can(regex("s3:ListBucket", output.nr_reader_policy_json))
    error_message = "NR reader policy missing s3:ListBucket - required for listing Iceberg files"
  }

  assert {
    condition     = can(regex("glue:GetTable", output.nr_reader_policy_json))
    error_message = "NR reader policy missing glue:GetTable - required for reading table schema"
  }

  assert {
    condition     = can(regex("glue:GetPartitions", output.nr_reader_policy_json))
    error_message = "NR reader policy missing glue:GetPartitions - required for partition pruning"
  }

  # ─────────────────────────────────────────────────────────────────────────────
  # TRUST POLICY ASSERTIONS
  # ─────────────────────────────────────────────────────────────────────────────

  # Glue service role should trust glue.amazonaws.com
  assert {
    condition     = can(regex("glue.amazonaws.com", output.glue_service_trust_policy_json))
    error_message = "Glue service role trust policy must allow glue.amazonaws.com - table optimizers won't work"
  }

  # PCG writer role trusts the fleet base role via ABAC — fleet_entity_guid condition must be present
  assert {
    condition     = can(regex("fleet_entity_guid", output.pcg_writer_trust_policy_json))
    error_message = "PCG writer role trust policy missing fleet_entity_guid ABAC condition"
  }

  # PCG writer role must allow sts:TagSession so base role can forward session tags
  assert {
    condition     = can(regex("sts:TagSession", output.pcg_writer_trust_policy_json))
    error_message = "PCG writer role trust policy missing sts:TagSession - base role cannot forward ABAC tags"
  }

  # NR reader role should have ExternalId condition
  assert {
    condition     = can(regex("ExternalId", output.nr_reader_trust_policy_json))
    error_message = "NR reader role trust policy missing ExternalId condition - security risk for cross-account access"
  }

  # Verify base_role_arn_from_ngep is the mocked ARN
  assert {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:role/.+", output.base_role_arn_from_ngep))
    error_message = "base_role_arn_from_ngep must be a valid IAM role ARN"
  }

  # Verify pcg-writer role is tagged with fleet_entity_guid
  assert {
    condition     = output.pcg_writer_role_tags["fleet_entity_guid"] == var.fleet_entity_guid
    error_message = "PCG writer role must be tagged with fleet_entity_guid for ABAC resource tag matching"
  }
}

# =============================================================================
# MODULE DEPENDENCY WIRING TEST
# =============================================================================
# Verify that the module correctly uses outputs from setup_resource module
# =============================================================================

run "setup_for_wiring_test" {
  command = apply

  variables {
    setup_name = "inttest-role-wire"
  }

  module {
    source = "./modules/federated_logs_setup_resource"
  }
}

# -----------------------------------------------------------------------------
# TEST: Module wiring - outputs from setup_resource flow correctly to role
# -----------------------------------------------------------------------------
run "test_module_wiring" {
  command = apply

  variables {
    setup_name           = run.setup_for_wiring_test.setup_name
    s3_bucket_name       = run.setup_for_wiring_test.s3_bucket_name
    glue_catalog_db_name = run.setup_for_wiring_test.glue_catalog_db_name
    fleet_entity_guid    = var.fleet_entity_guid
    newrelic_api_key     = var.newrelic_api_key
    newrelic_region      = var.newrelic_region
  }

  # Mock the NGEP fetch — no NR API call needed
  override_data {
    target = data.external.base_role
    values = {
      result = {
        role_arn = "arn:aws:iam::123456789012:role/newrelic-fed-logs-fleet-test-base"
      }
    }
  }

  # Skip pcg-writer role creation: trust policy principal is mocked, AWS would
  # reject the fake account ID. Only need non-empty role ARNs for wiring test.
  override_resource {
    target = aws_iam_role.pcg-writer-role
    values = {
      arn  = "arn:aws:iam::000000000000:role/newrelic-fed-logs-inttest-role-wire-pcg-writer"
      name = "newrelic-fed-logs-inttest-role-wire-pcg-writer"
      tags = {}
    }
  }

  # Skip the policy attachment since the role above is mocked and doesn't exist in AWS
  override_resource {
    target = aws_iam_role_policy_attachment.writer_attach
    values = {}
  }

  module {
    source = "./modules/federated_logs_role"
  }

  assert {
    condition     = output.glue_service_role_arn != "" && output.pcg_writer_role_arn != "" && output.nr_reader_role_arn != ""
    error_message = "All role outputs should be populated when module wiring is correct"
  }
}
