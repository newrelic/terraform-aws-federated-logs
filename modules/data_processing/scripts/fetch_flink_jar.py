"""Download the flink-iceberg-commit-worker JAR and check its sha256.

Run by null_resource.flink_jar_fetch (flink-jar.tf) with:
  FLINK_JAR_URL     URL of the JAR
  FLINK_JAR_DEST    local path to write it to
  FLINK_JAR_SHA256  expected sha256, or "" for a version this module release has
                    no hash for ("latest", an override), which is not checked

On a sha256 mismatch the file is deleted and the script exits non-zero, so the
apply fails before anything is uploaded.
"""

import hashlib
import os
import pathlib
import socket
import sys
import time
import urllib.error
import urllib.request

MAX_ATTEMPTS = 3
RETRY_DELAY_SECONDS = 5
SOCKET_TIMEOUT_SECONDS = 60


def sha256_of(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def verify(url, dest, expected_sha256):
    if not expected_sha256:
        return
    actual = sha256_of(dest)
    if actual != expected_sha256:
        dest.unlink()
        sys.exit(f"ERROR: {url} has sha256 {actual}, expected {expected_sha256}. Not deploying it.")


def fetch(url, dest, expected_sha256):
    dest.parent.mkdir(parents=True, exist_ok=True)
    for attempt in range(MAX_ATTEMPTS):
        try:
            urllib.request.urlretrieve(url, dest)
            if not dest.exists():
                raise RuntimeError("Downloaded file does not exist")
            if dest.stat().st_size > 0:
                verify(url, dest, expected_sha256)
                return
            raise RuntimeError("Downloaded file is empty")
        except urllib.error.HTTPError as e:
            if e.code < 500:
                sys.exit(f"ERROR: {url} returned HTTP {e.code} (not retryable)")
            error = f"HTTP {e.code}"
        except urllib.error.URLError as e:
            error = e.reason
        except Exception as e:
            error = e
        if attempt < MAX_ATTEMPTS - 1:
            time.sleep(RETRY_DELAY_SECONDS)
    sys.exit(f"ERROR: Failed to download {url} after {MAX_ATTEMPTS} attempts: {error}")


def main():
    socket.setdefaulttimeout(SOCKET_TIMEOUT_SECONDS)
    fetch(
        os.environ["FLINK_JAR_URL"],
        pathlib.Path(os.environ["FLINK_JAR_DEST"]),
        os.environ["FLINK_JAR_SHA256"],
    )


if __name__ == "__main__":
    main()
