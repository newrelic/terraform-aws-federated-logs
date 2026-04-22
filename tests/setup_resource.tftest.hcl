# =============================================================================
# Integration Tests: federated_logs_setup_resource module
# =============================================================================
#
# What we test here:
#   1. Input validation rules (setup_name regex)
#   2. Naming conventions (S3 bucket and Glue DB naming patterns)


# -----------------------------------------------------------------------------
# TEST: Naming Convention - S3 Bucket
# -----------------------------------------------------------------------------
# Verifies: S3 bucket follows pattern "newrelic-fed-logs-{setup_name}"
# Why: This is module-specific logic defined in locals.tf
# -----------------------------------------------------------------------------
run "test_s3_bucket_naming_convention" {
  command = apply

  variables {
    setup_name = "inttest-naming-01"
  }

  module {
    source = "./modules/federated_logs_setup_resource"
  }

  # Verify exact S3 bucket name matches our naming convention
  assert {
    condition     = output.s3_bucket_name == "newrelic-fed-logs-inttest-naming-01"
    error_message = "S3 bucket name should be 'newrelic-fed-logs-{setup_name}'. Got: ${output.s3_bucket_name}"
  }
}

# -----------------------------------------------------------------------------
# TEST: Naming Convention - Glue Database (hyphen to underscore transformation)
# -----------------------------------------------------------------------------
# Verifies: Glue DB name is "newrelic_fed_logs_{setup_name}" with hyphens
#           converted to underscores (Glue doesn't allow hyphens)
# Why: This transformation logic is in main.tf: replace(local.setup_naming_prefix, "-", "_")
# -----------------------------------------------------------------------------
run "test_glue_db_naming_convention" {
  command = apply

  variables {
    setup_name = "inttest-naming-02"
  }

  module {
    source = "./modules/federated_logs_setup_resource"
  }

  # Verify hyphens are converted to underscores for Glue
  assert {
    condition     = output.glue_catalog_db_name == "newrelic_fed_logs_inttest_naming_02"
    error_message = "Glue DB name should have hyphens converted to underscores. Got: ${output.glue_catalog_db_name}"
  }
}

# -----------------------------------------------------------------------------
# TEST: setup_name output passthrough
# -----------------------------------------------------------------------------
# Verifies: setup_name output matches input (used by downstream modules)
# Why: Other modules depend on this output for their naming
# -----------------------------------------------------------------------------
run "test_setup_name_output" {
  command = apply

  variables {
    setup_name = "inttest-output-01"
  }

  module {
    source = "./modules/federated_logs_setup_resource"
  }

  assert {
    condition     = output.setup_name == "inttest-output-01"
    error_message = "setup_name output should match input variable"
  }
}

# =============================================================================
# INPUT VALIDATION TESTS
# =============================================================================
# These tests verify that the regex validation in variables.tf works correctly.
# Regex: ^[a-z0-9][a-z0-9-]{1,24}[a-z0-9]$
# Rules:
#   - Lowercase alphanumeric only (no uppercase)
#   - Can contain hyphens, but not at start or end
#   - Length: 3-26 characters
# =============================================================================

# -----------------------------------------------------------------------------
# TEST: Validation - Uppercase letters rejected
# -----------------------------------------------------------------------------
run "test_validation_rejects_uppercase" {
  command = plan

  variables {
    setup_name = "InvalidName"
  }

  module {
    source = "./modules/federated_logs_setup_resource"
  }

  expect_failures = [var.setup_name]
}

# -----------------------------------------------------------------------------
# TEST: Validation - Leading hyphen rejected
# -----------------------------------------------------------------------------
run "test_validation_rejects_leading_hyphen" {
  command = plan

  variables {
    setup_name = "-invalid-name"
  }

  module {
    source = "./modules/federated_logs_setup_resource"
  }

  expect_failures = [var.setup_name]
}

# -----------------------------------------------------------------------------
# TEST: Validation - Trailing hyphen rejected
# -----------------------------------------------------------------------------
run "test_validation_rejects_trailing_hyphen" {
  command = plan

  variables {
    setup_name = "invalid-name-"
  }

  module {
    source = "./modules/federated_logs_setup_resource"
  }

  expect_failures = [var.setup_name]
}

# -----------------------------------------------------------------------------
# TEST: Validation - Special characters rejected
# -----------------------------------------------------------------------------
run "test_validation_rejects_special_chars" {
  command = plan

  variables {
    setup_name = "invalid_name!"
  }

  module {
    source = "./modules/federated_logs_setup_resource"
  }

  expect_failures = [var.setup_name]
}

# -----------------------------------------------------------------------------
# TEST: Validation - Name too short (< 3 chars)
# -----------------------------------------------------------------------------
run "test_validation_rejects_too_short" {
  command = plan

  variables {
    setup_name = "ab"
  }

  module {
    source = "./modules/federated_logs_setup_resource"
  }

  expect_failures = [var.setup_name]
}

# -----------------------------------------------------------------------------
# TEST: Validation - Name too long (> 26 chars)
# -----------------------------------------------------------------------------
run "test_validation_rejects_too_long" {
  command = plan

  variables {
    setup_name = "this-name-is-very-much-long-for-validation"
  }

  module {
    source = "./modules/federated_logs_setup_resource"
  }

  expect_failures = [var.setup_name]
}

# -----------------------------------------------------------------------------
# TEST: Validation - Minimum valid length (3 chars)
# -----------------------------------------------------------------------------
run "test_validation_accepts_min_length" {
  command = plan

  variables {
    setup_name = "abc"
  }

  module {
    source = "./modules/federated_logs_setup_resource"
  }

  # No expect_failures = plan should succeed
}

# -----------------------------------------------------------------------------
# TEST: Validation - Hyphens in middle are allowed
# -----------------------------------------------------------------------------
run "test_validation_accepts_middle_hyphens" {
  command = plan

  variables {
    setup_name = "valid-name-here"
  }

  module {
    source = "./modules/federated_logs_setup_resource"
  }

  # No expect_failures = plan should succeed
}
