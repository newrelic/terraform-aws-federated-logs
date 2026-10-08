# =============================================================================
# Plan-only tests for root-module wiring
# =============================================================================
# Every provider is mocked: these runs only inspect plan-time values of
# root-level resources, so no AWS or NR credentials are required.
# data.external.base_role (a Python script calling NR) is overridden per run.
mock_provider "aws" {
  mock_data "aws_region" {
    defaults = { region = "us-east-1", name = "us-east-1" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
}

mock_provider "newrelic" {}

variables {
  setup_name          = "inttest-root"
  fleet_entity_guid   = "test-fleet-entity-guid"
  newrelic_org_id     = "test-nr-org-id"
  newrelic_account_id = 12345678
}

# -----------------------------------------------------------------------------
# TEST: PCG writer schema-registry grant
# -----------------------------------------------------------------------------
# Object access must be scoped to the registry prefix: the code-artifacts
# bucket also holds the Glue retention script, which runs as the Glue service
# role -- write access to it would let PCG run code with that role's rights.
# -----------------------------------------------------------------------------
run "test_pcg_writer_schema_registry_grant_is_prefix_scoped" {
  command = plan

  override_data {
    target = module.role.data.external.base_role
    values = {
      result = {
        role_arn                = "arn:aws:iam::123456789012:role/mock-role"
        base_role_connection_id = "mock-connection-guid"
        sqs_queue_arn           = "arn:aws:sqs:us-east-1:123456789012:mock-queue"
        flink_base_role_arn     = "arn:aws:iam::123456789012:role/mock-flink-base-role"
      }
    }
  }

  assert {
    condition     = aws_iam_role_policy.pcg_writer_schema_registry_access.role == "newrelic-fed-logs-inttest-root-pcg-writer"
    error_message = "the grant must attach to the PCG writer role from module.role"
  }

  assert {
    condition = alltrue([
      for s in jsondecode(aws_iam_role_policy.pcg_writer_schema_registry_access.policy).Statement :
      s.Resource == "arn:aws:s3:::newrelic-fed-logs-inttest-root-code-artifacts/newrelic-fed-logs-schemas/*"
      if contains(s.Action, "s3:PutObject") || contains(s.Action, "s3:GetObject")
    ])
    error_message = "object actions must be scoped to the newrelic-fed-logs-schemas/ prefix, not the whole code-artifacts bucket"
  }

  assert {
    condition = anytrue([
      for s in jsondecode(aws_iam_role_policy.pcg_writer_schema_registry_access.policy).Statement :
      s.Resource == "arn:aws:s3:::newrelic-fed-logs-inttest-root-code-artifacts" && contains(s.Action, "s3:ListBucket")
    ])
    error_message = "ListBucket (needed for 404-on-miss and Refresh) must be granted on the bucket ARN"
  }

  # GetLifecycleConfiguration is no longer required: the gateway dropped its
  # startup lifecycle assertion, so PCG no longer needs this permission.
  assert {
    condition = alltrue([
      for s in jsondecode(aws_iam_role_policy.pcg_writer_schema_registry_access.policy).Statement :
      !contains(s.Action, "s3:GetLifecycleConfiguration")
    ])
    error_message = "s3:GetLifecycleConfiguration should not be granted -- PCG no longer checks the lifecycle rule at startup"
  }
}
