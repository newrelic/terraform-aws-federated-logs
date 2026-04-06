# =============================================================================
# 1. Base IAM Role — OIDC-federated identity for PCG pods
#
# The K8s ServiceAccount is annotated with this role's ARN.  On pod start EKS
# injects an OIDC web-identity token; the AWS SDK exchanges it for temporary
# credentials tied to this role.
#
# Tagged with PCG_Instance = var.name.  An ABAC wildcard policy allows this
# role to assume any target setup role whose PCG_Instance tag matches.
# =============================================================================

resource "aws_iam_role" "base_role" {
  name                 = "${local.naming_prefix}-base"
  description          = "Base IRSA role for PCG data processing — can only assume target setup roles."
  permissions_boundary = ""

  tags = {
    PCG_Instance = var.name
  }

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      for key, config in var.clusters : {
        Effect = "Allow"
        Action = "sts:AssumeRoleWithWebIdentity"
        Principal = {
          Federated = config.oidc_provider_arn
        }
        Condition = {
          StringEquals = {
            "${replace(config.oidc_provider_arn, "/^arn:aws:iam::.*:oidc-provider//", "")}:sub" = "system:serviceaccount:${config.k8s_namespace}:${config.k8s_service_account_name}"
            "${replace(config.oidc_provider_arn, "/^arn:aws:iam::.*:oidc-provider//", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}

# ABAC policy — one wildcard rule covers all current and future setup roles.
# Only roles tagged with a matching PCG_Instance value can be assumed.
resource "aws_iam_role_policy" "abac_assume_setup_roles" {
  name = "${local.naming_prefix}-assume-setup-roles"
  role = aws_iam_role.base_role.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AssumeMatchingSetupRoles"
        Effect   = "Allow"
        Action   = "sts:AssumeRole"
        Resource = "arn:aws:iam::*:role/newrelic-fed-logs-*-pcg-writer"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/PCG_Instance" = "$${aws:PrincipalTag/PCG_Instance}"
          }
        }
      }
    ]
  })
}

# =============================================================================
# 2. Cluster Grouping — fleet-level abstraction
#
# Captures the set of compute clusters that share this base role.
# Each cluster entry is tracked for lifecycle mgmt and can be referenced
# by the NGEP entity registration.
# =============================================================================

resource "terraform_data" "cluster_membership" {
  for_each = var.clusters

  input = {
    cluster_key              = each.key
    k8s_namespace            = each.value.k8s_namespace
    k8s_service_account_name = each.value.k8s_service_account_name
    oidc_provider_arn        = each.value.oidc_provider_arn
    fleet_id                 = local.fleet_id
    base_role_arn            = aws_iam_role.base_role.arn
  }
}

# =============================================================================
# 3. NGEP Data Processing Entity — registers base role + fleet with New Relic
#
# Create provisioner → calls NerdGraph, writes entity ID to a state file.
# Destroy provisioner → reads entity ID from that file, calls delete mutation.
#
# The state file (.entity_state.json) lives next to the module and is
# gitignored. It allows the destroy provisioner to know the entity ID without
# needing variable references (which aren't available in destroy context).
# =============================================================================

resource "terraform_data" "ngep_entity" {
  # Include values the destroy provisioner will need via self.input
  input = {
    base_role_arn   = aws_iam_role.base_role.arn
    fleet_id        = local.fleet_id
    auth_mode       = var.auth_mode
    nr_account_id   = tostring(var.newrelic_account_id)
    nr_endpoint     = local.nr_endpoint
    state_file      = "${path.module}/.entity_state.json"
  }

  provisioner "local-exec" {
    command = "bash ${path.module}/scripts/register_entity.sh"
    environment = {
      NR_ACCOUNT_ID   = tostring(var.newrelic_account_id)
      NR_USER_API_KEY = var.newrelic_user_api_key
      NR_ENDPOINT     = local.nr_endpoint
      BASE_ROLE_ARN   = aws_iam_role.base_role.arn
      FLEET_ID        = local.fleet_id
      AUTH_MODE       = var.auth_mode
      STATE_FILE      = "${path.module}/.entity_state.json"
    }
  }

  provisioner "local-exec" {
    when       = destroy
    command    = "bash ${self.input.state_file}/../scripts/deregister_entity.sh"
    environment = {
      NR_ACCOUNT_ID   = self.input.nr_account_id
      NR_ENDPOINT     = self.input.nr_endpoint
      STATE_FILE      = self.input.state_file
    }
    on_failure = continue
  }
}
