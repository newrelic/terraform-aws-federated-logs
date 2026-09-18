# =============================================================================
# Tests: data_processing module
# =============================================================================
#
# What we test here:
#   1. Base role naming conventions
#   2. Base role tags (fleet_entity_guid for ABAC)
#   3. ABAC policy content (fleet_entity_guid condition key)
#   4. Input validation (clusters must have non-empty fields, correct auth_mode)
#
# All tests use command = plan to avoid triggering the NGEP null_resource
# provisioner, which makes NR API calls. No NR credentials are required to
# run these tests.
#
# =============================================================================

# Mock the external provider to avoid requiring NEW_RELIC_LICENSE_KEY/NEW_RELIC_API_KEY in CI.
# Applies to every `data "external"` instance (license_key, fleet_name); each one only
# reads the key it cares about, so having both in the shared defaults is harmless.
mock_provider "external" {
  mock_data "external" {
    defaults = {
      result = {
        license_key       = "mock-license-key-for-testing"
        fleet_entity_name = "mock-fleet-name-for-testing"
      }
    }
  }
}

# Mock AWS provider for data sources
mock_provider "aws" {
  mock_data "aws_region" {
    defaults = {
      name = "us-east-1"
      id   = "us-east-1"
    }
  }
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
      arn        = "arn:aws:iam::123456789012:root"
      user_id    = "AIDAEXAMPLE"
    }
  }
}

# Mock New Relic provider (account_id is required)
mock_provider "newrelic" {}

variables {
  test_oidc_arn       = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE"
  fleet_entity_guid   = "test-fleet-entity-guid"
  newrelic_org_id     = "test-nr-org-id"
  newrelic_account_id = 12345678
  newrelic_region     = "US"
}

# =============================================================================
# NAMING + ABAC TESTS
# =============================================================================

run "test_base_role_naming_and_abac" {
  command = plan

  variables {
    data_processing_module_name = "inttest-dp-name"
    fleet_entity_guid           = var.fleet_entity_guid
    newrelic_org_id             = var.newrelic_org_id
    newrelic_account_id         = var.newrelic_account_id
    newrelic_region             = var.newrelic_region
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

  # Verify base role naming: newrelic-fed-logs-fleet-{name}-base
  assert {
    condition     = can(regex("newrelic-fed-logs-fleet-inttest-dp-name-base", output.base_role_name))
    error_message = "Base role name should follow pattern 'newrelic-fed-logs-fleet-{data_processing_module_name}-base'"
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

  # Verify ABAC policy targets the wildcard pcg-writer resource pattern
  assert {
    condition     = can(regex("newrelic-fed-logs-\\*-pcg-writer", output.abac_policy_json))
    error_message = "ABAC policy must target newrelic-fed-logs-*-pcg-writer roles"
  }

  # Verify the Flink application exposes fleet_entity_guid as a static job-level
  # property (fleetId), so the commit worker can stamp it onto every metric
  assert {
    # property_group is a set of objects (not a list) in this provider's schema,
    # so it isn't index-addressable — pick out the FlinkApplicationProperties
    # group by its property_group_id instead.
    condition = [
      for pg in aws_kinesisanalyticsv2_application.flink_iceberg_commit_worker.application_configuration[0].environment_properties[0].property_group :
      pg.property_map["fleet.entity.guid"] if pg.property_group_id == "FlinkApplicationProperties"
    ][0] == var.fleet_entity_guid
    error_message = "Flink application must expose fleet_entity_guid as the 'fleet.entity.guid' FlinkApplicationProperties key"
  }

  # Verify the Flink application also exposes the resolved fleet display name
  # (fleetName), alongside — not instead of — fleet_entity_guid
  assert {
    condition = [
      for pg in aws_kinesisanalyticsv2_application.flink_iceberg_commit_worker.application_configuration[0].environment_properties[0].property_group :
      pg.property_map["fleet.entity.name"] if pg.property_group_id == "FlinkApplicationProperties"
    ][0] == "mock-fleet-name-for-testing"
    error_message = "Flink application must expose the resolved fleet name as the 'fleet.entity.name' FlinkApplicationProperties key"
  }
}

# =============================================================================
# INPUT VALIDATION TESTS
# =============================================================================

run "test_validation_rejects_empty_namespace" {
  command = plan

  variables {
    data_processing_module_name = "inttest-dp-val1"
    fleet_entity_guid           = var.fleet_entity_guid
    newrelic_org_id             = var.newrelic_org_id
    newrelic_account_id         = var.newrelic_account_id
    newrelic_region             = var.newrelic_region
    clusters = {
      "test-cluster" = {
        k8s_namespace            = ""
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
    newrelic_org_id             = var.newrelic_org_id
    newrelic_account_id         = var.newrelic_account_id
    newrelic_region             = var.newrelic_region
    clusters = {
      "test-cluster" = {
        k8s_namespace            = "federated-logs"
        k8s_service_account_name = ""
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
    newrelic_org_id             = var.newrelic_org_id
    newrelic_account_id         = var.newrelic_account_id
    newrelic_region             = var.newrelic_region
    clusters = {
      "test-cluster" = {
        k8s_namespace            = "federated-logs"
        k8s_service_account_name = "pcg-writer-sa"
        oidc_provider_arn        = ""
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
    newrelic_org_id             = var.newrelic_org_id
    newrelic_account_id         = var.newrelic_account_id
    newrelic_region             = var.newrelic_region
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
