# federated_logs_e2e_validation

Independent, optional module that verifies the full write + read path of a New Relic Federated Logs setup.

It wraps `scripts/e2e_test.py`, which:

1. POSTs a test log payload (with a unique `e2e_test_id` UUID) to the PCG ingest endpoint.
2. Waits for PCG buffering + downstream ingestion.
3. Polls NRQL via the New Relic GraphQL API for the UUID until it appears (or retries are exhausted).

A `[PASS]`/`[FAIL]` line is printed to the local-exec stdout. **Failure of the check does not fail `terraform apply`** — the provisioner uses `on_failure = continue` so the deploy proceeds either way and the operator can inspect output.

## Prerequisites

- `python3` on the Terraform runner (stdlib only — no `pip install`).
- Network reachability from the runner to:
  - The PCG endpoint.
  - `api.newrelic.com` or `api.eu.newrelic.com` (depending on `nr_region`).
- A user API key (`NRAK-...`) with permission to run NRQL for the target account.
- A license/ingest key routed to the same account and partition table.

## Two ways to use

### 1. As a Terraform module

Wired under the root module behind an opt-in flag so existing deploys are unaffected:

```hcl
module "federated_logs" {
  source = "git::https://github.com/newrelic/terraform-aws-federated-logs.git?ref=v1.x.x"

  setup_name = "my-app-logs"
  clusters   = { ... }

  e2e_validation_config = {
    enabled        = true
    pcg_endpoint   = "https://pcg.example.com/v1/logs"
    partition_name = "application_log"
    nr_account_id  = "1234567"
    # nr_region    = "us"  # or "eu"
  }

  # Credentials live in dedicated sensitive variables
  e2e_license_key = var.nr_license_key
  e2e_nr_api_key  = var.nr_user_api_key
}
```

The null_resource is triggered on every apply (via `timestamp()`) so the write/read path is re-verified each deploy.

### 2. Standalone (for manual setups)

The script is pure stdlib — copy it anywhere or run it straight from the module path:

```bash
python3 modules/federated_logs_e2e_validation/scripts/e2e_test.py \
  --pcg-endpoint  "https://pcg.example.com/v1/logs" \
  --license-key   "INGEST-KEY-..." \
  --partition     "application_log" \
  --nr-account-id "1234567" \
  --nr-api-key    "NRAK-..."
```

All flags also accept environment variables: `PCG_ENDPOINT`, `NR_LICENSE_KEY`, `PARTITION_NAME`, `NR_ACCOUNT_ID`, `NR_API_KEY`, `NR_REGION`. The script also honors `NR_STAGING`, `NR_GRAPHQL_URL`, `TEST_PAYLOAD`, and retry-tuning vars (`E2E_WRITE_MAX_RETRIES`, `E2E_WRITE_RETRY_DELAY`, `E2E_READ_MAX_RETRIES`, `E2E_READ_RETRY_DELAY`, `E2E_INITIAL_READ_WAIT`) for ad-hoc debugging runs.

Exit code is `0` on PASS, `1` on FAIL.

## Inputs

| Name | Description | Type | Required | Default |
|------|-------------|------|----------|---------|
| `pcg_endpoint` | PCG ingest endpoint URL. | `string` | yes | – |
| `license_key` | New Relic license/ingest key. Sensitive. | `string` | yes | – |
| `partition_name` | Target Iceberg partition table name. | `string` | yes | – |
| `nr_account_id` | New Relic account ID for the NRQL read-back. | `string` | yes | – |
| `nr_api_key` | New Relic User API key (NRAK-...). Sensitive. | `string` | yes | – |
| `nr_region` | `us` or `eu`. | `string` | no | `"us"` |

## Outputs

| Name | Description |
|------|-------------|
| `validation_id` | null_resource id of the run. Stdout above shows PASS/FAIL + UUID. |
| `script_path` | Filesystem path to `e2e_test.py` for manual invocation. |

## Test case matrix

Scenarios the script is designed to behave correctly in:

| # | Scenario | Expected | Exit |
|---|---------|----------|------|
| 1 | Happy path: PCG accepts write, NR returns the UUID within retry budget | `[PASS] E2E test PASSED` | 0 |
| 2 | PCG write fails transiently, then succeeds | `[WARN]` on failed attempts, `[PASS]` overall | 0 |
| 3 | PCG write fails permanently (e.g., 401 / 403 / bad key) | `[FAIL] Failed to send payload ... after N attempts` | 1 |
| 4 | PCG accepts write, NR read-back retries and eventually finds the UUID | `[WARN]` on empty attempts, `[PASS]` overall | 0 |
| 5 | PCG accepts write, UUID never shows up in NRQL (read side broken) | `[FAIL] Test log ... not found after N attempts` | 1 |
| 6 | Missing required inputs | `[FAIL] Missing required inputs:` | 1 |
| 7 | Malformed `TEST_PAYLOAD` | `[FAIL] --payload is not valid JSON` | 1 |

In Terraform, exit `1` is swallowed by `on_failure = continue` — the apply is unaffected; the PASS/FAIL is visible in the provisioner output.

## Notes

- Secrets (`license_key`, `nr_api_key`) are passed through `environment {}` to avoid leaking into Terraform's command-line logs.
- The `triggers = { always_run = timestamp() }` means this null_resource always shows a change in plan when enabled. That's intentional — the point is to re-verify the path on every apply.
