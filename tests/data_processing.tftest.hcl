# =============================================================================
# Tests: data_processing module
# =============================================================================
#
# What we test here:
#   1. Base role naming conventions
#   2. Base role tags (fleet_entity_guid for ABAC)
#   3. ABAC policy content (fleet_entity_guid condition key)
#   4. Input validation (clusters must have non-empty fields, correct auth_mode)
#   5. Flink JAR upload trigger (source_hash: pinned sha256, else the unquoted source ETag)
#   6. Flink JAR version pin (variable default matches flink-jar-versions.json; "latest" warns)
#
# All tests use command = plan to avoid triggering the NGEP null_resource
# provisioner, which makes NR API calls. No NR credentials are required to
# run these tests.
#
# =============================================================================

# Mock the external provider to avoid requiring NEW_RELIC_LICENSE_KEY/NEW_RELIC_API_KEY in CI.
# Applies to the license_key `data "external"` instance.
mock_provider "external" {
  mock_data "external" {
    defaults = {
      result = {
        license_key = "mock-license-key-for-testing"
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
    fleet_name                  = "test-fleet-name"
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

  # Verify the Flink application also exposes the fleet display name (fleetName),
  # alongside — not instead of — fleet_entity_guid
  assert {
    condition = [
      for pg in aws_kinesisanalyticsv2_application.flink_iceberg_commit_worker.application_configuration[0].environment_properties[0].property_group :
      pg.property_map["fleet.entity.name"] if pg.property_group_id == "FlinkApplicationProperties"
    ][0] == "test-fleet-name"
    error_message = "Flink application must expose fleet_name as the 'fleet.entity.name' FlinkApplicationProperties key"
  }

  # Commit batching defaults when the caller doesn't set them
  assert {
    condition = [
      for pg in aws_kinesisanalyticsv2_application.flink_iceberg_commit_worker.application_configuration[0].environment_properties[0].property_group :
      [pg.property_map["iceberg.commit.batch.size"], pg.property_map["iceberg.commit.batch.timeout.ms"]] if pg.property_group_id == "FlinkApplicationProperties"
    ][0] == ["100", "10000"]
    error_message = "Commit batching must default to 100 files / 10000 ms"
  }
}

run "test_commit_batch_overrides" {
  command = plan

  variables {
    data_processing_module_name = "inttest-dp-commit-batch"
    fleet_entity_guid           = var.fleet_entity_guid
    newrelic_org_id             = var.newrelic_org_id
    newrelic_account_id         = var.newrelic_account_id
    newrelic_region             = var.newrelic_region
    commit_batch_size           = 500
    commit_batch_timeout_ms     = 60000
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
    condition = [
      for pg in aws_kinesisanalyticsv2_application.flink_iceberg_commit_worker.application_configuration[0].environment_properties[0].property_group :
      [pg.property_map["iceberg.commit.batch.size"], pg.property_map["iceberg.commit.batch.timeout.ms"]] if pg.property_group_id == "FlinkApplicationProperties"
    ][0] == ["500", "60000"]
    error_message = "commit_batch_size / commit_batch_timeout_ms must flow into the iceberg.commit.batch.* Flink properties"
  }
}

run "test_validation_rejects_zero_commit_batch_timeout" {
  command = plan

  variables {
    data_processing_module_name = "inttest-dp-bad-timeout"
    fleet_entity_guid           = var.fleet_entity_guid
    newrelic_org_id             = var.newrelic_org_id
    newrelic_account_id         = var.newrelic_account_id
    newrelic_region             = var.newrelic_region
    commit_batch_timeout_ms     = 0
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

  expect_failures = [var.commit_batch_timeout_ms]
}

run "test_fleet_name_omitted_when_empty" {
  command = plan

  variables {
    data_processing_module_name = "inttest-dp-no-fleet-name"
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

  # fleet_name defaults to "" — the "fleet.entity.name" key must be omitted
  # entirely rather than set to an empty string, since AWS Managed Flink's
  # property map rejects empty-string values outright.
  assert {
    condition = ![
      for pg in aws_kinesisanalyticsv2_application.flink_iceberg_commit_worker.application_configuration[0].environment_properties[0].property_group :
      contains(keys(pg.property_map), "fleet.entity.name") if pg.property_group_id == "FlinkApplicationProperties"
    ][0]
    error_message = "fleet.entity.name must be omitted from FlinkApplicationProperties when fleet_name is unset"
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

# =============================================================================
# FLINK JAR VERSION PIN AND UPLOAD TRIGGER
# =============================================================================

# With no override, the module deploys the version its variable default pins, so the
# JAR changes only when the customer upgrades the module.
run "test_flink_jar_defaults_to_pinned_version" {
  command = plan

  variables {
    data_processing_module_name = "inttest-dp-pin"
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

  override_data {
    target = data.http.flink_jar_metadata
    values = {
      status_code      = 200
      response_headers = { Etag = "\"bc5db85d65e8fb112d9830d64001e823-10\"" }
    }
  }

  assert {
    condition     = aws_s3_object.flink_jar.key == "flink/flink-iceberg-commit-worker-${output.flink_iceberg_commit_worker_version}.jar"
    error_message = "The JAR key must carry the concrete version, never latest"
  }

  # A JAR bump changes the variable default and flink-jar-versions.json together;
  # this fails if only one of them was changed.
  assert {
    condition = (
      length(jsondecode(file("modules/data_processing/flink-jar-versions.json")).sha256) == 1 &&
      contains(keys(jsondecode(file("modules/data_processing/flink-jar-versions.json")).sha256), output.flink_iceberg_commit_worker_version)
    )
    error_message = "flink-jar-versions.json must hold exactly one sha256, for the default flink_iceberg_commit_worker_version; bump both together"
  }

  # A pinned version re-uploads only when its sha256 changes, independent of the ETag.
  assert {
    condition     = aws_s3_object.flink_jar.source_hash == jsondecode(file("modules/data_processing/flink-jar-versions.json")).sha256[output.flink_iceberg_commit_worker_version]
    error_message = "For a pinned version, source_hash must be its sha256"
  }
}

# "latest" still works but has no checksum, so the flink_jar_version_pinned check warns.
# With no sha256, source_hash falls back to the source ETag, which arrives quoted; it
# must strip the quotes so it is stable across applies, or every apply would
# re-upload the 83 MB JAR.
run "test_flink_jar_latest_override_warns" {
  command = plan

  variables {
    data_processing_module_name         = "inttest-dp-latest"
    fleet_entity_guid                   = var.fleet_entity_guid
    newrelic_org_id                     = var.newrelic_org_id
    newrelic_account_id                 = var.newrelic_account_id
    newrelic_region                     = var.newrelic_region
    flink_iceberg_commit_worker_version = "latest"
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

  override_data {
    target = data.http.flink_jar_metadata
    values = {
      status_code      = 200
      response_headers = { Etag = "\"bc5db85d65e8fb112d9830d64001e823-10\"" }
    }
  }

  expect_failures = [check.flink_jar_version_pinned]

  assert {
    condition     = aws_s3_object.flink_jar.key == "flink/flink-iceberg-commit-worker-latest.jar"
    error_message = "An explicit override must still be honoured"
  }

  assert {
    condition     = aws_s3_object.flink_jar.source_hash == "bc5db85d65e8fb112d9830d64001e823-10"
    error_message = "source_hash must be the source ETag without its surrounding quotes"
  }
}
