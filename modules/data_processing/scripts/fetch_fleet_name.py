import json, os, sys, urllib.request

# `data "external"` data source contract: read a JSON object of strings from
# stdin, write a JSON object of strings to stdout. Resolves fleet_entity_guid's
# display name via a direct NerdGraph entity(guid:) lookup, for the "fleet.entity.name"
# Flink application property (display-only; fleet.entity.guid remains the stable
# identifier the rest of the pipeline keys off of).
#
# Never fails terraform apply over this: a bad GUID, an expired key, or NerdGraph
# being down should not block deploying the fleet's actual pipeline over a
# cosmetic dashboard label. On any failure, print an empty name and exit 0 —
# the failure reason still goes to stderr so it's visible in the apply output.


def call_graphql(endpoint, nr_api_key, query, variables):
    payload = json.dumps({"query": query, "variables": variables}).encode()
    req = urllib.request.Request(endpoint, data=payload, headers={
        "Content-Type": "application/json",
        "API-Key": nr_api_key,
        "X-Query-Source-Capability-Id": "ADD_DATA",
    })
    return json.loads(urllib.request.urlopen(req).read())


def fail_soft(reason):
    print(reason, file=sys.stderr)
    print(json.dumps({"fleet_entity_name": ""}))
    sys.exit(0)


nr_api_key = os.environ.get('NEW_RELIC_API_KEY')
if not nr_api_key:
    fail_soft("Error: NEW_RELIC_API_KEY environment variable is not set")

query = json.load(sys.stdin)
fleet_entity_guid = query["fleet_entity_guid"]
nr_endpoint = query["nr_endpoint"]

graphql_query = """
query($guid: EntityGuid!) {
  actor {
    entity(guid: $guid) {
      name
    }
  }
}
"""

try:
    resp = call_graphql(nr_endpoint, nr_api_key, graphql_query, {"guid": fleet_entity_guid})
except urllib.error.HTTPError as e:
    body = e.read().decode("utf-8", errors="replace")
    fail_soft("HTTP %d %s fetching fleet entity name\nResponse: %s" % (e.code, e.reason, body))
except Exception as e:
    fail_soft("Error fetching fleet entity name: %s" % e)

if "errors" in resp:
    fail_soft("GraphQL errors (fleet entity name lookup): " + json.dumps(resp["errors"], indent=2))

entity = (resp.get("data") or {}).get("actor", {}).get("entity")
if not entity or not entity.get("name"):
    fail_soft("No entity/name found for fleet_entity_guid: %s" % fleet_entity_guid)

print(json.dumps({"fleet_entity_name": entity["name"]}))
