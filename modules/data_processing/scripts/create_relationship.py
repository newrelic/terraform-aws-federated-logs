import json, os, urllib.request, sys

# Creates a HAS_FED_LOGS_BASE_ROLE relationship from the fleet entity to the
# AWS Connection entity that wraps the PCG base role.

endpoint          = os.environ['NR_ENDPOINT']
nr_api_key        = os.environ['NEW_RELIC_API_KEY']
if not nr_api_key:
    print("Error: NEW_RELIC_API_KEY environment variable is not set", file=sys.stderr)
    sys.exit(1)
fleet_entity_guid = os.environ['FLEET_ENTITY_GUID']
connection_id     = os.environ['CONNECTION_ID']


def call_graphql(query, variables=None):
    payload = json.dumps({"query": query, "variables": variables or {}}).encode()
    headers = {
        "Content-Type": "application/json",
        "API-Key": nr_api_key,
        "X-Query-Source-Capability-Id": "ADD_DATA",
    }
    req = urllib.request.Request(endpoint, data=payload, headers=headers)
    try:
        return json.loads(urllib.request.urlopen(req).read())
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        print("HTTP %d %s\nResponse: %s" % (e.code, e.reason, body), file=sys.stderr)
        sys.exit(1)


mutation = """
mutation($input: EntityManagementRelationshipCreateInput!) {
  entityManagementCreateRelationship(relationship: $input) {
    relationship { type }
  }
}
"""

variables = {
    "input": {
        "type":   "HAS_FED_LOGS_BASE_ROLE",
        "source": {"id": fleet_entity_guid, "scope": "ORGANIZATION"},
        "target": {"id": connection_id,     "scope": "ORGANIZATION"},
    }
}

resp = call_graphql(mutation, variables)
if "errors" in resp:
    errors = resp["errors"]
    # Idempotent: a relationship with the same (source, target, type) tuple
    # already exists → treat as success.
    if any(e.get("extensions", {}).get("errorClass") == "ENTITY_UNIQUE_CONSTRAINT_VIOLATION" for e in errors):
        print("HAS_FED_LOGS_BASE_ROLE relationship already exists (%s -> %s). Nothing to do." % (fleet_entity_guid, connection_id))
        sys.exit(0)
    print("GraphQL errors (create relationship): " + json.dumps(errors, indent=2), file=sys.stderr)
    sys.exit(1)

print("Created HAS_FED_LOGS_BASE_ROLE relationship: %s -> %s" % (fleet_entity_guid, connection_id))
