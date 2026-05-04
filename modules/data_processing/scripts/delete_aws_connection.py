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


# Look up entity ID by name so we don't rely on any local state file.
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
