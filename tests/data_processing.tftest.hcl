# =============================================================================
# Integration Tests: data_processing module
# =============================================================================
#
# What we test here:
#   1. Input validation (clusters must have non-empty fields, correct auth_mode)
#   2. Base role naming conventions
#   3. Multiple clusters configuration
#   4. Cluster trust policy updates (add / remove cluster)
#
# Prerequisites:
#   - NR staging credentials: TF_VAR_newrelic_api_key, TF_VAR_newrelic_org_id,
#     and TF_VAR_fleet_entity_guid must be set for apply-based tests.
#   - Validation-only tests (command = plan + expect_failures) do not require
#     real NR credentials.
#
# =============================================================================

# Shared test variables
variables {
  test_oidc_arn     = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE"
  fleet_entity_guid = "YOUR_TEST_FLEET_ENTITY_GUID"
  newrelic_api_key  = "YOUR_TEST_NR_API_KEY"
  newrelic_org_id   = "YOUR_TEST_NR_ORG_ID"
  newrelic_region   = "STAGING"
}

# =============================================================================
# NAMING CONVENTION TESTS
# =============================================================================

run "test_base_role_naming" {
  command = apply

  variables {
    data_processing_module_name = "inttest-dp-name"
    fleet_entity_guid           = var.fleet_entity_guid
    newrelic_api_key            = var.newrelic_api_key
    newrelic_region             = var.newrelic_region
    newrelic_org_id             = var.newrelic_org_id
    clusters = {
      "test-cluster" = {
        k8s_namespace            = "federated-logs"
        k8s_service_account_name = "pcg-writer-sa"
        oidc_provider_arn        = var.test_oidc_arn
      }
    }
  }

  module {
    source = "./modules/data_processing"
  }

  assert {
    condition     = can(regex("newrelic-fed-logs-fleet-inttest-dp-name-base", output.base_role_name))
    error_message = "Base role name should follow pattern 'newrelic-fed-logs-fleet-{data_processing_module_name}-base'"
  }

  assert {
    condition     = can(regex("newrelic-fed-logs-fleet-inttest-dp-name-base", output.base_role_arn))
    error_message = "Base role ARN should contain the expected role name"
  }

  # Verify base role is tagged with fleet_entity_guid (required for ABAC session tag forwarding)
  assert {
    condition     = output.base_role_tags["fleet_entity_guid"] == var.fleet_entity_guid
    error_message = "Base role must be tagged with fleet_entity_guid for ABAC to work"
  }

  # Verify ABAC policy uses fleet_entity_guid as the condition key
  assert {
    condition     = can(regex("fleet_entity_guid", output.abac_policy_json))
    error_message = "ABAC policy must use fleet_entity_guid as the condition key"
  }

  # Verify ABAC policy uses the wildcard pcg-writer resource pattern
  assert {
    condition     = can(regex("newrelic-fed-logs-\\*-pcg-writer", output.abac_policy_json))
    error_message = "ABAC policy must target newrelic-fed-logs-*-pcg-writer roles"
  }
}

# =============================================================================
# INPUT VALIDATION TESTS
# =============================================================================
# The clusters variable requires all fields to be non-empty:
#   - k8s_namespace
#   - k8s_service_account_name
#   - oidc_provider_arn (when auth_mode = "irsa")
#   - cluster_name (when auth_mode = "pod_identity")
# =============================================================================

run "test_validation_rejects_empty_namespace" {
  command = plan

  variables {
    data_processing_module_name = "inttest-dp-val1"
    fleet_entity_guid           = var.fleet_entity_guid
    newrelic_api_key            = var.newrelic_api_key
    newrelic_region             = var.newrelic_region
    newrelic_org_id             = var.newrelic_org_id
    clusters = {
      "test-cluster" = {
        k8s_namespace            = "" # Empty - should fail
        k8s_service_account_name = "pcg-writer-sa"
        oidc_provider_arn        = var.test_oidc_arn
      }
    }
  }

  module {
    source = "./modules/data_processing"
  }

  expect_failures = [var.clusters]
}

run "test_validation_rejects_empty_service_account" {
  command = plan

  variables {
    data_processing_module_name = "inttest-dp-val2"
    fleet_entity_guid           = var.fleet_entity_guid
    newrelic_api_key            = var.newrelic_api_key
    newrelic_region             = var.newrelic_region
    newrelic_org_id             = var.newrelic_org_id
    clusters = {
      "test-cluster" = {
        k8s_namespace            = "federated-logs"
        k8s_service_account_name = "" # Empty - should fail
        oidc_provider_arn        = var.test_oidc_arn
      }
    }
  }

  module {
    source = "./modules/data_processing"
  }

  expect_failures = [var.clusters]
}

run "test_validation_rejects_empty_oidc_arn" {
  command = plan

  variables {
    data_processing_module_name = "inttest-dp-val3"
    fleet_entity_guid           = var.fleet_entity_guid
    newrelic_api_key            = var.newrelic_api_key
    newrelic_region             = var.newrelic_region
    newrelic_org_id             = var.newrelic_org_id
    clusters = {
      "test-cluster" = {
        k8s_namespace            = "federated-logs"
        k8s_service_account_name = "pcg-writer-sa"
        oidc_provider_arn        = "" # Empty - should fail
      }
    }
  }

  module {
    source = "./modules/data_processing"
  }

  expect_failures = [var.clusters]
}

run "test_validation_rejects_mixed_auth_modes" {
  command = plan

  variables {
    data_processing_module_name = "inttest-dp-val4"
    fleet_entity_guid           = var.fleet_entity_guid
    newrelic_api_key            = var.newrelic_api_key
    newrelic_region             = var.newrelic_region
    newrelic_org_id             = var.newrelic_org_id
    clusters = {
      "irsa-cluster" = {
        k8s_namespace            = "federated-logs"
        k8s_service_account_name = "pcg-writer-sa"
        auth_mode                = "irsa"
        oidc_provider_arn        = var.test_oidc_arn
      }
      "pod-identity-cluster" = {
        k8s_namespace            = "federated-logs"
        k8s_service_account_name = "pcg-writer-sa"
        auth_mode                = "pod_identity"
        cluster_name             = "my-cluster"
      }
    }
  }

  module {
    source = "./modules/data_processing"
  }

  expect_failures = [var.clusters]
}

# =============================================================================
# MULTIPLE CLUSTERS TESTS
# =============================================================================

run "setup_for_multi_cluster_test" {
  command = apply

  variables {
    data_processing_module_name = "inttest-dp-multi"
    fleet_entity_guid           = var.fleet_entity_guid
    newrelic_api_key            = var.newrelic_api_key
    newrelic_region             = var.newrelic_region
    newrelic_org_id             = var.newrelic_org_id
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
    source = "./modules/data_processing"
  }

  assert {
    condition     = output.base_role_arn != ""
    error_message = "Base role should be created with multiple clusters"
  }
}

# =============================================================================
# UPDATE TESTS
# =============================================================================
# Test that the module correctly handles updates to the clusters configuration.
# =============================================================================

run "update_test_create_single_cluster" {
  command = apply

  variables {
    data_processing_module_name = "inttest-dp-upd"
    fleet_entity_guid           = var.fleet_entity_guid
    newrelic_api_key            = var.newrelic_api_key
    newrelic_region             = var.newrelic_region
    newrelic_org_id             = var.newrelic_org_id
    clusters = {
      "cluster-1" = {
        k8s_namespace            = "namespace-1"
        k8s_service_account_name = "sa-1"
        oidc_provider_arn        = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/CLUSTER1"
      }
    }
  }

  module {
    source = "./modules/data_processing"
  }

  assert {
    condition     = output.base_role_arn != ""
    error_message = "Base role should be created"
  }
}

run "update_test_add_cluster" {
  command = apply

  variables {
    data_processing_module_name = "inttest-dp-upd"
    fleet_entity_guid           = var.fleet_entity_guid
    newrelic_api_key            = var.newrelic_api_key
    newrelic_region             = var.newrelic_region
    newrelic_org_id             = var.newrelic_org_id
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
    source = "./modules/data_processing"
  }

  # Role ARN should remain the same — role is updated in place, not recreated
  assert {
    condition     = output.base_role_arn == run.update_test_create_single_cluster.base_role_arn
    error_message = "Base role ARN should remain unchanged after adding a cluster"
  }
}

run "update_test_remove_cluster" {
  command = apply

  variables {
    data_processing_module_name = "inttest-dp-upd"
    fleet_entity_guid           = var.fleet_entity_guid
    newrelic_api_key            = var.newrelic_api_key
    newrelic_region             = var.newrelic_region
    newrelic_org_id             = var.newrelic_org_id
    clusters = {
      "cluster-1" = {
        k8s_namespace            = "namespace-1"
        k8s_service_account_name = "sa-1"
        oidc_provider_arn        = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/CLUSTER1"
        # cluster-2 removed
      }
    }
  }

  module {
    source = "./modules/data_processing"
  }

  assert {
    condition     = output.base_role_arn == run.update_test_create_single_cluster.base_role_arn
    error_message = "Base role ARN should remain unchanged after removing a cluster"
  }
}
