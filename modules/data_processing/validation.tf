# =============================================================================
# OIDC Provider Existence Check (opt-in)
#
# Verifies that each IRSA cluster's oidc_provider_arn actually exists in the
# AWS account. An invalid OIDC provider will cause AssumeRoleWithWebIdentity
# to fail at runtime with a "Not authorized to perform
# sts:AssumeRoleWithWebIdentity" error from EKS pods.
#
# Requires: iam:GetOpenIDConnectProvider on the deploying identity.
# Gated by: var.validate_oidc_providers (default false).
# Skipped automatically when auth_mode = "pod_identity" (no OIDC involved).
# =============================================================================

data "aws_iam_openid_connect_provider" "cluster" {
  for_each = local.oidc_arns_to_validate
  arn      = each.value
}

check "oidc_providers_exist" {
  assert {
    condition = !var.validate_oidc_providers || local.auth_mode != "irsa" || alltrue([
      for k, arn in local.oidc_arns_to_validate :
      data.aws_iam_openid_connect_provider.cluster[k].arn == arn
    ])
    error_message = "One or more OIDC provider ARNs from the clusters map do not exist in this AWS account. EKS pods will not be able to assume the fleet base role via IRSA."
  }
}
