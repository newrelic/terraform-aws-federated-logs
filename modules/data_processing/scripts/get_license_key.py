import json, os, sys

# Terraform's external data source passes `query` as a JSON object on stdin.
# Prefer an explicitly supplied key; fall back to the process environment so
# existing callers keep working unchanged.
try:
    query = json.loads(sys.stdin.read() or "{}")
except (json.JSONDecodeError, ValueError):
    query = {}

license_key = query.get("license_key") or os.environ.get("NEW_RELIC_LICENSE_KEY")
if not license_key:
    print(
        "Error: no license key available. Set var.newrelic_license_key or the "
        "NEW_RELIC_LICENSE_KEY environment variable.",
        file=sys.stderr,
    )
    sys.exit(1)

# Output as JSON for Terraform external data source
print(json.dumps({"license_key": license_key}))
