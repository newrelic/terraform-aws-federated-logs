#!/usr/bin/env python3
"""
Federated Logs E2E Test

Sends a test log payload to the PCG endpoint, then verifies
it appears in New Relic via NRQL query. A unique UUID is
injected into the payload so we can query for the exact log.

Usage:
    python3 e2e_test.py \
        --pcg-endpoint "https://pcg.example.com/v1/logs" \
        --license-key "INGEST-KEY-..." \
        --partition "application_log" \
        --nr-account-id "1234567" \
        --nr-api-key "NRAK-..." \
        --payload '{"message": "test log entry", "level": "info"}'

All arguments can also be set via environment variables:
    PCG_ENDPOINT, NR_LICENSE_KEY, PARTITION_NAME,
    NR_ACCOUNT_ID, NR_API_KEY, TEST_PAYLOAD
"""

import argparse
import json
import os
import sys
import time
import uuid
import urllib.request
import urllib.error

# ── Constants ─────────────────────────────────────────────────
WRITE_MAX_RETRIES = int(os.environ.get("E2E_WRITE_MAX_RETRIES", 3))
WRITE_RETRY_DELAY = int(os.environ.get("E2E_WRITE_RETRY_DELAY", 5))
READ_MAX_RETRIES = int(os.environ.get("E2E_READ_MAX_RETRIES", 6))
READ_RETRY_DELAY = int(os.environ.get("E2E_READ_RETRY_DELAY", 15))
INITIAL_READ_WAIT = int(os.environ.get("E2E_INITIAL_READ_WAIT", 30))

NR_GRAPHQL_ENDPOINTS = {
    "us":      "https://api.newrelic.com/graphql",
    "eu":      "https://api.eu.newrelic.com/graphql",
    "staging": "https://staging-api.newrelic.com/graphql",
}


def get_graphql_url(region, staging):
    key = "staging" if staging else region.lower()
    url = NR_GRAPHQL_ENDPOINTS.get(key)
    if url is None:
        fail_msg(f"No GraphQL endpoint for region='{region}'")
        sys.exit(1)
    return url

# ── Color output ──────────────────────────────────────────────
RED = "\033[0;31m"
GREEN = "\033[0;32m"
YELLOW = "\033[0;33m"
NC = "\033[0m"


def info(msg):
    print(f"{NC}[INFO]  {msg}")


def warn(msg):
    print(f"{YELLOW}[WARN]  {msg}{NC}")


def pass_msg(msg):
    print(f"{GREEN}[PASS]  {msg}{NC}")


def fail_msg(msg):
    print(f"{RED}[FAIL]  {msg}{NC}")


# ── HTTP helpers ──────────────────────────────────────────────
def http_post(url, headers, body):
    """POST JSON and return (status_code, response_body)."""
    data = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(url, data=data, method="POST")
    for k, v in headers.items():
        req.add_header(k, v)
    try:
        with urllib.request.urlopen(req) as resp:
            return resp.status, resp.read().decode("utf-8")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8")
    except urllib.error.URLError as e:
        return 0, str(e.reason)


# ── Step 1: Send payload to PCG ───────────────────────────────
def send_to_pcg(endpoint, license_key, payload):
    info("")
    info("Step 1: Sending test payload to PCG endpoint...")

    headers = {
        "Content-Type": "application/json",
        "Api-Key": license_key,
    }
    # PCG expects an array of log entries
    body = [payload]

    for attempt in range(1, WRITE_MAX_RETRIES + 1):
        status, response_body = http_post(endpoint, headers, body)

        if 200 <= status < 300:
            pass_msg(f"Payload sent successfully (HTTP {status})")
            return True

        warn(f"Attempt {attempt}/{WRITE_MAX_RETRIES}: PCG returned HTTP {status}")
        warn(f"Response: {response_body}")

        if attempt < WRITE_MAX_RETRIES:
            info(f"Retrying in {WRITE_RETRY_DELAY}s...")
            time.sleep(WRITE_RETRY_DELAY)

    fail_msg(f"Failed to send payload to PCG after {WRITE_MAX_RETRIES} attempts")
    return False


# ── Step 3: Query New Relic ───────────────────────────────────
def query_new_relic(account_id, api_key, partition, test_uuid, graphql_url):
    info("")
    info(f"Step 3: Querying New Relic for test log (UUID: {test_uuid})...")
    info(f"GraphQL endpoint: {graphql_url}")

    nrql = (
        f"SELECT * FROM {partition} "
        f"WHERE e2e_test_id = '{test_uuid}' SINCE 10 minutes ago"
    )

    graphql_query = (
        "{ actor { account(id: %s) { nrql(query: \"%s\") { results } } } }"
        % (account_id, nrql)
    )

    headers = {
        "Content-Type": "application/json",
        "API-Key": api_key,
    }

    log_count = 0
    last_response = ""

    for attempt in range(1, READ_MAX_RETRIES + 1):
        if attempt > 1:
            info(f"Retry {attempt}/{READ_MAX_RETRIES}: waiting {READ_RETRY_DELAY}s...")
            time.sleep(READ_RETRY_DELAY)

        status, response_body = http_post(
            graphql_url, headers, {"query": graphql_query}
        )
        last_response = response_body

        if status == 0:
            warn(f"Attempt {attempt}: Connection error: {response_body}")
            continue

        try:
            data = json.loads(response_body)
        except json.JSONDecodeError:
            warn(f"Attempt {attempt}: Invalid JSON response")
            continue

        # Check for GraphQL errors
        errors = data.get("errors", [])
        if errors:
            warn(f"Attempt {attempt}: API error: {errors[0].get('message', 'Unknown')}")
            continue

        # Extract results
        try:
            results = data["data"]["actor"]["account"]["nrql"]["results"]
            log_count = len(results)
        except (KeyError, IndexError, TypeError):
            warn(f"Attempt {attempt}: Unexpected response structure")
            continue

        info(f"Attempt {attempt}: found {log_count} matching log(s)")

        if log_count >= 1:
            return True, log_count, last_response

    return False, log_count, last_response


# ── Main ──────────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser(
        description="Federated Logs E2E Test",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument(
        "--pcg-endpoint",
        default=os.environ.get("PCG_ENDPOINT", ""),
        help="PCG ingest endpoint URL",
    )
    parser.add_argument(
        "--license-key",
        default=os.environ.get("NR_LICENSE_KEY", ""),
        help="New Relic license/ingest key",
    )
    parser.add_argument(
        "--partition",
        default=os.environ.get("PARTITION_NAME", ""),
        help="Target partition (table) name for NRQL query",
    )
    parser.add_argument(
        "--nr-account-id",
        default=os.environ.get("NR_ACCOUNT_ID", ""),
        help="New Relic account ID",
    )
    parser.add_argument(
        "--nr-api-key",
        default=os.environ.get("NR_API_KEY", ""),
        help="New Relic User API key for GraphQL queries",
    )
    parser.add_argument(
        "--payload",
        default=os.environ.get("TEST_PAYLOAD", ""),
        help='JSON payload (default: {"message": "federated-logs e2e test", "level": "info"})',
    )
    parser.add_argument(
        "--region",
        default=os.environ.get("NR_REGION", "us"),
        choices=["us", "eu"],
        help="New Relic region (default: us)",
    )
    parser.add_argument(
        "--staging",
        action="store_true",
        default=os.environ.get("NR_STAGING", "").lower() in ("true", "1", "yes"),
        help="Use the staging GraphQL endpoint (default: false)",
    )
    parser.add_argument(
        "--graphql-url",
        default=os.environ.get("NR_GRAPHQL_URL", ""),
        help="Override the GraphQL endpoint URL (ignores --region and --staging)",
    )

    args = parser.parse_args()

    # Validate required inputs
    required = {
        "PCG_ENDPOINT / --pcg-endpoint": bool(args.pcg_endpoint),
        "NR_LICENSE_KEY / --license-key": bool(args.license_key),
        "PARTITION_NAME / --partition": bool(args.partition),
        "NR_ACCOUNT_ID / --nr-account-id": bool(args.nr_account_id),
        "NR_API_KEY / --nr-api-key": bool(args.nr_api_key),
    }
    missing = [name for name, present in required.items() if not present]
    if missing:
        fail_msg("Missing required inputs:")
        for m in missing:
            print(f"  - {m}")
        sys.exit(1)

    # Default payload
    if args.payload:
        try:
            payload = json.loads(args.payload)
        except json.JSONDecodeError:
            fail_msg("--payload is not valid JSON")
            sys.exit(1)
    else:
        payload = {"message": "federated-logs e2e test", "level": "info"}

    # Resolve GraphQL endpoint
    graphql_url = args.graphql_url or get_graphql_url(args.region, args.staging)

    # Generate UUID and inject
    test_uuid = str(uuid.uuid4())
    payload["e2e_test_id"] = test_uuid

    info("──────────────────────────────────────────────────")
    info("Federated Logs E2E Test")
    info("──────────────────────────────────────────────────")
    info(f"PCG Endpoint:  {args.pcg_endpoint}")
    info(f"Partition:     {args.partition}")
    info(f"Test UUID:     {test_uuid}")
    info(f"NR Account:    {args.nr_account_id}")
    info(f"NR Region:     {args.region}{'  (staging)' if args.staging else ''}")
    info(f"GraphQL URL:   {graphql_url}")
    info(f"Payload:       {json.dumps(payload)}")
    info("──────────────────────────────────────────────────")

    # Step 1: Send to PCG
    if not send_to_pcg(args.pcg_endpoint, args.license_key, payload):
        sys.exit(1)

    # Step 2: Wait for ingestion
    info("")
    info(f"Step 2: Waiting {INITIAL_READ_WAIT}s for log ingestion...")
    time.sleep(INITIAL_READ_WAIT)

    # Step 3: Query New Relic
    success, count, last_response = query_new_relic(
        args.nr_account_id, args.nr_api_key, args.partition, test_uuid, graphql_url
    )

    # Results
    info("")
    info("──────────────────────────────────────────────────")
    if success:
        pass_msg("E2E test PASSED")
        pass_msg(f"Test log with UUID {test_uuid} found in New Relic (count: {count})")
        info("──────────────────────────────────────────────────")
        sys.exit(0)
    else:
        fail_msg("E2E test FAILED")
        fail_msg(
            f"Test log with UUID {test_uuid} not found after {READ_MAX_RETRIES} attempts"
        )
        info(f"Last API response: {last_response}")
        info("──────────────────────────────────────────────────")
        sys.exit(1)


if __name__ == "__main__":
    main()
