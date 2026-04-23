data "aws_region" "current" {
  region = var.region
}

data "aws_caller_identity" "current" {}

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
    PCG_Instance = var.setup_name
  }
}

# ABAC wildcard policy: allows assuming any pcg-writer role in any account
# where the role's PCG_Instance tag matches this base role's PCG_Instance tag.
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
            "aws:ResourceTag/PCG_Instance" = "$${aws:PrincipalTag/PCG_Instance}"
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
# 2. Creates an APPLY_TO relationship from fleet_entity_guid → AWS Connection Entity.

resource "null_resource" "aws_connection_entity" {
  triggers = {
    role_arn          = aws_iam_role.base_role.arn
    nr_org_id         = var.newrelic_org_id
    fleet_entity_guid = var.fleet_entity_guid
    entity_name       = "${local.naming_prefix}-aws-connection"
    nr_endpoint       = local.nr_graphql_endpoint
    nr_api_key        = var.newrelic_api_key
  }

  provisioner "local-exec" {
    environment = {
      ROLE_ARN          = aws_iam_role.base_role.arn
      ENTITY_NAME       = "${local.naming_prefix}-aws-connection"
      NR_ORG_ID         = var.newrelic_org_id
      FLEET_ENTITY_GUID = var.fleet_entity_guid
      NR_API_KEY        = var.newrelic_api_key
      NR_ENDPOINT       = local.nr_graphql_endpoint
    }
    command = <<-EOT
      set -e
      python3 - <<'PYEOF'
import json, urllib.request, os, sys

endpoint          = os.environ['NR_ENDPOINT']
api_key           = os.environ['NR_API_KEY']
role_arn          = os.environ['ROLE_ARN']
name              = os.environ['ENTITY_NAME']
org_id            = os.environ['NR_ORG_ID']
fleet_entity_guid = os.environ['FLEET_ENTITY_GUID']

def call_graphql(query):
    payload = json.dumps({"query": query}).encode()
    req = urllib.request.Request(endpoint, data=payload, headers={
        "Content-Type": "application/json",
        "API-Key": api_key
    })
    try:
        return json.loads(urllib.request.urlopen(req).read())
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        print("HTTP %d %s\nResponse: %s" % (e.code, e.reason, body), file=sys.stderr)
        sys.exit(1)

# Step 1: Create AWS Connection Entity
create_mutation = """
mutation {
  entityManagementCreateAwsConnection(
    awsConnectionEntity: {
      name: "%s",
      credential: {assumeRole: {roleArn: "%s"}},
      scope: {id: "%s", type: ORGANIZATION}
    }
  ) {
    entity { id }
  }
}
""" % (name, role_arn, org_id)

resp = call_graphql(create_mutation)
if "errors" in resp:
    print("GraphQL errors (create entity): " + json.dumps(resp["errors"], indent=2), file=sys.stderr)
    sys.exit(1)

entity_id = resp['data']['entityManagementCreateAwsConnection']['entity']['id']
print("Created AWS Connection Entity: " + entity_id)

# Step 2: Create APPLY_TO relationship fleet_entity_guid -> aws_connection_entity
rel_mutation = """
mutation {
  entityManagementCreateRelationship(
    relationship: {
      source: {id: "%s", scope: ORGANIZATION}
      target: {id: "%s", scope: ORGANIZATION}
      type: "APPLY_TO"
    }
  ) {
    relationship {
      type
      source { id }
      target { id }
    }
  }
}
""" % (fleet_entity_guid, entity_id)

resp = call_graphql(rel_mutation)
if "errors" in resp:
    print("GraphQL errors (create relationship): " + json.dumps(resp["errors"], indent=2), file=sys.stderr)
    sys.exit(1)

print("Created APPLY_TO relationship: %s -> %s" % (fleet_entity_guid, entity_id))
PYEOF
    EOT
  }

  provisioner "local-exec" {
    when = destroy
    environment = {
      NR_API_KEY        = self.triggers.nr_api_key
      NR_ENDPOINT       = self.triggers.nr_endpoint
      ENTITY_NAME       = self.triggers.entity_name
      FLEET_ENTITY_GUID = self.triggers.fleet_entity_guid
      NR_ORG_ID         = self.triggers.nr_org_id
    }
    command = <<-EOT
      set -e
      python3 - <<'PYEOF'
import json, urllib.request, os, sys

endpoint          = os.environ['NR_ENDPOINT']
api_key           = os.environ['NR_API_KEY']
entity_name       = os.environ['ENTITY_NAME']
fleet_entity_guid = os.environ['FLEET_ENTITY_GUID']
org_id            = os.environ['NR_ORG_ID']

def call_graphql(query):
    payload = json.dumps({"query": query}).encode()
    req = urllib.request.Request(endpoint, data=payload, headers={
        "Content-Type": "application/json",
        "API-Key": api_key
    })
    try:
        return json.loads(urllib.request.urlopen(req).read())
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        print("HTTP %d %s\nResponse: %s" % (e.code, e.reason, body), file=sys.stderr)
        sys.exit(1)

# Look up the entity ID by name so we don't rely on any local file.
search_query = """
{
  actor {
    entitySearch(query: "name = '%s' AND type = 'AWS_CONNECTION'") {
      results {
        entities { guid }
      }
    }
  }
}
""" % entity_name

resp = call_graphql(search_query)
entities = resp.get('data', {}).get('actor', {}).get('entitySearch', {}).get('results', {}).get('entities', [])
if not entities:
    print("AWS Connection Entity '%s' not found, skipping delete." % entity_name)
    sys.exit(0)

entity_id = entities[0]['guid']

# TODO: Delete APPLY_TO relationship once delete mutation is confirmed.
# TODO: Delete AWS Connection Entity once delete mutation is confirmed.
print("TODO: delete relationship and AWS Connection Entity %s — mutations not yet confirmed." % entity_id)
PYEOF
    EOT
  }
}

# TODO: Create FederatedLogsDataProcessingEntity once mutation is available.
# This entity is fleet-level and references the AWS Connection Entity created above.

