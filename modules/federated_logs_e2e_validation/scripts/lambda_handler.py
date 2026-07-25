"""
Lambda entry point for the federated-logs E2E validation.
"""
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
    # ── Resolve secret ARNs from env ────────────────────────────
    try:
        license_key_secret_arn = os.environ["LICENSE_KEY_SECRET_ARN"]
        api_key_secret_arn = os.environ["API_KEY_SECRET_ARN"]
    except KeyError as e:
        return {
            "status": "FAIL",
            "exit_code": 1,
            "error": f"Missing required env var: {e}",
            "stdout": "",
            "stderr": "",
        }

    # ── Fetch credentials from Secrets Manager ──────────────────
    try:
        license_key = get_secret(license_key_secret_arn)
        api_key = get_secret(api_key_secret_arn)
    except ClientError as e:
        return {
            "status": "FAIL",
            "exit_code": 1,
            "error": f"Failed to read secret from Secrets Manager: {e.response['Error']['Code']}",
            "stdout": "",
            "stderr": "",
        }

    # ── Build environment for the script ────────────────────────
    env = os.environ.copy()
    env["NEW_RELIC_LICENSE_KEY"] = license_key
    env["NEW_RELIC_API_KEY"] = api_key

    if isinstance(event, dict) and event.get("test_payload"):
        env["TEST_PAYLOAD"] = str(event["test_payload"])

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
