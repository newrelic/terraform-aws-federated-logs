import json, os, urllib.request, sys


def call_graphql(endpoint, nr_api_key, query):
    payload = json.dumps({"query": query}).encode()
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


nr_api_key = os.environ['NEWRELIC_API_KEY']
if not nr_api_key:
    print("Error: NEWRELIC_API_KEY environment variable is not set", file=sys.stderr)
    sys.exit(1)
    
query = json.load(sys.stdin)
fleet_entity_guid = query["fleet_entity_guid"]
nr_endpoint       = query["nr_endpoint"]

# Search for the AWS Connection Entity tagged with this fleet_entity_guid
# TO DO to change this and use new relic providers.
search_query = """
{
  actor {
    entitySearch(query: "domain = 'NGEP' AND type = 'AWS_CONNECTION' AND tags.`fleet_entity_guid` = '%s'") {
      results {
        entities {
          guid
          tags {
            key
            values
          }
        }
      }
    }
  }
}
""" % fleet_entity_guid

resp = call_graphql(nr_endpoint, nr_api_key, search_query)
if "errors" in resp:
    print("GraphQL errors (search entity): " + json.dumps(resp["errors"], indent=2), file=sys.stderr)
    sys.exit(1)

entities = resp.get("data", {}).get("actor", {}).get("entitySearch", {}).get("results", {}).get("entities", [])
if not entities:
    print("No AWS Connection Entity found for fleet_entity_guid: %s" % fleet_entity_guid, file=sys.stderr)
    sys.exit(1)

entity = entities[0]
tags = {t["key"]: t["values"][0] for t in entity["tags"] if t["values"]}

role_arn = tags.get("credential.assumeRole.roleArn")
if not role_arn:
    print("credential.assumeRole.roleArn tag not found on entity: %s" % entity["guid"], file=sys.stderr)
    sys.exit(1)

sqs_queue_arn = tags.get("sqs_queue_arn", "")

print(json.dumps({"role_arn": role_arn, "sqs_queue_arn": sqs_queue_arn}))
