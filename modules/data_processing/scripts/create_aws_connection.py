import json, urllib.request, os, sys

endpoint          = os.environ['NR_ENDPOINT']
nr_api_key           = os.environ['NEWRELIC_API_KEY']
if not nr_api_key:
    print("Error: NEWRELIC_API_KEY environment variable is not set", file=sys.stderr)
    sys.exit(1)
role_arn          = os.environ['ROLE_ARN']
name              = os.environ['ENTITY_NAME']
org_id            = os.environ['NR_ORG_ID']
fleet_entity_guid = os.environ['FLEET_ENTITY_GUID']
auth_mode         = os.environ['AUTH_MODE']
sqs_queue_arn     = os.environ['SQS_QUEUE_ARN']


def call_graphql(query, variables=None):
    payload = json.dumps({"query": query, "variables": variables or {}}).encode()
    req = urllib.request.Request(endpoint, data=payload, headers={
        "Content-Type": "application/json",
        "API-Key": nr_api_key,
        "X-Query-Source-Capability-Id": "ADD_DATA"
    })
    try:
        return json.loads(urllib.request.urlopen(req).read())
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        print("HTTP %d %s\nResponse: %s" % (e.code, e.reason, body), file=sys.stderr)
        sys.exit(1)

# TO DO to change this to use nr provider if possible
# Step 1: Create AWS Connection Entity
create_mutation = """
mutation($input: EntityManagementAwsConnectionEntityCreateInput!) {
  entityManagementCreateAwsConnection(awsConnectionEntity: $input) {
    entity { id }
  }
}
"""

create_variables = {
    "input": {
        "name": name,
        "credential": {"assumeRole": {"roleArn": role_arn}},
        "scope": {"id": org_id, "type": "ORGANIZATION"},
        "tags": [
            {"key": "fleet_entity_guid", "values": [fleet_entity_guid]},
            {"key": "auth_mode",         "values": [auth_mode]},
            {"key": "sqs_queue_arn",     "values": [sqs_queue_arn]},
        ],
    }
}

resp = call_graphql(create_mutation, create_variables)

if "errors" in resp:
    errors = resp["errors"]
    if any(e.get("extensions", {}).get("errorClass") == "ENTITY_UNIQUE_CONSTRAINT_VIOLATION" for e in errors):
        print("AWS Connection Entity already exists, relationship also already exists. Nothing to do.")
        sys.exit(0)
    print("GraphQL errors (create entity): " + json.dumps(errors, indent=2), file=sys.stderr)
    sys.exit(1)

entity_id = resp['data']['entityManagementCreateAwsConnection']['entity']['id']
print("Created AWS Connection Entity: " + entity_id)

# Step 2: Create HAS_FED_LOGS_BASE_ROLE relationship fleet_entity_guid -> aws_connection_entity
rel_mutation = """
mutation($input: EntityManagementRelationshipCreateInput!) {
  entityManagementCreateRelationship(relationship: $input) {
    relationship {
      type
      source { id }
      target { id }
    }
  }
}
"""

rel_variables = {
    "input": {
        "source": {"id": fleet_entity_guid, "scope": "ORGANIZATION"},
        "target": {"id": entity_id,          "scope": "ORGANIZATION"},
        "type":   "HAS_FED_LOGS_BASE_ROLE",
    }
}

resp = call_graphql(rel_mutation, rel_variables)
if "errors" in resp:
    print("GraphQL errors (create relationship): " + json.dumps(resp["errors"], indent=2), file=sys.stderr)
    sys.exit(1)

print("Created HAS_FED_LOGS_BASE_ROLE relationship: %s -> %s" % (fleet_entity_guid, entity_id))
