"""Unit tests for modules/federated_logs_partition/scripts/tagging_job.py.

Run with: python3 -m pytest tests/python

awsglue only exists on the Glue runtime and pyiceberg is not a repo
dependency, so both are stubbed when not importable. The fake catalog
commits on manage_snapshots().__exit__, matching pyiceberg, so a
CommitFailedException surfaces from the `with` block as it does live.
"""

import importlib.util
import pathlib
import sys
import types
from types import SimpleNamespace

import pytest

SCRIPT = (
    pathlib.Path(__file__).resolve().parents[2]
    / "modules/federated_logs_partition/scripts/tagging_job.py"
)


def _stub(name, **attrs):
    module = types.ModuleType(name)
    module.__dict__.update(attrs)
    sys.modules[name] = module


_stub("awsglue")
_stub("awsglue.utils", getResolvedOptions=None)
try:
    from pyiceberg.exceptions import CommitFailedException
    import pyiceberg.catalog.glue  # noqa: F401
except ImportError:
    class CommitFailedException(Exception):
        pass

    _stub("pyiceberg")
    _stub("pyiceberg.catalog")
    _stub("pyiceberg.catalog.glue", GlueCatalog=None)
    _stub("pyiceberg.exceptions", CommitFailedException=CommitFailedException)

_spec = importlib.util.spec_from_file_location("tagging_job", SCRIPT)
tagging_job = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(tagging_job)
Status = tagging_job.Status

TAG = "backup-2026-10-07T01"
RETAIN_MS = 15 * 24 * 60 * 60 * 1000


class FakeCatalog:
    """One table's worth of state; load_table returns a fresh handle each call."""

    def __init__(self, snapshot_id=101, refs=None, commit_failures=0):
        self.snapshot_id = snapshot_id
        self.refs = dict(refs or {})
        self.commit_failures = commit_failures
        self.load_calls = 0
        self.commits = []

    def load_table(self, identifier):
        self.load_calls += 1
        return FakeTable(self)


class FakeTable:
    def __init__(self, catalog):
        self._catalog = catalog

    def refs(self):
        return dict(self._catalog.refs)

    def current_snapshot(self):
        if self._catalog.snapshot_id is None:
            return None
        return SimpleNamespace(snapshot_id=self._catalog.snapshot_id)

    def manage_snapshots(self):
        return FakeManageSnapshots(self._catalog)


class FakeManageSnapshots:
    def __init__(self, catalog):
        self._catalog = catalog
        self._pending = None

    def __enter__(self):
        return self

    def create_tag(self, snapshot_id, tag_name, max_ref_age_ms=None):
        self._pending = (snapshot_id, tag_name, max_ref_age_ms)

    def __exit__(self, exc_type, exc, tb):
        if exc_type is not None:
            return False
        if self._catalog.commit_failures > 0:
            self._catalog.commit_failures -= 1
            raise CommitFailedException("requirement failed: branch main has changed")
        snapshot_id, tag_name, _ = self._pending
        self._catalog.refs[tag_name] = snapshot_id
        self._catalog.commits.append(self._pending)
        return False


@pytest.fixture(autouse=True)
def no_sleep(monkeypatch):
    monkeypatch.setattr(tagging_job.time, "sleep", lambda _: None)


def test_retries_commit_conflicts_with_a_fresh_table_each_attempt():
    catalog = FakeCatalog(commit_failures=2)

    status, _ = tagging_job.tag_current_snapshot(catalog, "db.t", TAG, RETAIN_MS)

    assert status is Status.SUCCESS
    assert catalog.load_calls == 3
    assert catalog.commits == [(101, TAG, RETAIN_MS)]


def test_reraises_after_last_attempt():
    catalog = FakeCatalog(commit_failures=tagging_job.COMMIT_ATTEMPTS)

    with pytest.raises(CommitFailedException):
        tagging_job.tag_current_snapshot(catalog, "db.t", TAG, RETAIN_MS)

    assert catalog.load_calls == tagging_job.COMMIT_ATTEMPTS
    assert catalog.commits == []


def test_skips_without_committing_when_tag_already_exists():
    catalog = FakeCatalog(refs={TAG: 99})

    status, _ = tagging_job.tag_current_snapshot(catalog, "db.t", TAG, RETAIN_MS)

    assert status is Status.SKIPPED
    assert catalog.commits == []
    assert catalog.refs[TAG] == 99  # not repointed to the current snapshot


def test_skips_tag_created_concurrently_during_backoff():
    catalog = FakeCatalog(commit_failures=1)
    original_load = catalog.load_table

    def load_table(identifier):
        # A concurrent run wins the race between our first and second attempt.
        if catalog.load_calls == 1:
            catalog.refs[TAG] = 99
        return original_load(identifier)

    catalog.load_table = load_table

    status, _ = tagging_job.tag_current_snapshot(catalog, "db.t", TAG, RETAIN_MS)

    assert status is Status.SKIPPED
    assert catalog.commits == []


def test_skips_table_with_no_snapshot():
    catalog = FakeCatalog(snapshot_id=None)

    status, _ = tagging_job.tag_current_snapshot(catalog, "db.t", TAG, RETAIN_MS)

    assert status is Status.SKIPPED
    assert catalog.commits == []


def _run_main(monkeypatch, catalog):
    monkeypatch.setattr(
        tagging_job,
        "getResolvedOptions",
        lambda argv, keys: {
            "DATABASE_NAME": "db",
            "TABLE_TAG_CONFIG": '{"good": {"retain_days": 15}, "bad": {"retain_days": 15}}',
            "WAREHOUSE_PATH": "s3://bucket/warehouse/",
        },
    )
    monkeypatch.setattr(tagging_job, "GlueCatalog", lambda *a, **kw: catalog)
    tagging_job.main()


def test_main_exits_nonzero_when_any_table_errors(monkeypatch, capsys):
    catalog = FakeCatalog()
    original_load = catalog.load_table

    def load_table(identifier):
        if identifier == "db.bad":
            raise KeyError("boom")
        return original_load(identifier)

    catalog.load_table = load_table

    with pytest.raises(SystemExit) as exit_info:
        _run_main(monkeypatch, catalog)

    assert exit_info.value.code == 1
    out = capsys.readouterr().out
    assert "Traceback" in out  # traceback logged, not just str(e)
    assert len(catalog.commits) == 1  # the good table was still tagged


def test_main_exits_zero_when_tables_succeed_or_skip(monkeypatch):
    catalog = FakeCatalog()

    _run_main(monkeypatch, catalog)  # second table finds the tag and skips

    assert len(catalog.commits) == 1
