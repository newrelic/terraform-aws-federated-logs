# federated_logs_e2e_validation

Independent, optional module that verifies the full write + read path of a New Relic Federated Logs setup.

It wraps `scripts/e2e_test.py`, which runs the following steps:

1. **Health check** — `GET <pcg_endpoint>/health/status` and asserts `{"healthy": true}`.
2. **Write** — POSTs a test log payload (with a unique `e2e_test_id` UUID) to `<pcg_endpoint>/v1/logs`.
3. **Wait** — pauses for PCG buffering + downstream ingestion.
4. **Read** — polls NRQL via the New Relic GraphQL API until the UUID appears (or retries are exhausted).
5. **Report** — calls the `federatedLogsUpdateSetup` GraphQL mutation to set the setup health status to `HEALTHY` (with the NRQL query and matched log as the message) or `UNHEALTHY` (with a structured error object). This step is skipped when `setup_id` is empty.

On any failure the script returns a structured error object:

```json
{ "error": "<short reason>", "description": "<remediation hint>" }
```

A `[PASS]`/`[FAIL]` line is printed to the local-exec stdout. **Failure of the check does not fail `terraform apply`** — the provisioner uses `on_failure = continue` so the deploy proceeds either way and the operator can inspect output.

## Prerequisites

- `python3` on the Terraform runner (stdlib only — no `pip install`).
- Network reachability from the runner to:
  - The PCG endpoint.
  - `api.newrelic.com` or `api.eu.newrelic.com` (depending on `nr_region`).
- The following environment variables set on the runner (not Terraform variables — kept out of state):
  - `NEWRELIC_LICENSE_KEY` — New Relic license/ingest key routed to the target account.
  - `NEWRELIC_API_KEY` — New Relic User API key (`NRAK-...`) with NRQL query permission.

## Two ways to use

### 1. As a Terraform module

Wired under the root module behind an opt-in flag so existing deploys are unaffected:

```hcl
module "federated_logs" {
  source = "git::https://github.com/newrelic/terraform-aws-federated-logs.git?ref=v1.x.x"

  setup_name = "my-app-logs"
  clusters   = { ... }

  e2e_validation_config = {
    enabled       = true
    pcg_endpoint  = "https://pcg.example.com"
    nr_account_id = "1234567"
    # nr_region   = "us"  # or "eu"
  }
}
```

Credentials are read automatically from `NEWRELIC_LICENSE_KEY` and `NEWRELIC_API_KEY` in the runner environment.

The null_resource is triggered on every apply (via `timestamp()`) so the write/read path is re-verified each deploy.

### 2. Standalone (for manual runs)

The script is pure stdlib — run it straight from the module path:

```bash
export NEWRELIC_LICENSE_KEY="INGEST-KEY-..."
export NEWRELIC_API_KEY="NRAK-..."

python3 modules/federated_logs_e2e_validation/scripts/e2e_test.py \
  --pcg-endpoint  "https://pcg.example.com" \
  --nr-account-id "1234567" \
  --nr-api-key    "$NEWRELIC_API_KEY"
```

All flags also accept environment variables: `PCG_ENDPOINT`, `NR_ACCOUNT_ID`, `NR_REGION`. The script also honors `NR_FEDERATEDLOGS_SETUP_ID`, `NR_STAGING`, `NR_GRAPHQL_URL`, `TEST_PAYLOAD`, and retry-tuning vars (`E2E_WRITE_MAX_RETRIES`, `E2E_WRITE_RETRY_DELAY`, `E2E_READ_MAX_RETRIES`, `E2E_READ_RETRY_DELAY`, `E2E_INITIAL_READ_WAIT`) for ad-hoc debugging runs.

Exit code is `0` on PASS, `1` on FAIL.

## Inputs

| Name | Description | Type | Required | Default |
|------|-------------|------|----------|---------|
| `pcg_endpoint` | PCG base URL (the script appends `/health/status` and `/v1/logs` automatically). | `string` | yes | – |
| `nr_account_id` | New Relic account ID for the NRQL read-back. | `string` | yes | – |
| `nr_region` | `us` or `eu`. | `string` | no | `"us"` |
| `setup_id` | Federated logs setup entity GUID. When set, the script calls `federatedLogsUpdateSetup` to report `HEALTHY`/`UNHEALTHY` status. | `string` | no | `""` |

> **Credentials** (`NEWRELIC_LICENSE_KEY`, `NEWRELIC_API_KEY`) are read from the runner environment — not Terraform inputs — to keep them out of Terraform state.

## Outputs

| Name | Description |
|------|-------------|
| `validation_id` | null_resource id of the run. Stdout above shows PASS/FAIL + UUID. |
| `script_path` | Filesystem path to `e2e_test.py` for manual invocation. |

## Test case matrix

| # | Scenario | Error (if any) | Exit |
|---|----------|----------------|------|
| 1 | Happy path: health OK, write accepted, UUID found in NR | – | 0 |
| 2 | PCG health check returns `{"healthy": false}` | `PCG is not reachable` | 1 |
| 3 | PCG write returns 401 or 403 | `License key configured in PCG is either invalid or expired` | 1 |
| 4 | PCG write fails with other error (after retries) | `Error sending log to PCG` | 1 |
| 5 | Write retries transiently then succeeds, UUID found in NR | `[WARN]` on failed attempts, `[PASS]` overall | 0 |
| 6 | Write accepted, NR read-back retries then finds UUID | `[WARN]` on empty attempts, `[PASS]` overall | 0 |
| 7 | Write accepted, UUID never appears in NRQL | `Unable to query the test log` | 1 |
| 8 | Missing required inputs | `[FAIL] Missing required inputs:` | 1 |
| 9 | Malformed `TEST_PAYLOAD` | `[FAIL] --payload is not valid JSON` | 1 |

When `setup_id` is provided, the `federatedLogsUpdateSetup` mutation is called after every outcome — `HEALTHY` on pass, `UNHEALTHY` with the error object on any failure.

In Terraform, exit `1` is swallowed by `on_failure = continue` — the apply is unaffected; the PASS/FAIL is visible in the provisioner output.

## Notes

- Credentials are passed through the runner environment (not Terraform `environment {}`) to avoid leaking into Terraform state or command-line logs.
- The `triggers = { always_run = timestamp() }` means this null_resource always shows a change in plan when enabled. That is intentional — the point is to re-verify the path on every apply.
- The partition queried is always `Log_Federated` (hardcoded in the script).

