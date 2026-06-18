"""
Reads New Relic credentials from the Terraform runner's environment and
emits them as JSON for `data "external"`.
"""
import json
import os
import sys


def require(var):
    value = os.environ.get(var)
    if not value:
        print(f"Error: {var} environment variable is not set", file=sys.stderr)
        sys.exit(1)
    return value


print(json.dumps({
    "license_key": require("NEW_RELIC_LICENSE_KEY"),
    "api_key":     require("NEW_RELIC_API_KEY"),
}))
