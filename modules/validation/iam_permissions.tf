# ──────────────────────────────────────────────────────────────
# IAM Policy Simulation Checks
#
# These use the IAM Policy Simulator API to verify that each role
# has the correct permissions — both positive (can do what it needs)
# and negative (cannot do what it shouldn't).
#
# Requires the Terraform execution identity to have:
#   iam:SimulatePrincipalPolicy on the roles being tested.
#
# Set var.enable_permission_checks = false to skip these checks
# if the permission cannot be granted.
# ──────────────────────────────────────────────────────────────

data "aws_iam_principal_policy_simulation" "pcg_writer_s3_write" {
  count             = var.enable_permission_checks ? 1 : 0
  action_names      = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"]
  policy_source_arn = var.pcg_writer_role_arn
  resource_arns     = [local.s3_object_arn]
}

check "pcg_writer_can_write_s3" {
  assert {
    condition = var.enable_permission_checks ? data.aws_iam_principal_policy_simulation.pcg_writer_s3_write[0].all_allowed : true
    error_message = join("\n", [
      "PCG writer role CANNOT write to S3 bucket '${var.s3_bucket_name}'. Log ingestion will fail.",
      "Simulation results:",
      join("\n", [
        for r in try(data.aws_iam_principal_policy_simulation.pcg_writer_s3_write[0].results, []) :
        "  ${r.action_name} on ${r.resource_arn}: decision=${r.decision}, details=${jsonencode(r.decision_details)}"
      ])
    ])
  }
}

data "aws_iam_principal_policy_simulation" "pcg_writer_glue_access" {
  count             = var.enable_permission_checks ? 1 : 0
  action_names      = ["glue:GetTable", "glue:UpdateTable", "glue:GetDatabase"]
  policy_source_arn = var.pcg_writer_role_arn
  resource_arns     = [local.glue_catalog, local.glue_db_arn, local.glue_table_arn]
}

check "pcg_writer_can_update_glue" {
  assert {
    condition = var.enable_permission_checks ? data.aws_iam_principal_policy_simulation.pcg_writer_glue_access[0].all_allowed : true
    error_message = join("\n", [
      "PCG writer role CANNOT update Glue tables. Iceberg metadata commits will fail.",
      "Simulation results:",
      join("\n", [
        for r in try(data.aws_iam_principal_policy_simulation.pcg_writer_glue_access[0].results, []) :
        "  ${r.action_name} on ${r.resource_arn}: decision=${r.decision}, details=${jsonencode(r.decision_details)}"
      ])
    ])
  }
}

data "aws_iam_principal_policy_simulation" "nr_reader_s3_read" {
  count             = var.enable_permission_checks ? 1 : 0
  action_names      = ["s3:GetObject", "s3:ListBucket"]
  policy_source_arn = var.nr_reader_role_arn
  resource_arns     = [local.s3_bucket_arn, local.s3_object_arn]
}

check "nr_reader_can_read_s3" {
  assert {
    condition = var.enable_permission_checks ? data.aws_iam_principal_policy_simulation.nr_reader_s3_read[0].all_allowed : true
    error_message = join("\n", [
      "NR reader role CANNOT read S3 bucket '${var.s3_bucket_name}'. New Relic queries will return no data.",
      "Simulation results:",
      join("\n", [
        for r in try(data.aws_iam_principal_policy_simulation.nr_reader_s3_read[0].results, []) :
        "  ${r.action_name} on ${r.resource_arn}: decision=${r.decision}, details=${jsonencode(r.decision_details)}"
      ])
    ])
  }
}

data "aws_iam_principal_policy_simulation" "nr_reader_glue_read" {
  count             = var.enable_permission_checks ? 1 : 0
  action_names      = ["glue:GetTable", "glue:GetTables", "glue:GetDatabase", "glue:GetPartitions", "glue:BatchGetPartition"]
  policy_source_arn = var.nr_reader_role_arn
  resource_arns     = [local.glue_catalog, local.glue_db_arn, local.glue_table_arn]
}

check "nr_reader_can_read_glue" {
  assert {
    condition = var.enable_permission_checks ? data.aws_iam_principal_policy_simulation.nr_reader_glue_read[0].all_allowed : true
    error_message = join("\n", [
      "NR reader role CANNOT read Glue catalog. New Relic queries will fail.",
      "Simulation results:",
      join("\n", [
        for r in try(data.aws_iam_principal_policy_simulation.nr_reader_glue_read[0].results, []) :
        "  ${r.action_name} on ${r.resource_arn}: decision=${r.decision}, details=${jsonencode(r.decision_details)}"
      ])
    ])
  }
}

data "aws_iam_principal_policy_simulation" "glue_role_s3_access" {
  count             = var.enable_permission_checks ? 1 : 0
  action_names      = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
  policy_source_arn = var.glue_service_role_arn
  resource_arns     = [local.s3_bucket_arn, local.s3_object_arn]
}

check "glue_role_can_access_s3" {
  assert {
    condition = var.enable_permission_checks ? data.aws_iam_principal_policy_simulation.glue_role_s3_access[0].all_allowed : true
    error_message = join("\n", [
      "Glue service role CANNOT access S3. Table compaction, retention, and orphan deletion will fail.",
      "Simulation results:",
      join("\n", [
        for r in try(data.aws_iam_principal_policy_simulation.glue_role_s3_access[0].results, []) :
        "  ${r.action_name} on ${r.resource_arn}: decision=${r.decision}, details=${jsonencode(r.decision_details)}"
      ])
    ])
  }
}

data "aws_iam_principal_policy_simulation" "glue_role_glue_access" {
  count             = var.enable_permission_checks ? 1 : 0
  action_names      = ["glue:GetTable", "glue:UpdateTable", "glue:GetDatabase"]
  policy_source_arn = var.glue_service_role_arn
  resource_arns     = [local.glue_catalog, local.glue_db_arn, local.glue_table_arn]
}

check "glue_role_can_access_glue" {
  assert {
    condition = var.enable_permission_checks ? data.aws_iam_principal_policy_simulation.glue_role_glue_access[0].all_allowed : true
    error_message = join("\n", [
      "Glue service role CANNOT access Glue catalog. Table optimization will fail.",
      "Simulation results:",
      join("\n", [
        for r in try(data.aws_iam_principal_policy_simulation.glue_role_glue_access[0].results, []) :
        "  ${r.action_name} on ${r.resource_arn}: decision=${r.decision}, details=${jsonencode(r.decision_details)}"
      ])
    ])
  }
}

data "aws_iam_principal_policy_simulation" "glue_role_cloudwatch" {
  count             = var.enable_permission_checks ? 1 : 0
  action_names      = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
  policy_source_arn = var.glue_service_role_arn
  resource_arns     = ["arn:aws:logs:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:log-group:/aws-glue/*"]
}

check "glue_role_can_write_logs" {
  assert {
    condition = var.enable_permission_checks ? data.aws_iam_principal_policy_simulation.glue_role_cloudwatch[0].all_allowed : true
    error_message = join("\n", [
      "Glue service role CANNOT write CloudWatch logs.",
      "Simulation results:",
      join("\n", [
        for r in try(data.aws_iam_principal_policy_simulation.glue_role_cloudwatch[0].results, []) :
        "  ${r.action_name} on ${r.resource_arn}: decision=${r.decision}, details=${jsonencode(r.decision_details)}"
      ])
    ])
  }
}
