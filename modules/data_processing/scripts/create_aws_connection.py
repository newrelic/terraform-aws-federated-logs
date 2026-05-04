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
    errors = resp["errors"]
    if any(e.get("extensions", {}).get("errorClass") == "ENTITY_UNIQUE_CONSTRAINT_VIOLATION" for e in errors):
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
""" % name
        search_resp = call_graphql(search_query)
        entities = search_resp.get('data', {}).get('actor', {}).get('entitySearch', {}).get('results', {}).get('entities', [])
        if not entities:
            print("Entity already exists but could not be found by name: %s" % name, file=sys.stderr)
            sys.exit(1)
        entity_id = entities[0]['guid']
        print("AWS Connection Entity already exists, reusing: " + entity_id)
    else:
        print("GraphQL errors (create entity): " + json.dumps(errors, indent=2), file=sys.stderr)
        sys.exit(1)
else:
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
