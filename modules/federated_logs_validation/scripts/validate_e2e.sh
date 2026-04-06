#!/usr/bin/env bash
set -euo pipefail

#
# End-to-end validation for federated logs pipeline.
# Writes a test log to S3, then polls New Relic NerdGraph until
# the log is queryable — or times out.
#
# Required env vars (set by Terraform provisioner):
#   S3_BUCKET, GLUE_DB_NAME, NR_ACCOUNT_ID, NR_USER_API_KEY
# Optional:
#   NR_REGION (US|EU, default US), MAX_WAIT_SECONDS (default 300),
#   POLL_INTERVAL_SECS (default 15), RUN_ID (auto-generated if empty)
#

: "${S3_BUCKET:?S3_BUCKET is required}"
: "${GLUE_DB_NAME:?GLUE_DB_NAME is required}"
: "${NR_ACCOUNT_ID:?NR_ACCOUNT_ID is required}"
: "${NR_USER_API_KEY:?NR_USER_API_KEY is required}"

NR_REGION="${NR_REGION:-US}"
MAX_WAIT_SECONDS="${MAX_WAIT_SECONDS:-300}"
POLL_INTERVAL_SECS="${POLL_INTERVAL_SECS:-15}"
RUN_ID="${RUN_ID:-$(date +%s)-$$}"

if [[ "${NR_REGION}" == "EU" ]]; then
  NR_ENDPOINT="https://api.eu.newrelic.com/graphql"
else
  NR_ENDPOINT="https://api.newrelic.com/graphql"
fi

for cmd in aws jq curl; do
  command -v "$cmd" >/dev/null || { echo "ERROR: $cmd not found in PATH"; exit 1; }
done

MARKER="fed-logs-validate-${RUN_ID}"
TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
TMPFILE="$(mktemp)"

trap 'rm -f "$TMPFILE"' EXIT

# --- Step 1: Write test log to S3 ---
cat > "$TMPFILE" <<EOF
{"timestamp":"${TIMESTAMP}","message":"${MARKER}","logtype":"validation","service":"terraform-validation","level":"INFO"}
EOF

S3_KEY="${GLUE_DB_NAME}/validation/validation-${RUN_ID}.json"

echo "==> [Step 1/3] Uploading test log to s3://${S3_BUCKET}/${S3_KEY}"
aws s3 cp "$TMPFILE" "s3://${S3_BUCKET}/${S3_KEY}" --content-type "application/json"
echo "    Upload complete."

# --- Step 2: Verify object landed in S3 ---
echo "==> [Step 2/3] Verifying S3 object exists"
if aws s3api head-object --bucket "${S3_BUCKET}" --key "${S3_KEY}" > /dev/null 2>&1; then
  echo "    S3 object verified."
else
  echo "FAIL: S3 object not found after upload."
  exit 1
fi

# --- Step 3: Poll New Relic for the marker ---
NRQL="SELECT count(*) AS c FROM Log WHERE message = '${MARKER}' SINCE 30 minutes ago"

# Build GraphQL query — use jq to safely escape
GQL_QUERY="{ actor { account(id: ${NR_ACCOUNT_ID}) { nrql(query: \"${NRQL}\") { results } } } }"

echo "==> [Step 3/3] Polling New Relic for marker: ${MARKER}"
echo "    Endpoint : ${NR_ENDPOINT}"
echo "    Timeout  : ${MAX_WAIT_SECONDS}s (poll every ${POLL_INTERVAL_SECS}s)"

START_EPOCH="$(date +%s)"

while true; do
  RESP="$(curl -sS -X POST "${NR_ENDPOINT}" \
    -H "Content-Type: application/json" \
    -H "API-Key: ${NR_USER_API_KEY}" \
    --data "$(jq -nc --arg q "${GQL_QUERY}" '{query:$q}')" 2>&1)" || true

  COUNT="$(echo "${RESP}" | jq -r '.data.actor.account.nrql.results[0].c // 0' 2>/dev/null)" || COUNT=0

  if [[ "${COUNT}" != "0" && "${COUNT}" != "null" ]]; then
    echo ""
    echo "SUCCESS: Test log ingested and queryable in New Relic (count=${COUNT})."
    # Clean up test object
    aws s3 rm "s3://${S3_BUCKET}/${S3_KEY}" > /dev/null 2>&1 || true
    exit 0
  fi

  NOW="$(date +%s)"
  ELAPSED=$((NOW - START_EPOCH))
  if (( ELAPSED >= MAX_WAIT_SECONDS )); then
    echo ""
    echo "FAIL: Test log not queryable in New Relic within ${MAX_WAIT_SECONDS}s."
    echo "  Marker   : ${MARKER}"
    echo "  Last resp: ${RESP}"
    # Clean up test object
    aws s3 rm "s3://${S3_BUCKET}/${S3_KEY}" > /dev/null 2>&1 || true
    exit 1
  fi

  REMAINING=$((MAX_WAIT_SECONDS - ELAPSED))
  printf "    Waiting... (%ds elapsed, %ds remaining)\r" "${ELAPSED}" "${REMAINING}"
  sleep "${POLL_INTERVAL_SECS}"
done
