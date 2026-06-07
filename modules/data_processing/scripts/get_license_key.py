import json, os, sys

license_key = os.environ.get('NEW_RELIC_LICENSE_KEY')
if not license_key:
    print("Error: NEW_RELIC_LICENSE_KEY environment variable is not set", file=sys.stderr)
    sys.exit(1)

# Output as JSON for Terraform external data source
print(json.dumps({"license_key": license_key}))
