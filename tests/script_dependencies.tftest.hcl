# =============================================================================
# Tests: script_dependencies ordering variable
# =============================================================================
#
# What we test here:
#   1. A caller that passes nothing still gets every data source at plan time.
#   2. A caller that passes a dependency keeps region and account id at plan
#      time, so ordering the Python script did not defer the AWS data sources.
#
# Everything is mocked and both run blocks use command = plan, so no AWS or
# New Relic credentials are needed.
#
# =============================================================================

mock_provider "external" {
  mock_data "external" {
    defaults = {
      result = {
        role_arn                = "arn:aws:iam::123456789012:role/mock-base-role"
        base_role_connection_id = "mock-connection-guid"
        sqs_queue_arn           = "arn:aws:sqs:us-east-1:123456789012:mock-queue"
        flink_base_role_arn     = "arn:aws:iam::123456789012:role/mock-flink-base-role"
      }
    }
  }
}

mock_provider "aws" {
  mock_data "aws_region" {
    defaults = {
      name   = "us-east-1"
      id     = "us-east-1"
      region = "us-east-1"
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

mock_provider "newrelic" {}

variables {
  setup_name           = "inttest-scriptdeps"
  s3_bucket_name       = "inttest-scriptdeps-bucket"
  glue_catalog_db_name = "inttest_scriptdeps_db"
  fleet_entity_guid    = "test-fleet-entity-guid"
  newrelic_org_id      = "test-nr-org-id"
  newrelic_account_id  = 12345678
  newrelic_region      = "US"
  region               = "us-east-1"
}

# The common caller passes no script_dependencies at all. terraform_data is then
# absent, the depends_on imposes no ordering, and data.external.base_role reads at
# plan time. Drop the count on terraform_data and this run block fails, because a
# pending managed resource defers the data source to apply.
run "test_absent_script_dependencies_reads_base_role_at_plan_time" {
  command = plan

  module {
    source = "./modules/federated_logs_role"
  }

  assert {
    condition     = output.base_role_arn_from_ngep == "arn:aws:iam::123456789012:role/mock-base-role"
    error_message = "data.external.base_role was deferred past plan even though no script_dependencies were passed"
  }

  assert {
    condition     = can(regex("arn:aws:glue:us-east-1:123456789012:catalog", output.glue_service_policy_json))
    error_message = "Glue policy lost the concrete region or account id at plan time"
  }
}

# A caller that supplies a dependency gets base_role ordered behind it, which does
# defer that one data source. The AWS data sources carry no depends_on, so they must
# still read at plan time. depends_on on the module block is what breaks this.
run "test_supplied_script_dependencies_keeps_aws_data_at_plan_time" {
  command = plan

  variables {
    script_dependencies = ["install-python-deps"]
  }

  module {
    source = "./modules/federated_logs_role"
  }

  assert {
    condition     = can(regex("arn:aws:glue:us-east-1:123456789012:catalog", output.glue_service_policy_json))
    error_message = "Glue policy lost the concrete region or account id, so an AWS data source was deferred past plan"
  }

  assert {
    condition     = can(regex("arn:aws:logs:us-east-1:123456789012:log-group", output.glue_service_policy_json))
    error_message = "CloudWatch resource ARN lost the concrete region or account id at plan time"
  }
}
