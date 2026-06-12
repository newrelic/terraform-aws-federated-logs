#!/usr/bin/env python3
"""
Federated Logs E2E Test

Sends a test log payload to the PCG endpoint, then verifies
it appears in New Relic via NRQL query. A unique UUID is
injected into the payload so we can query for the exact log.

Usage:
    python3 e2e_test.py \
        --pcg-endpoint "https://pcg.example.com" \
        --license-key "INGEST-KEY-..." \
        --nr-account-id "1234567" \
        --nr-api-key "NRAK-..." \
        --payload '{"message": "test log entry", "level": "info"}'

All arguments can also be set via environment variables:
    PCG_ENDPOINT, NEW_RELIC_LICENSE_KEY,
    NR_ACCOUNT_ID, NEW_RELIC_API_KEY, TEST_PAYLOAD
"""

import argparse
import datetime
import json
import os
import sys
import time
import uuid
import urllib.request
import urllib.error

# ── Constants ─────────────────────────────────────────────────
MAX_RETRIES = int(os.environ.get("E2E_MAX_RETRIES", 3))
RETRY_DELAY = int(os.environ.get("E2E_RETRY_DELAY", 5))
INITIAL_READ_WAIT = int(os.environ.get("E2E_INITIAL_READ_WAIT", 30))

# Used to wait for the test log to surface in NRQL.
# Distinct from the HTTP retry because the failure mode is ingestion
# latency (200 OK with empty results), not a transient error.
READ_MAX_RETRIES = int(os.environ.get("E2E_READ_MAX_RETRIES", 5))
READ_RETRY_DELAY = int(os.environ.get("E2E_READ_RETRY_DELAY", 15))

NR_GRAPHQL_ENDPOINTS = {
    "US":      "https://api.newrelic.com/graphql",
    "EU":      "https://api.eu.newrelic.com/graphql",
    "STAGING": "https://staging-api.newrelic.com/graphql",
}


def get_graphql_url(region):
    url = NR_GRAPHQL_ENDPOINTS.get(region)
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
    """POST JSON and return (status_code, response_body). Retries on transient errors."""
    data = json.dumps(body).encode("utf-8")
    statusResponse, response_body = 0, ""
    for attempt in range(1, MAX_RETRIES + 1):
        req = urllib.request.Request(url, data=data, method="POST")
        for k, v in headers.items():
            req.add_header(k, v)
        try:
            with urllib.request.urlopen(req) as resp:
                statusResponse = resp.status
                response_body = resp.read().decode("utf-8")
        except urllib.error.HTTPError as e:
            statusResponse = e.code
            response_body = e.read().decode("utf-8")
        except urllib.error.URLError as e:
            statusResponse = 0
            response_body = str(e.reason)

        if statusResponse == 0 or statusResponse >= 500:
            if attempt < MAX_RETRIES:
                warn(f"Attempt {attempt}/{MAX_RETRIES}: HTTP {statusResponse}, retrying in {RETRY_DELAY}s...")
                time.sleep(RETRY_DELAY)
                continue

        return statusResponse, response_body
    return statusResponse, response_body


# ── Step 1: Check PCG health ──────────────────────────────────
def check_pcg_health(base_endpoint):
    url = f"{base_endpoint}:13133/health/status"
    info("")
    info("Step 1: Checking PCG health...")
    info(f"Health endpoint: {url}")

    statusResponse, body = 0, ""
    for attempt in range(1, MAX_RETRIES + 1):
        req = urllib.request.Request(url, method="GET")
        try:
            with urllib.request.urlopen(req) as resp:
                statusResponse = resp.status
                body = resp.read().decode("utf-8")
        except urllib.error.HTTPError as e:
            statusResponse = e.code
            body = e.read().decode("utf-8")
        except urllib.error.URLError as e:
            statusResponse = 0
            body = str(e.reason)

        if statusResponse == 0 or statusResponse >= 500:
            if attempt < MAX_RETRIES:
                warn(f"Attempt {attempt}/{MAX_RETRIES}: health check HTTP {statusResponse}, retrying in {RETRY_DELAY}s...")
                time.sleep(RETRY_DELAY)
                continue
        break

    try:
        data = json.loads(body)
        healthy = data.get("healthy") is True
    except (json.JSONDecodeError, AttributeError):
        healthy = False

    if not healthy:
        fail_msg(f"PCG health check failed (HTTP {statusResponse}): {body}")
        return False, {
            "error": "PCG is not reachable",
            "description": "Verify the PCG pod is running and the service endpoint is exposed",
        }

    pass_msg("PCG is healthy")
    return True, None


# ── Step 2: Send payload to PCG ───────────────────────────────
def send_to_pcg(base_endpoint, license_key, payload):
    endpoint = f"{base_endpoint}:80/log/v1"
    info("")
    info("Step 2: Sending test payload to PCG endpoint...")
    info(f"Logs endpoint: {endpoint}")

    headers = {
        "Content-Type": "application/json",
        "X-License-Key": license_key,
    }
    # PCG expects an array of log entries
    body = [payload]

    status, response_body = http_post(endpoint, headers, body)

    if 200 <= status < 300:
        pass_msg(f"Payload sent successfully (HTTP {status})")
        return True, None

    warn(f"PCG returned HTTP {status}: {response_body}")

    if status in (401, 403):
        fail_msg("License key error")
        return False, {
            "error": "License key configured in PCG is either invalid or expired",
            "description": "Re-check the key configured in the PCG Helm values",
        }

    fail_msg("Failed to send payload to PCG")
    return False, {
        "error": "Error sending log to PCG",
        "description": "Please check the logs of PCG pods",
    }


# ── Step 4: Query New Relic ───────────────────────────────────
def query_new_relic(account_id, api_key, partition, test_uuid, graphql_url):
    info("")
    info(f"Step 4: Querying New Relic for test log (UUID: {test_uuid})...")
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

    response_body = ""
    for attempt in range(1, READ_MAX_RETRIES + 1):
        status, response_body = http_post(
            graphql_url, headers, {"query": graphql_query}
        )

        try:
            data = json.loads(response_body)
        except json.JSONDecodeError:
            warn("Invalid JSON response from New Relic")
            return False, 0, response_body, nrql, {
                "error": "Unable to query the test log",
                "description": "Please check troubleshooting docs",
            }

        # Check for GraphQL errors
        errors = data.get("errors", [])
        if errors:
            warn(f"New Relic API error: {errors[0].get('message', 'Unknown')}")
            return False, 0, response_body, nrql, {
                "error": "Unable to query the test log",
                "description": "Please check troubleshooting docs",
            }

        try:
            results = data["data"]["actor"]["account"]["nrql"]["results"]
            log_count = len(results)
        except (KeyError, IndexError, TypeError):
            warn("Unexpected response structure from New Relic")
            return False, 0, response_body, nrql, {
                "error": "Unable to query the test log",
                "description": "Please check troubleshooting docs",
            }

        info(f"Attempt {attempt}/{READ_MAX_RETRIES}: found {log_count} matching log(s)")

        if log_count >= 1:
            return True, log_count, results[0], nrql, None

        # Empty result — log probably hasn't ingested yet. Poll and retry.
        if attempt < READ_MAX_RETRIES:
            warn(f"Log not yet visible, retrying in {READ_RETRY_DELAY}s...")
            time.sleep(READ_RETRY_DELAY)

    return False, 0, response_body, nrql, {
        "error": "Unable to query the test log",
        "description": "Please check troubleshooting docs",
    }


# ── Step 5: Update federated logs setup status ────────────────
def update_federated_logs_setup(graphql_url, api_key, setup_id, account_id, status, message):
    now = (
        datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%S.")
        + f"{datetime.datetime.utcnow().microsecond // 1000:03d}Z"
    )

    mutation = (
        'mutation {\n'
        '  federatedLogsUpdateSetup(\n'
        '    id: "%s"\n'
        '    accountId: %s\n'
        '    setup: {healthCheck: {end2endDataFlow: {status: %s, message: %s, lastUpdatedAt: "%s"}}}\n'
        '  ) {\n'
        '    setup {\n'
        '      id\n'
        '    }\n'
        '  }\n'
        '}'
    ) % (setup_id, account_id, status, json.dumps(message), now)

    headers = {
        "Content-Type": "application/json",
        "API-Key": api_key,
    }

    info("")
    info("Step 5: Updating federated logs setup status...")
    info(f"Status: {status}")

    resp_status, response_body = http_post(graphql_url, headers, {"query": mutation})

    if resp_status == 0:
        warn(f"Connection error when updating setup status: {response_body}")
        return False

    try:
        data = json.loads(response_body)
        gql_errors = data.get("errors", [])
        if gql_errors:
            warn(f"GraphQL error updating setup: {gql_errors[0].get('message', 'Unknown')}")
            return False
    except json.JSONDecodeError:
        warn("Invalid JSON response from setup update")
        return False

    if 200 <= resp_status < 300:
        pass_msg(f"Setup status updated to {status}")
        return True

    warn(f"Failed to update setup status (HTTP {resp_status}): {response_body}")
    return False


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
        default=os.environ.get("NEW_RELIC_LICENSE_KEY", ""),
        help="New Relic license/ingest key",
    )
    parser.add_argument(
        "--nr-account-id",
        default=os.environ.get("NR_ACCOUNT_ID", ""),
        help="New Relic account ID",
    )
    parser.add_argument(
        "--nr-api-key",
        default=os.environ.get("NEW_RELIC_API_KEY", ""),
        help="New Relic User API key for GraphQL queries",
    )
    parser.add_argument(
        "--payload",
        default=os.environ.get("TEST_PAYLOAD", ""),
        help="JSON log payload to send to PCG (required)",
    )
    parser.add_argument(
        "--nr-region",
        default=os.environ.get("NR_REGION", "US"),
        choices=["US", "EU", "STAGING"],
        help="New Relic region (default: US)",
    )
    parser.add_argument(
        "--setup-id",
        default=os.environ.get("NR_FEDERATEDLOGS_SETUP_ID", ""),
        help="Federated logs setup entity GUID for reporting health status",
    )

    args = parser.parse_args()

    # Validate required inputs
    required = {
        "PCG_ENDPOINT / --pcg-endpoint": bool(args.pcg_endpoint),
        "NEW_RELIC_LICENSE_KEY / --license-key": bool(args.license_key),
        "NR_ACCOUNT_ID / --nr-account-id": bool(args.nr_account_id),
        "NEW_RELIC_API_KEY / --nr-api-key": bool(args.nr_api_key),
        "TEST_PAYLOAD / --payload": bool(args.payload),
        "NR_FEDERATEDLOGS_SETUP_ID / --setup-id": bool(args.setup_id),
    }
    missing = [name for name, present in required.items() if not present]
    if missing:
        fail_msg("Missing required inputs:")
        for m in missing:
            print(f"  - {m}")
        sys.exit(1)

    # Parse payload
    try:
        payload = json.loads(args.payload)
    except json.JSONDecodeError:
        fail_msg("--payload is not valid JSON")
        sys.exit(1)

    # Resolve GraphQL endpoint
    graphql_url = os.environ.get("NR_GRAPHQL_URL") or get_graphql_url(args.nr_region)

    # Generate UUID and inject
    test_uuid = str(uuid.uuid4())
    payload["e2e_test_id"] = test_uuid

    info("──────────────────────────────────────────────────")
    info("Federated Logs E2E Test")
    info("──────────────────────────────────────────────────")
    info(f"PCG Endpoint:  {args.pcg_endpoint}")
    info(f"Partition:     Log_federated")
    info(f"Test UUID:     {test_uuid}")
    info(f"NR Account:    {args.nr_account_id}")
    info(f"NR Region:     {args.nr_region}")
    info(f"GraphQL URL:   {graphql_url}")
    info(f"Payload:       {json.dumps(payload)}")
    info(f"Setup ID:      {args.setup_id}")
    info("──────────────────────────────────────────────────")

    # Step 1: Check PCG health
    health_ok, health_error = check_pcg_health(args.pcg_endpoint)
    if not health_ok:
        info("")
        info("──────────────────────────────────────────────────")
        fail_msg("E2E test FAILED")
        info("──────────────────────────────────────────────────")
        update_federated_logs_setup(
            graphql_url, args.nr_api_key, args.setup_id, args.nr_account_id,
            "UNHEALTHY", json.dumps(health_error),
        )
        sys.exit(1)

    # Step 2: Send to PCG
    send_ok, send_error = send_to_pcg(args.pcg_endpoint, args.license_key, payload)
    if not send_ok:
        info("")
        info("──────────────────────────────────────────────────")
        fail_msg("E2E test FAILED")
        info("──────────────────────────────────────────────────")
        update_federated_logs_setup(
            graphql_url, args.nr_api_key, args.setup_id, args.nr_account_id,
            "UNHEALTHY", json.dumps(send_error),
        )
        sys.exit(1)

    # Step 3: Wait for ingestion
    info("")
    info(f"Step 3: Waiting {INITIAL_READ_WAIT}s for log ingestion...")
    time.sleep(INITIAL_READ_WAIT)

    # Step 4: Query New Relic
    success, count, last_response, nrql, read_error = query_new_relic(
        args.nr_account_id, args.nr_api_key, "Log_federated", test_uuid, graphql_url
    )

    # Results
    info("")
    info("──────────────────────────────────────────────────")
    if success:
        pass_msg("E2E test PASSED")
        pass_msg(f"Test log with UUID {test_uuid} found in New Relic (count: {count})")
        info("──────────────────────────────────────────────────")
        success_message = json.dumps({"nrql": nrql, "response": last_response})
        update_federated_logs_setup(
            graphql_url, args.nr_api_key, args.setup_id, args.nr_account_id,
            "HEALTHY", success_message,
        )
        sys.exit(0)
    else:
        fail_msg("E2E test FAILED")
        fail_msg(
            f"Test log with UUID {test_uuid} not found in New Relic"
        )
        info(f"Last API response: {last_response}")
        info("──────────────────────────────────────────────────")
        update_federated_logs_setup(
            graphql_url, args.nr_api_key, args.setup_id, args.nr_account_id,
            "UNHEALTHY", json.dumps(read_error),
        )
        sys.exit(1)


if __name__ == "__main__":
    main()
