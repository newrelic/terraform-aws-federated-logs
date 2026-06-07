#!/usr/bin/env python3
"""
Download Flink JAR from source URL and upload to S3 bucket.

Cross-platform script (Linux, macOS, Windows) using only Python standard library.
Uses AWS Signature V4 for S3 upload - no boto3 or AWS CLI required.

Environment variables (required):
    SOURCE_URL:   HTTPS URL to download the JAR from
    DEST_BUCKET:  S3 bucket name to upload to
    DEST_KEY:     S3 object key for the uploaded JAR
    DEST_REGION:  AWS region for the destination bucket

AWS credentials (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_SESSION_TOKEN) are
automatically available from the Terraform execution environment.
"""

import hashlib
import hmac
import json
import os
import sys
import tempfile
import urllib.request
import urllib.error
from datetime import datetime, timezone


def sha256_hash(data):
    """Return SHA256 hash of data as hex string."""
    if isinstance(data, str):
        data = data.encode("utf-8")
    return hashlib.sha256(data).hexdigest()


def sha256_hash_file(filepath):
    """Return SHA256 hash of file contents as hex string."""
    h = hashlib.sha256()
    with open(filepath, "rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            h.update(chunk)
    return h.hexdigest()


def hmac_sha256(key, msg):
    """Return HMAC-SHA256 of msg using key."""
    if isinstance(key, str):
        key = key.encode("utf-8")
    if isinstance(msg, str):
        msg = msg.encode("utf-8")
    return hmac.new(key, msg, hashlib.sha256).digest()


def get_signature_key(secret_key, date_stamp, region, service):
    """Derive the signing key for AWS Signature V4."""
    k_date = hmac_sha256(("AWS4" + secret_key).encode("utf-8"), date_stamp)
    k_region = hmac_sha256(k_date, region)
    k_service = hmac_sha256(k_region, service)
    k_signing = hmac_sha256(k_service, "aws4_request")
    return k_signing


def upload_to_s3(filepath, bucket, key, region, content_type="application/java-archive"):
    """
    Upload a file to S3 using AWS Signature V4 (stdlib only).

    Uses PUT request with proper AWS authentication headers.
    """
    # Get AWS credentials from environment (always available in Terraform execution)
    access_key = os.environ["AWS_ACCESS_KEY_ID"]
    secret_key = os.environ["AWS_SECRET_ACCESS_KEY"]
    session_token = os.environ.get("AWS_SESSION_TOKEN", "")

    # S3 endpoint
    host = f"{bucket}.s3.{region}.amazonaws.com"
    endpoint = f"https://{host}/{key}"

    # Timestamps
    t = datetime.now(timezone.utc)
    amz_date = t.strftime("%Y%m%dT%H%M%SZ")
    date_stamp = t.strftime("%Y%m%d")

    # Read file and compute hash
    with open(filepath, "rb") as f:
        file_content = f.read()
    payload_hash = sha256_hash(file_content)

    # Canonical headers
    canonical_headers = f"content-type:{content_type}\n"
    canonical_headers += f"host:{host}\n"
    canonical_headers += f"x-amz-content-sha256:{payload_hash}\n"
    canonical_headers += f"x-amz-date:{amz_date}\n"
    if session_token:
        canonical_headers += f"x-amz-security-token:{session_token}\n"

    signed_headers = "content-type;host;x-amz-content-sha256;x-amz-date"
    if session_token:
        signed_headers += ";x-amz-security-token"

    # Canonical request
    canonical_request = f"PUT\n/{key}\n\n{canonical_headers}\n{signed_headers}\n{payload_hash}"

    # String to sign
    algorithm = "AWS4-HMAC-SHA256"
    credential_scope = f"{date_stamp}/{region}/s3/aws4_request"
    string_to_sign = f"{algorithm}\n{amz_date}\n{credential_scope}\n{sha256_hash(canonical_request)}"

    # Signing key and signature
    signing_key = get_signature_key(secret_key, date_stamp, region, "s3")
    signature = hmac.new(signing_key, string_to_sign.encode("utf-8"), hashlib.sha256).hexdigest()

    # Authorization header
    authorization = (
        f"{algorithm} "
        f"Credential={access_key}/{credential_scope}, "
        f"SignedHeaders={signed_headers}, "
        f"Signature={signature}"
    )

    # Build request headers
    headers = {
        "Content-Type": content_type,
        "Host": host,
        "x-amz-content-sha256": payload_hash,
        "x-amz-date": amz_date,
        "Authorization": authorization,
    }
    if session_token:
        headers["x-amz-security-token"] = session_token

    # Make PUT request
    req = urllib.request.Request(endpoint, data=file_content, headers=headers, method="PUT")

    try:
        response = urllib.request.urlopen(req)
        return response.status
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        raise Exception(f"S3 upload failed: HTTP {e.code} {e.reason}\n{body}")


def download_file(url, dest_path):
    """Download file from URL to destination path."""
    urllib.request.urlretrieve(url, dest_path)
    return os.path.getsize(dest_path)


def main():
    # Required environment variables
    source_url = os.environ.get("SOURCE_URL")
    dest_bucket = os.environ.get("DEST_BUCKET")
    dest_key = os.environ.get("DEST_KEY")
    dest_region = os.environ.get("DEST_REGION")
    content_type = os.environ.get("CONTENT_TYPE", "application/java-archive")

    if not all([source_url, dest_bucket, dest_key, dest_region]):
        print("Error: SOURCE_URL, DEST_BUCKET, DEST_KEY, and DEST_REGION are required", file=sys.stderr)
        sys.exit(1)

    temp_file = None
    try:
        # Create temp file
        fd, temp_file = tempfile.mkstemp(suffix=".jar")
        os.close(fd)

        # Download JAR via HTTPS
        print(f"Downloading JAR from {source_url}...")
        file_size = download_file(source_url, temp_file)
        print(f"Downloaded {file_size / (1024 * 1024):.2f} MB")

        # Upload to S3 using AWS Signature V4
        s3_uri = f"s3://{dest_bucket}/{dest_key}"
        print(f"Uploading JAR to {s3_uri}...")
        upload_to_s3(temp_file, dest_bucket, dest_key, dest_region, content_type)
        print("JAR copy completed successfully.")

    except urllib.error.HTTPError as e:
        print(f"Error downloading JAR: HTTP {e.code} - {e.reason}", file=sys.stderr)
        sys.exit(1)
    except urllib.error.URLError as e:
        print(f"Error downloading JAR: {e.reason}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
    finally:
        # Cleanup temp file
        if temp_file and os.path.exists(temp_file):
            os.remove(temp_file)


if __name__ == "__main__":
    main()
