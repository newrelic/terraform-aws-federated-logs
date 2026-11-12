"""Tests for modules/data_processing/scripts/fetch_flink_jar.py.

Run with: python3 -m pytest tests/python

Each test runs the script the way null_resource.flink_jar_fetch does, with the
JAR served from a file:// URL so no network is needed.
"""

import hashlib
import os
import pathlib
import subprocess
import sys

SCRIPT = (
    pathlib.Path(__file__).resolve().parents[2]
    / "modules/data_processing/scripts/fetch_flink_jar.py"
)

JAR = b"PK\x03\x04 stand-in for the commit worker JAR"
JAR_SHA256 = hashlib.sha256(JAR).hexdigest()


def run_fetch(tmp_path, served_bytes, expected_sha256):
    source = tmp_path / "source.jar"
    source.write_bytes(served_bytes)
    dest = tmp_path / "tmp" / "flink-iceberg-commit-worker.jar"
    result = subprocess.run(
        [sys.executable, str(SCRIPT)],
        env={
            **os.environ,
            "FLINK_JAR_URL": source.as_uri(),
            "FLINK_JAR_DEST": str(dest),
            "FLINK_JAR_SHA256": expected_sha256,
        },
        capture_output=True,
        text=True,
        timeout=60,
    )
    return result, dest


def test_matching_sha256_keeps_the_jar(tmp_path):
    result, dest = run_fetch(tmp_path, JAR, JAR_SHA256)

    assert result.returncode == 0, result.stderr
    assert dest.read_bytes() == JAR


# A swapped, republished or truncated JAR must fail the apply and leave nothing
# behind for aws_s3_object.flink_jar to upload.
def test_mismatch_exits_non_zero_and_deletes_the_jar(tmp_path):
    result, dest = run_fetch(tmp_path, JAR[:-1], JAR_SHA256)

    assert result.returncode != 0
    assert f"expected {JAR_SHA256}" in result.stderr
    assert not dest.exists()


# "latest" and overrides have no known sha256; they are deployed unchecked
# (the flink_jar_version_pinned check warns about it at plan time).
def test_empty_sha256_skips_the_check(tmp_path):
    result, dest = run_fetch(tmp_path, b"any bytes", "")

    assert result.returncode == 0, result.stderr
    assert dest.read_bytes() == b"any bytes"
