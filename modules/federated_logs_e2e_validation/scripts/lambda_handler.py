"""
Lambda entry point for the federated-logs E2E validation.
"""
import json
import os
import subprocess
import sys
import boto3
from botocore.exceptions import ClientError


def get_secret(secret_arn):
    """Fetch a secret value from Secrets Manager. Raises ClientError on miss."""
    client = boto3.client("secretsmanager")
    response = client.get_secret_value(SecretId=secret_arn)
    return response.get("SecretString", "")


def handler(event, context):
    # ── Fetch credentials from Secrets Manager ──────────────────
    try:
        license_key = get_secret(event["license_key_secret_arn"])
        api_key = get_secret(event["api_key_secret_arn"])
    except ClientError as e:
        return {
            "status": "FAIL",
            "exit_code": 1,
            "error": f"Failed to read secret from Secrets Manager: {e.response['Error']['Code']}",
            "stdout": "",
            "stderr": "",
        }
    except KeyError as e:
        return {
            "status": "FAIL",
            "exit_code": 1,
            "error": f"Missing required event field: {e}",
            "stdout": "",
            "stderr": "",
        }

    # ── Build environment for the script ────────────────────────
    env = os.environ.copy()
    env["PCG_ENDPOINT"] = str(event["pcg_endpoint"])
    env["NR_ACCOUNT_ID"] = str(event["nr_account_id"])
    env["NR_REGION"] = str(event.get("nr_region", "US"))
    env["NR_FEDERATEDLOGS_SETUP_ID"] = str(event["setup_id"])
    env["TEST_PAYLOAD"] = str(event.get("test_payload", '{"message":"federated-logs e2e test","level":"info"}'))
    env["NEW_RELIC_LICENSE_KEY"] = license_key
    env["NEW_RELIC_API_KEY"] = api_key

    # Optional retry/poll knobs (script defaults apply when absent)
    for tf_field, env_var in [
        ("max_retries",       "E2E_MAX_RETRIES"),
        ("retry_delay",       "E2E_RETRY_DELAY"),
        ("initial_read_wait", "E2E_INITIAL_READ_WAIT"),
        ("read_max_retries",  "E2E_READ_MAX_RETRIES"),
        ("read_retry_delay",  "E2E_READ_RETRY_DELAY"),
    ]:
        if tf_field in event:
            env[env_var] = str(event[tf_field])

    # ── Run the CLI script ──────────────────────────────────────
    script_path = os.path.join(os.path.dirname(__file__), "e2e_test.py")
    try:
        result = subprocess.run(
            ["python3", script_path],
            env=env,
            capture_output=True,
            text=True,
            # Lambda timeout is enforced externally; we still bound subprocess.
            timeout=context.get_remaining_time_in_millis() / 1000.0 - 5
            if context else 600,
        )
    except subprocess.TimeoutExpired:
        return {
            "status": "FAIL",
            "exit_code": 124,
            "error": "e2e_test.py exceeded Lambda time budget",
            "stdout": "",
            "stderr": "",
        }

    # Surface the child script's output to CloudWatch (blocking run, so this
    # appears once the script finishes; the payload still carries it too).
    if result.stdout:
        print(result.stdout)
    if result.stderr:
        print(result.stderr, file=sys.stderr)

    return {
        "status": "PASS" if result.returncode == 0 else "FAIL",
        "exit_code": result.returncode,
        "stdout": result.stdout,
        "stderr": result.stderr,
    }
