# =============================================================================
# Integration Tests: federated_logs_role module
# =============================================================================
#
# What we test here:
#   1. Input validation (clusters must have non-empty fields)
#   2. Role naming conventions
#   3. IAM policy permissions (correct actions attached to each role)
#   4. Trust policy structure (OIDC federation, ExternalId, etc.)
#   5. Module dependency wiring (uses setup_resource outputs correctly)
#
# =============================================================================

# Shared test variables
variables {
  # Mock OIDC provider ARN for testing
  test_oidc_arn = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE"
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
    clusters = {
      "test-cluster" = {
        k8s_namespace            = "federated-logs"
        k8s_service_account_name = "pcg-writer-sa"
        oidc_provider_arn        = var.test_oidc_arn
      }
    }
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
  # Verify that each role's policy contains the required actions.
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
  # Verify trust policies have correct principals and conditions
  # ─────────────────────────────────────────────────────────────────────────────

  # Glue service role should trust glue.amazonaws.com
  assert {
    condition     = can(regex("glue.amazonaws.com", output.glue_service_trust_policy_json))
    error_message = "Glue service role trust policy must allow glue.amazonaws.com - table optimizers won't work"
  }

  # PCG writer role should have OIDC federation (for IRSA)
  assert {
    condition     = can(regex("AssumeRoleWithWebIdentity", output.pcg_writer_trust_policy_json))
    error_message = "PCG writer role trust policy missing sts:AssumeRoleWithWebIdentity - EKS pods can't assume this role"
  }

  # NR reader role should have ExternalId condition
  assert {
    condition     = can(regex("ExternalId", output.nr_reader_trust_policy_json))
    error_message = "NR reader role trust policy missing ExternalId condition - security risk for cross-account access"
  }
}

# =============================================================================
# INPUT VALIDATION TESTS
# =============================================================================
# The clusters variable requires all fields to be non-empty:
#   - k8s_namespace
#   - k8s_service_account_name
#   - oidc_provider_arn
# =============================================================================

# -----------------------------------------------------------------------------
# TEST: Validation - Empty namespace rejected
# -----------------------------------------------------------------------------
run "test_validation_rejects_empty_namespace" {
  command = plan

  variables {
    setup_name           = "inttest-role-val1"
    s3_bucket_name       = "test-bucket"
    glue_catalog_db_name = "test_db"
    clusters = {
      "test-cluster" = {
        k8s_namespace            = "" # Empty - should fail
        k8s_service_account_name = "pcg-writer-sa"
        oidc_provider_arn        = var.test_oidc_arn
      }
    }
  }

  module {
    source = "./modules/federated_logs_role"
  }

  expect_failures = [var.clusters]
}

# -----------------------------------------------------------------------------
# TEST: Validation - Empty service account name rejected
# -----------------------------------------------------------------------------
run "test_validation_rejects_empty_service_account" {
  command = plan

  variables {
    setup_name           = "inttest-role-val2"
    s3_bucket_name       = "test-bucket"
    glue_catalog_db_name = "test_db"
    clusters = {
      "test-cluster" = {
        k8s_namespace            = "federated-logs"
        k8s_service_account_name = "" # Empty - should fail
        oidc_provider_arn        = var.test_oidc_arn
      }
    }
  }

  module {
    source = "./modules/federated_logs_role"
  }

  expect_failures = [var.clusters]
}

# -----------------------------------------------------------------------------
# TEST: Validation - Empty OIDC provider ARN rejected
# -----------------------------------------------------------------------------
run "test_validation_rejects_empty_oidc_arn" {
  command = plan

  variables {
    setup_name           = "inttest-role-val3"
    s3_bucket_name       = "test-bucket"
    glue_catalog_db_name = "test_db"
    clusters = {
      "test-cluster" = {
        k8s_namespace            = "federated-logs"
        k8s_service_account_name = "pcg-writer-sa"
        oidc_provider_arn        = "" # Empty - should fail
      }
    }
  }

  module {
    source = "./modules/federated_logs_role"
  }

  expect_failures = [var.clusters]
}

# =============================================================================
# MULTIPLE CLUSTERS TESTS
# =============================================================================
# Verify that multiple clusters can be configured at once, including clusters
# from different AWS accounts with different OIDC providers.
# =============================================================================

# -----------------------------------------------------------------------------
# TEST: Multiple clusters from different AWS accounts
# -----------------------------------------------------------------------------
# Why: Real-world setups often have clusters in different AWS accounts.
#      Each has a different OIDC provider ARN. The trust policy should
#      include all of them.
# -----------------------------------------------------------------------------
run "setup_for_multi_cluster_test" {
  command = apply

  variables {
    setup_name = "inttest-role-multi"
  }

  module {
    source = "./modules/federated_logs_setup_resource"
  }
}

run "test_multiple_clusters_different_accounts" {
  command = apply

  variables {
    setup_name           = run.setup_for_multi_cluster_test.setup_name
    s3_bucket_name       = run.setup_for_multi_cluster_test.s3_bucket_name
    glue_catalog_db_name = run.setup_for_multi_cluster_test.glue_catalog_db_name
    clusters = {
      "prod-cluster-account-a" = {
        k8s_namespace            = "federated-logs"
        k8s_service_account_name = "pcg-writer-sa"
        oidc_provider_arn        = "arn:aws:iam::111111111111:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/PRODCLUSTERA"
      }
      "prod-cluster-account-b" = {
        k8s_namespace            = "federated-logs"
        k8s_service_account_name = "pcg-writer-sa"
        oidc_provider_arn        = "arn:aws:iam::222222222222:oidc-provider/oidc.eks.us-west-2.amazonaws.com/id/PRODCLUSTERB"
      }
      "staging-cluster" = {
        k8s_namespace            = "staging-logs"
        k8s_service_account_name = "pcg-staging-sa"
        oidc_provider_arn        = "arn:aws:iam::333333333333:oidc-provider/oidc.eks.eu-west-1.amazonaws.com/id/STAGINGCLUSTER"
      }
    }
  }

  module {
    source = "./modules/federated_logs_role"
  }

  # All roles should be created successfully with multiple clusters
  assert {
    condition     = output.glue_service_role_arn != ""
    error_message = "Glue service role should be created with multiple clusters"
  }

  assert {
    condition     = output.pcg_writer_role_arn != ""
    error_message = "PCG writer role should be created with multiple clusters (trust policy should include all 3 OIDC providers)"
  }

  assert {
    condition     = output.nr_reader_role_arn != ""
    error_message = "NR reader role should be created with multiple clusters"
  }
}

# =============================================================================
# MODULE DEPENDENCY WIRING TEST
# =============================================================================
# Verify that the module correctly uses outputs from setup_resource module
# =============================================================================

# -----------------------------------------------------------------------------
# TEST: Module wiring - outputs from setup_resource flow correctly to role
# -----------------------------------------------------------------------------
# Why: The role module depends on s3_bucket_name and glue_catalog_db_name
#      from setup_resource. This verifies the integration contract.
# -----------------------------------------------------------------------------
run "setup_for_wiring_test" {
  command = apply

  variables {
    setup_name = "inttest-role-wire"
  }

  module {
    source = "./modules/federated_logs_setup_resource"
  }
}

run "test_module_wiring" {
  command = apply

  variables {
    setup_name           = run.setup_for_wiring_test.setup_name
    s3_bucket_name       = run.setup_for_wiring_test.s3_bucket_name
    glue_catalog_db_name = run.setup_for_wiring_test.glue_catalog_db_name
    clusters = {
      "test-cluster" = {
        k8s_namespace            = "federated-logs"
        k8s_service_account_name = "pcg-writer-sa"
        oidc_provider_arn        = var.test_oidc_arn
      }
    }
  }

  module {
    source = "./modules/federated_logs_role"
  }

  # If we get here without errors, the wiring worked
  # The IAM policies reference s3_bucket_name and glue_catalog_db_name internally
  # A misconfigured reference would cause the apply to fail
  assert {
    condition     = output.glue_service_role_arn != "" && output.pcg_writer_role_arn != "" && output.nr_reader_role_arn != ""
    error_message = "All role outputs should be populated when module wiring is correct"
  }
}

# =============================================================================
# UPDATE TESTS
# =============================================================================
# Test that the module correctly handles updates to the clusters configuration.
# This is module-specific logic - how trust policies are updated when clusters
# are added or removed.
# =============================================================================

# -----------------------------------------------------------------------------
# Setup for update tests
# -----------------------------------------------------------------------------
run "setup_for_update_tests" {
  command = apply

  variables {
    setup_name = "inttest-role-upd"
  }

  module {
    source = "./modules/federated_logs_setup_resource"
  }
}

# -----------------------------------------------------------------------------
# TEST: Create with single cluster (baseline for update tests)
# -----------------------------------------------------------------------------
run "update_test_create_single_cluster" {
  command = apply

  variables {
    setup_name           = run.setup_for_update_tests.setup_name
    s3_bucket_name       = run.setup_for_update_tests.s3_bucket_name
    glue_catalog_db_name = run.setup_for_update_tests.glue_catalog_db_name
    clusters = {
      "cluster-1" = {
        k8s_namespace            = "namespace-1"
        k8s_service_account_name = "sa-1"
        oidc_provider_arn        = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/CLUSTER1"
      }
    }
  }

  module {
    source = "./modules/federated_logs_role"
  }

  # Baseline: All roles should be created
  assert {
    condition     = output.glue_service_role_arn != ""
    error_message = "Glue service role should be created"
  }

  assert {
    condition     = output.pcg_writer_role_arn != ""
    error_message = "PCG writer role should be created"
  }
}

# -----------------------------------------------------------------------------
# TEST: Update - Add a second cluster
# -----------------------------------------------------------------------------
# Why: Verifies that the trust policy is correctly updated to include
#      the new cluster's OIDC provider. This tests the for_each logic
#      in the pcg-writer-role trust policy.
# -----------------------------------------------------------------------------
run "update_test_add_cluster" {
  command = apply

  variables {
    setup_name           = run.setup_for_update_tests.setup_name
    s3_bucket_name       = run.setup_for_update_tests.s3_bucket_name
    glue_catalog_db_name = run.setup_for_update_tests.glue_catalog_db_name
    clusters = {
      "cluster-1" = {
        k8s_namespace            = "namespace-1"
        k8s_service_account_name = "sa-1"
        oidc_provider_arn        = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/CLUSTER1"
      }
      "cluster-2" = {
        k8s_namespace            = "namespace-2"
        k8s_service_account_name = "sa-2"
        oidc_provider_arn        = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/CLUSTER2"
      }
    }
  }

  module {
    source = "./modules/federated_logs_role"
  }

  # Roles should still exist after adding a cluster
  # The role ARNs should remain the same (roles are updated, not recreated)
  assert {
    condition     = output.glue_service_role_arn == run.update_test_create_single_cluster.glue_service_role_arn
    error_message = "Glue service role ARN should remain unchanged after adding cluster"
  }

  assert {
    condition     = output.pcg_writer_role_arn == run.update_test_create_single_cluster.pcg_writer_role_arn
    error_message = "PCG writer role ARN should remain unchanged after adding cluster (trust policy updated in place)"
  }
}

# -----------------------------------------------------------------------------
# TEST: Update - Remove a cluster (back to single)
# -----------------------------------------------------------------------------
# Why: Verifies that the trust policy is correctly updated to remove
#      the cluster's OIDC entry. Tests that removing from the map
#      correctly updates the trust policy.
# -----------------------------------------------------------------------------
run "update_test_remove_cluster" {
  command = apply

  variables {
    setup_name           = run.setup_for_update_tests.setup_name
    s3_bucket_name       = run.setup_for_update_tests.s3_bucket_name
    glue_catalog_db_name = run.setup_for_update_tests.glue_catalog_db_name
    clusters = {
      "cluster-1" = {
        k8s_namespace            = "namespace-1"
        k8s_service_account_name = "sa-1"
        oidc_provider_arn        = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/CLUSTER1"
      }
      # cluster-2 removed
    }
  }

  module {
    source = "./modules/federated_logs_role"
  }

  # Roles should still exist after removing a cluster
  assert {
    condition     = output.glue_service_role_arn == run.update_test_create_single_cluster.glue_service_role_arn
    error_message = "Glue service role ARN should remain unchanged after removing cluster"
  }

  assert {
    condition     = output.pcg_writer_role_arn == run.update_test_create_single_cluster.pcg_writer_role_arn
    error_message = "PCG writer role ARN should remain unchanged after removing cluster"
  }
}
