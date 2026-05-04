import json, urllib.request, sys


def call_graphql(endpoint, api_key, query):
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


query = json.load(sys.stdin)
fleet_entity_guid = query["fleet_entity_guid"]
nr_api_key        = query["nr_api_key"]
nr_endpoint       = query["nr_endpoint"]

# TODO: Step 1 — Resolve aws_connection_entity_id from fleet_entity_guid.
# The relationship traversal API to go from a fleet entity GUID to its
# APPLY_TO target (AWS Connection Entity) is not yet confirmed.
# Hardcoded placeholder until that API is available.
aws_connection_entity_id = "TODO_RESOLVE_FROM_FLEET_GUID"

# Step 2: Fetch base role ARN from the AWS Connection Entity.
entity_query = """
{
  actor {
    entityManagement {
      entity(id: "%s") {
        ... on EntityManagementAwsConnectionEntity {
          credential {
            assumeRole {
              roleArn
            }
          }
        }
      }
    }
  }
}
""" % aws_connection_entity_id

resp = call_graphql(nr_endpoint, nr_api_key, entity_query)
if "errors" in resp:
    print("GraphQL errors (fetch entity): " + json.dumps(resp["errors"], indent=2), file=sys.stderr)
    sys.exit(1)

try:
    role_arn = resp["data"]["actor"]["entityManagement"]["entity"]["credential"]["assumeRole"]["roleArn"]
except (KeyError, TypeError):
    print("Could not parse roleArn from response: " + json.dumps(resp), file=sys.stderr)
    sys.exit(1)

print(json.dumps({"role_arn": role_arn}))
