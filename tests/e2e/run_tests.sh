#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MOCK_URL="http://localhost:1080"
E2E_SCRIPT="$REPO_ROOT/scripts/e2e_test.py"

# Zero out wait times for mock testing
export E2E_WRITE_RETRY_DELAY=0
export E2E_READ_RETRY_DELAY=0
export E2E_INITIAL_READ_WAIT=0
export E2E_READ_MAX_RETRIES=3

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

passed=0
failed=0
total=0

clean_up() {
    echo ""
    echo "Cleaning up..."
    docker compose -f "$SCRIPT_DIR/docker-compose.yml" down -v 2>/dev/null || true
}
trap clean_up EXIT

load_expectations() {
    local file="$1"
    curl -s -X PUT "$MOCK_URL/mockserver/reset" > /dev/null
    curl -s -X PUT "$MOCK_URL/mockserver/expectation" \
        -H "Content-Type: application/json" \
        -d @"$SCRIPT_DIR/expectations/$file" > /dev/null
}

run_test() {
    local name="$1"
    local expectations="$2"
    local expect_exit="$3"  # 0 = expect pass, 1 = expect fail

    total=$((total + 1))
    echo ""
    echo -e "${YELLOW}━━━ TEST: $name ━━━${NC}"

    load_expectations "$expectations"

    set +e
    python3 "$E2E_SCRIPT" \
        --pcg-endpoint "$MOCK_URL/v1/logs" \
        --graphql-url "$MOCK_URL/graphql" \
        --license-key "mock-license-key" \
        --partition "application_log" \
        --nr-account-id "12345" \
        --nr-api-key "mock-api-key" 2>&1
    actual_exit=$?
    set -e

    if [[ "$actual_exit" -eq "$expect_exit" ]]; then
        echo -e "${GREEN}✓ PASSED: $name (exit=$actual_exit as expected)${NC}"
        passed=$((passed + 1))
    else
        echo -e "${RED}✗ FAILED: $name (exit=$actual_exit, expected=$expect_exit)${NC}"
        failed=$((failed + 1))
    fi
}

# ── Start MockServer ──────────────────────────────────────────
echo "Starting MockServer..."
docker compose -f "$SCRIPT_DIR/docker-compose.yml" up -d

echo "Waiting for MockServer to be ready..."
for i in $(seq 1 30); do
    if curl -s "$MOCK_URL/mockserver/status" > /dev/null 2>&1; then
        echo "MockServer ready."
        break
    fi
    sleep 1
done

# ── Run tests ─────────────────────────────────────────────────
run_test "Happy path"                    "happy_path.json"              0
run_test "Write retry then success"      "write_retry.json"             0
run_test "NR read retry then success"    "read_retry.json"              0
run_test "Write permanent failure"       "write_permanent_failure.json"  1
run_test "NR read permanent empty"       "read_permanent_empty.json"    1

# ── Results ───────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "Results: ${GREEN}$passed passed${NC}, ${RED}$failed failed${NC}, $total total"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ "$failed" -gt 0 ]]; then
    exit 1
fi
