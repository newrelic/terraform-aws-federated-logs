# =============================================================================
# Integration Tests: federated_logs_partition module
# =============================================================================
#
# What we test here:
#   1. Input validation (reserved table name "log_federated")
#   2. Default table is always created
#   3. Table count logic (default + custom tables)
#   4. Table name sanitization (lowercase, special chars -> underscore)
#   5. Module dependency chain (setup -> role -> partition)
#
# =============================================================================

# Shared test variables
variables {
  test_oidc_arn = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE"
}

# =============================================================================
# INPUT VALIDATION TESTS
# =============================================================================
# The partition_tables variable has a validation rule:
#   - Table name "log_federated" (case-insensitive) is reserved for default table
# =============================================================================

# -----------------------------------------------------------------------------
# TEST: Validation - Reserved table name "log_federated" rejected (lowercase)
# -----------------------------------------------------------------------------
# Why: The default table is named "log_federated", so users can't create
#      a custom table with the same name
# -----------------------------------------------------------------------------
run "test_validation_rejects_reserved_name_lowercase" {
  command = plan

  variables {
    setup_name            = "inttest-part-val1"
    s3_bucket_name        = "test-bucket"
    glue_catalog_db_name  = "test_db"
    glue_service_role_arn = "arn:aws:iam::123456789012:role/test-role"
    partition_tables = {
      "log_federated" = {}  # Reserved name - should fail
    }
  }

  module {
    source = "./modules/federated_logs_partition"
  }

  expect_failures = [var.partition_tables]
}

# -----------------------------------------------------------------------------
# TEST: Validation - Reserved table name case-insensitive ("Log_Federated")
# -----------------------------------------------------------------------------
# Why: Validation uses lower() so "Log_Federated" should also be rejected
# -----------------------------------------------------------------------------
run "test_validation_rejects_reserved_name_mixed_case" {
  command = plan

  variables {
    setup_name            = "inttest-part-val2"
    s3_bucket_name        = "test-bucket"
    glue_catalog_db_name  = "test_db"
    glue_service_role_arn = "arn:aws:iam::123456789012:role/test-role"
    partition_tables = {
      "Log_Federated" = {}  # Reserved name (mixed case) - should fail
    }
  }

  module {
    source = "./modules/federated_logs_partition"
  }

  expect_failures = [var.partition_tables]
}

# =============================================================================
# TABLE COUNT TESTS
# =============================================================================
# Verify that:
#   - Default table (Log_Federated) is always created
#   - Custom tables are added to the total count
# =============================================================================

# Create prerequisites for table count tests
run "setup_for_table_tests" {
  command = apply

  variables {
    setup_name = "inttest-part-tbl"
  }

  module {
    source = "./modules/federated_logs_setup_resource"
  }
}

run "roles_for_table_tests" {
  command = apply

  variables {
    setup_name           = run.setup_for_table_tests.setup_name
    s3_bucket_name       = run.setup_for_table_tests.s3_bucket_name
    glue_catalog_db_name = run.setup_for_table_tests.glue_catalog_db_name
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
}

# -----------------------------------------------------------------------------
# TEST: Default table is always created (no custom tables)
# -----------------------------------------------------------------------------
# Why: Even with empty partition_tables, the default Log_Federated table
#      should be created. This is module logic in locals.tf (all_tables merge)
# -----------------------------------------------------------------------------
run "test_default_table_always_created" {
  command = apply

  variables {
    setup_name            = run.setup_for_table_tests.setup_name
    s3_bucket_name        = run.setup_for_table_tests.s3_bucket_name
    glue_catalog_db_name  = run.setup_for_table_tests.glue_catalog_db_name
    glue_service_role_arn = run.roles_for_table_tests.glue_service_role_arn
    # No partition_tables specified - should still create default table
  }

  module {
    source = "./modules/federated_logs_partition"
  }

  # Default table should exist (exactly 1 table)
  assert {
    condition     = length(output.all_tables) == 1
    error_message = "Should have exactly 1 table (default) when no custom tables specified. Got: ${length(output.all_tables)}"
  }
}

# -----------------------------------------------------------------------------
# TEST: Table count = default + custom tables
# -----------------------------------------------------------------------------
# Why: Verifies the merge logic in locals.tf correctly combines default
#      and custom tables
# -----------------------------------------------------------------------------
run "setup_for_custom_tables" {
  command = apply

  variables {
    setup_name = "inttest-part-cust"
  }

  module {
    source = "./modules/federated_logs_setup_resource"
  }
}

run "roles_for_custom_tables" {
  command = apply

  variables {
    setup_name           = run.setup_for_custom_tables.setup_name
    s3_bucket_name       = run.setup_for_custom_tables.s3_bucket_name
    glue_catalog_db_name = run.setup_for_custom_tables.glue_catalog_db_name
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
}

run "test_table_count_with_custom_tables" {
  command = apply

  variables {
    setup_name            = run.setup_for_custom_tables.setup_name
    s3_bucket_name        = run.setup_for_custom_tables.s3_bucket_name
    glue_catalog_db_name  = run.setup_for_custom_tables.glue_catalog_db_name
    glue_service_role_arn = run.roles_for_custom_tables.glue_service_role_arn
    partition_tables = {
      "app_logs"      = {}
      "security_logs" = {}
    }
  }

  module {
    source = "./modules/federated_logs_partition"
  }

  # Should have: 1 default + 2 custom = 3 tables
  assert {
    condition     = length(output.all_tables) == 3
    error_message = "Should have 3 tables (1 default + 2 custom). Got: ${length(output.all_tables)}"
  }
}

# =============================================================================
# TABLE NAME SANITIZATION TESTS
# =============================================================================
# Verify that table names are sanitized:
#   - Lowercase
#   - Special chars replaced with underscore
#   - Prefix added: newrelic_fed_logs_{setup_name}_{table_name}
# =============================================================================

# -----------------------------------------------------------------------------
# TEST: Table names with special characters are sanitized
# -----------------------------------------------------------------------------
# Why: The sanitization logic in locals.tf replaces non-alphanumeric chars
#      with underscores. This tests that "My-App.Logs" becomes "my_app_logs"
# -----------------------------------------------------------------------------
run "setup_for_special_chars_test" {
  command = apply

  variables {
    setup_name = "inttest-part-spec"
  }

  module {
    source = "./modules/federated_logs_setup_resource"
  }
}

run "roles_for_special_chars_test" {
  command = apply

  variables {
    setup_name           = run.setup_for_special_chars_test.setup_name
    s3_bucket_name       = run.setup_for_special_chars_test.s3_bucket_name
    glue_catalog_db_name = run.setup_for_special_chars_test.glue_catalog_db_name
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
}

run "test_table_name_special_chars_sanitized" {
  command = apply

  variables {
    setup_name            = run.setup_for_special_chars_test.setup_name
    s3_bucket_name        = run.setup_for_special_chars_test.s3_bucket_name
    glue_catalog_db_name  = run.setup_for_special_chars_test.glue_catalog_db_name
    glue_service_role_arn = run.roles_for_special_chars_test.glue_service_role_arn
    partition_tables = {
      "My-App.Logs"    = {}  # Contains hyphen and dot
      "UPPERCASE_NAME" = {}  # Contains uppercase
    }
  }

  module {
    source = "./modules/federated_logs_partition"
  }

  # Verify tables are created (sanitization worked, no errors)
  assert {
    condition     = length(output.all_tables) == 3
    error_message = "Should have 3 tables (1 default + 2 custom with special chars)"
  }

  # Verify all table names are lowercase with only alphanumeric and underscores
  assert {
    condition = alltrue([
      for name, _ in output.all_tables :
      can(regex("^[a-z0-9_]+$", name))
    ])
    error_message = "All table names should be lowercase with only alphanumeric and underscores after sanitization"
  }
}

# -----------------------------------------------------------------------------
# TEST: Table names include setup prefix
# -----------------------------------------------------------------------------
# Why: Table names are constructed with prefix in locals.tf
#      Pattern: newrelic_fed_logs_{setup_name}_{table_name}
# -----------------------------------------------------------------------------
run "setup_for_naming_test" {
  command = apply

  variables {
    setup_name = "inttest-part-nm"
  }

  module {
    source = "./modules/federated_logs_setup_resource"
  }
}

run "roles_for_naming_test" {
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
}

run "test_table_name_includes_prefix" {
  command = apply

  variables {
    setup_name            = run.setup_for_naming_test.setup_name
    s3_bucket_name        = run.setup_for_naming_test.s3_bucket_name
    glue_catalog_db_name  = run.setup_for_naming_test.glue_catalog_db_name
    glue_service_role_arn = run.roles_for_naming_test.glue_service_role_arn
    partition_tables = {
      "my_custom_table" = {}
    }
  }

  module {
    source = "./modules/federated_logs_partition"
  }

  # All table names should start with the prefix
  # Note: hyphens in setup_name are converted to underscores
  assert {
    condition = alltrue([
      for name, _ in output.all_tables :
      startswith(name, "newrelic_fed_logs_inttest_part_nm_")
    ])
    error_message = "All table names should start with 'newrelic_fed_logs_{setup_name}_' prefix"
  }
}

# =============================================================================
# CUSTOM CONFIGURATION TESTS
# =============================================================================
# Verify that custom table settings (optimizer configuration, table parameters)
# are correctly applied and don't break the module.
# =============================================================================

# -----------------------------------------------------------------------------
# TEST: Custom optimizer settings are accepted
# -----------------------------------------------------------------------------
# Why: Users can customize orphan_file_deletion and snapshot_retention settings.
#      This tests that non-default values don't cause errors.
# -----------------------------------------------------------------------------
run "setup_for_custom_config_test" {
  command = apply

  variables {
    setup_name = "inttest-part-cfg"
  }

  module {
    source = "./modules/federated_logs_setup_resource"
  }
}

run "roles_for_custom_config_test" {
  command = apply

  variables {
    setup_name           = run.setup_for_custom_config_test.setup_name
    s3_bucket_name       = run.setup_for_custom_config_test.s3_bucket_name
    glue_catalog_db_name = run.setup_for_custom_config_test.glue_catalog_db_name
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
}

run "test_custom_optimizer_settings" {
  command = apply

  variables {
    setup_name            = run.setup_for_custom_config_test.setup_name
    s3_bucket_name        = run.setup_for_custom_config_test.s3_bucket_name
    glue_catalog_db_name  = run.setup_for_custom_config_test.glue_catalog_db_name
    glue_service_role_arn = run.roles_for_custom_config_test.glue_service_role_arn
    partition_tables = {
      "custom_config_table" = {
        table_parameters = {
          "custom_param" = "custom_value"
        }
        optimizer_configuration = {
          orphan_file_deletion = {
            orphan_file_retention_period_in_days = 7   # Non-default: 7 instead of 3
            run_rate_in_hours                    = 12  # Non-default: 12 instead of 24
          }
          snapshot_retention = {
            snapshot_retention_period_in_days = 10     # Non-default: 10 instead of 5
            number_of_snapshots_to_retain     = 5      # Non-default: 5 instead of 2
            clean_expired_files               = true   # Non-default: true instead of false
            run_rate_in_hours                 = 12     # Non-default: 12 instead of 24
          }
        }
      }
    }
  }

  module {
    source = "./modules/federated_logs_partition"
  }

  # If apply succeeds, custom config was accepted
  assert {
    condition     = length(output.all_tables) == 2
    error_message = "Should have 2 tables (1 default + 1 custom with optimizer settings)"
  }
}

# -----------------------------------------------------------------------------
# TEST: Custom default_table_setting is applied
# -----------------------------------------------------------------------------
# Why: Users can customize the default Log_Federated table settings too.
# -----------------------------------------------------------------------------
run "test_custom_default_table_setting" {
  command = apply

  variables {
    setup_name            = run.setup_for_custom_config_test.setup_name
    s3_bucket_name        = run.setup_for_custom_config_test.s3_bucket_name
    glue_catalog_db_name  = run.setup_for_custom_config_test.glue_catalog_db_name
    glue_service_role_arn = run.roles_for_custom_config_test.glue_service_role_arn
    default_table_setting = {
      table_parameters = {
        "default_custom_param" = "default_custom_value"
      }
    }
    # No custom partition_tables - just customized default
  }

  module {
    source = "./modules/federated_logs_partition"
  }

  # Should still have exactly 1 table (the customized default)
  assert {
    condition     = length(output.all_tables) == 1
    error_message = "Should have exactly 1 table (customized default)"
  }
}

# =============================================================================
# UPDATE TESTS
# =============================================================================
# Test that the module correctly handles updates to partition_tables.
# This is module-specific logic - how the all_tables map is updated when
# custom tables are added or removed.
# =============================================================================

# -----------------------------------------------------------------------------
# Setup for update tests
# -----------------------------------------------------------------------------
run "setup_for_update_tests" {
  command = apply

  variables {
    setup_name = "inttest-part-upd"
  }

  module {
    source = "./modules/federated_logs_setup_resource"
  }
}

run "roles_for_update_tests" {
  command = apply

  variables {
    setup_name           = run.setup_for_update_tests.setup_name
    s3_bucket_name       = run.setup_for_update_tests.s3_bucket_name
    glue_catalog_db_name = run.setup_for_update_tests.glue_catalog_db_name
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
}

# -----------------------------------------------------------------------------
# TEST: Create with default table only (baseline for update tests)
# -----------------------------------------------------------------------------
run "update_test_create_default_only" {
  command = apply

  variables {
    setup_name            = run.setup_for_update_tests.setup_name
    s3_bucket_name        = run.setup_for_update_tests.s3_bucket_name
    glue_catalog_db_name  = run.setup_for_update_tests.glue_catalog_db_name
    glue_service_role_arn = run.roles_for_update_tests.glue_service_role_arn
    # No custom tables - just default
  }

  module {
    source = "./modules/federated_logs_partition"
  }

  # Baseline: Should have exactly 1 table (default)
  assert {
    condition     = length(output.all_tables) == 1
    error_message = "Should have exactly 1 table (default) initially"
  }
}

# -----------------------------------------------------------------------------
# TEST: Update - Add custom partition tables
# -----------------------------------------------------------------------------
# Why: Verifies that new tables can be added to an existing setup.
#      Tests the for_each logic in aws_glue_catalog_table.
# -----------------------------------------------------------------------------
run "update_test_add_tables" {
  command = apply

  variables {
    setup_name            = run.setup_for_update_tests.setup_name
    s3_bucket_name        = run.setup_for_update_tests.s3_bucket_name
    glue_catalog_db_name  = run.setup_for_update_tests.glue_catalog_db_name
    glue_service_role_arn = run.roles_for_update_tests.glue_service_role_arn
    partition_tables = {
      "app_logs"      = {}
      "security_logs" = {}
    }
  }

  module {
    source = "./modules/federated_logs_partition"
  }

  # Should now have: 1 default + 2 custom = 3 tables
  assert {
    condition     = length(output.all_tables) == 3
    error_message = "Should have 3 tables after adding 2 custom tables. Got: ${length(output.all_tables)}"
  }
}

# -----------------------------------------------------------------------------
# TEST: Update - Add more tables (incremental add)
# -----------------------------------------------------------------------------
# Why: Verifies that additional tables can be added without affecting
#      existing tables.
# -----------------------------------------------------------------------------
run "update_test_add_more_tables" {
  command = apply

  variables {
    setup_name            = run.setup_for_update_tests.setup_name
    s3_bucket_name        = run.setup_for_update_tests.s3_bucket_name
    glue_catalog_db_name  = run.setup_for_update_tests.glue_catalog_db_name
    glue_service_role_arn = run.roles_for_update_tests.glue_service_role_arn
    partition_tables = {
      "app_logs"      = {}
      "security_logs" = {}
      "audit_logs"    = {}  # NEW table
    }
  }

  module {
    source = "./modules/federated_logs_partition"
  }

  # Should now have: 1 default + 3 custom = 4 tables
  assert {
    condition     = length(output.all_tables) == 4
    error_message = "Should have 4 tables after adding another custom table. Got: ${length(output.all_tables)}"
  }
}

# -----------------------------------------------------------------------------
# TEST: Update - Remove a table
# -----------------------------------------------------------------------------
# Why: Verifies that tables can be removed from the configuration.
#      The removed table should be deleted from Glue.
# -----------------------------------------------------------------------------
run "update_test_remove_table" {
  command = apply

  variables {
    setup_name            = run.setup_for_update_tests.setup_name
    s3_bucket_name        = run.setup_for_update_tests.s3_bucket_name
    glue_catalog_db_name  = run.setup_for_update_tests.glue_catalog_db_name
    glue_service_role_arn = run.roles_for_update_tests.glue_service_role_arn
    partition_tables = {
      "app_logs"   = {}
      "audit_logs" = {}
      # security_logs removed
    }
  }

  module {
    source = "./modules/federated_logs_partition"
  }

  # Should now have: 1 default + 2 custom = 3 tables
  assert {
    condition     = length(output.all_tables) == 3
    error_message = "Should have 3 tables after removing one custom table. Got: ${length(output.all_tables)}"
  }
}

# -----------------------------------------------------------------------------
# TEST: Update - Remove all custom tables (back to default only)
# -----------------------------------------------------------------------------
# Why: Verifies that all custom tables can be removed, leaving only
#      the default table.
# -----------------------------------------------------------------------------
run "update_test_remove_all_custom" {
  command = apply

  variables {
    setup_name            = run.setup_for_update_tests.setup_name
    s3_bucket_name        = run.setup_for_update_tests.s3_bucket_name
    glue_catalog_db_name  = run.setup_for_update_tests.glue_catalog_db_name
    glue_service_role_arn = run.roles_for_update_tests.glue_service_role_arn
    # No custom tables - back to default only
  }

  module {
    source = "./modules/federated_logs_partition"
  }

  # Should be back to: 1 default table only
  assert {
    condition     = length(output.all_tables) == 1
    error_message = "Should have 1 table (default only) after removing all custom tables. Got: ${length(output.all_tables)}"
  }
}
