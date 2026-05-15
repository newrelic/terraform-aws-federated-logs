# ── Base Role ────────────────────────────────────────────────────────────────
# Fleet-level IAM role authenticated via OIDC (IRSA) or Pod Identity.
# Has NO direct S3/Glue permissions — it can only assume per-setup pcg-writer
# roles via the ABAC inline policy below.

resource "aws_iam_role" "base_role" {
  name        = "${local.naming_prefix}-base"
  description = "Fleet-level base role for PCG. Authenticates via EKS and assumes per-setup writer roles via ABAC."

  assume_role_policy = local.auth_mode == "irsa" ? jsonencode({
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
    }) : jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "pods.eks.amazonaws.com"
        }
        Action = ["sts:AssumeRole", "sts:TagSession"]
        Condition = {
          StringEquals = {
            "aws:RequestTag/kubernetes-namespace" = [for c in var.clusters : c.k8s_namespace]
          }
        }
      }
    ]
  })

  tags = {
    fleet_entity_guid = var.fleet_entity_guid
  }
}

# ABAC wildcard policy: allows assuming any pcg-writer role in any account
# where the role's fleet_entity_guid tag matches this base role's fleet_entity_guid tag.
resource "aws_iam_role_policy" "abac_assume_policy" {
  name = "${local.naming_prefix}-abac-assume"
  role = aws_iam_role.base_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["sts:AssumeRole", "sts:TagSession"]
        Resource = "arn:aws:iam::*:role/newrelic-fed-logs-*-pcg-writer"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/fleet_entity_guid" = "$${aws:PrincipalTag/fleet_entity_guid}"
          }
        }
      }
    ]
  })
}

# Pod Identity: bind base role to each cluster's service account
resource "aws_eks_pod_identity_association" "base_role" {
  for_each = { for k, v in var.clusters : k => v if local.auth_mode == "pod_identity" }

  cluster_name    = each.value.cluster_name
  namespace       = each.value.k8s_namespace
  service_account = each.value.k8s_service_account_name
  role_arn        = aws_iam_role.base_role.arn
}

# ── NGEP: AWS Connection Entity + Relationship ────────────────────────────────
# 1. Creates an AWS Connection Entity storing the base role ARN as credential.
# 2. Creates a HAS_FED_LOGS_BASE_ROLE relationship from fleet_entity_guid → AWS Connection Entity.

# TODO we will change this to use new relic providers directly. 
resource "null_resource" "aws_connection_entity" {
  triggers = {
    role_arn          = aws_iam_role.base_role.arn
    nr_org_id         = var.newrelic_org_id
    fleet_entity_guid = var.fleet_entity_guid
    entity_name       = "${local.naming_prefix}-aws-connection"
    nr_endpoint       = local.nr_graphql_endpoint
    nr_api_key        = var.newrelic_api_key
    auth_mode         = local.auth_mode
  }

  provisioner "local-exec" {
    environment = {
      ROLE_ARN          = aws_iam_role.base_role.arn
      ENTITY_NAME       = "${local.naming_prefix}-aws-connection"
      NR_ORG_ID         = var.newrelic_org_id
      FLEET_ENTITY_GUID = var.fleet_entity_guid
      NR_API_KEY        = var.newrelic_api_key
      NR_ENDPOINT       = local.nr_graphql_endpoint
      AUTH_MODE         = local.auth_mode
    }
    command = "python3 ${path.module}/scripts/create_aws_connection.py"
  }

}