#!/usr/bin/env bash

set -uo pipefail

# ── Argument validation ─────────────────────────────────────────────────────
if [[ "$#" -lt 2 ]]; then
    cat >&2 <<EOF
Usage: $0 <region> <substr> [<substr>...]
  <region>: US | EU | STAGING
  <substr>: name substring to match (multiple allowed)
  Requires NEW_RELIC_API_KEY env var.
EOF
    exit 1
fi

if [[ -z "${NEW_RELIC_API_KEY:-}" ]]; then
    echo "ERROR: NEW_RELIC_API_KEY env var must be set" >&2
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq is required (brew install jq, or apt-get install jq)" >&2
    exit 1
fi

REGION="$1"
shift
SUBSTRINGS=("$@")

case "$REGION" in
    US)      ENDPOINT="https://api.newrelic.com/graphql" ;;
    EU)      ENDPOINT="https://api.eu.newrelic.com/graphql" ;;
    STAGING) ENDPOINT="https://staging-api.newrelic.com/graphql" ;;
    *)
        echo "ERROR: invalid region '$REGION' (expected US | EU | STAGING)" >&2
        exit 1
        ;;
esac

# ── NerdGraph helpers ───────────────────────────────────────────────────────

# nerdgraph <query-json>  →  prints raw response body
nerdgraph() {
    local payload="$1"
    curl -sS -X POST \
        -H "Content-Type: application/json" \
        -H "Api-Key: $NEW_RELIC_API_KEY" \
        -d "$payload" \
        "$ENDPOINT"
}

search_setups() {
    local cursor=""
    while :; do
        local payload
        if [[ -z "$cursor" ]]; then
            payload='{"query":"{ actor { entityManagement { entitySearch(query: \"type = '"'"'FEDERATED_LOGS_SETUP'"'"'\") { entities { id name type ... on EntityManagementFederatedLogsSetupEntity { lifecycleStatus { status } metadata { version } } } nextCursor } } } }"}'
        else
            payload=$(jq -n --arg c "$cursor" '{
                query: ("{ actor { entityManagement { entitySearch(query: \"type = '"'"'FEDERATED_LOGS_SETUP'"'"'\", cursor: " + ($c | tojson) + ") { entities { id name type ... on EntityManagementFederatedLogsSetupEntity { lifecycleStatus { status } metadata { version } } } nextCursor } } } }")
            }')
        fi
        local resp
        resp=$(nerdgraph "$payload")
        echo "$resp" | jq -c '.data.actor.entityManagement.entitySearch.entities[]?'
        cursor=$(echo "$resp" | jq -r '.data.actor.entityManagement.entitySearch.nextCursor // ""')
        [[ -z "$cursor" ]] && break
    done
}

search_aws_connections() {
    local cursor=""
    while :; do
        local payload
        if [[ -z "$cursor" ]]; then
            payload='{"query":"{ actor { entityManagement { entitySearch(query: \"type = '"'"'AWS_CONNECTION'"'"'\") { entities { id name type ... on EntityManagementAwsConnectionEntity { metadata { version } } } nextCursor } } } }"}'
        else
            payload=$(jq -n --arg c "$cursor" '{
                query: ("{ actor { entityManagement { entitySearch(query: \"type = '"'"'AWS_CONNECTION'"'"'\", cursor: " + ($c | tojson) + ") { entities { id name type ... on EntityManagementAwsConnectionEntity { metadata { version } } } nextCursor } } } }")
            }')
        fi
        local resp
        resp=$(nerdgraph "$payload")
        echo "$resp" | jq -c '.data.actor.entityManagement.entitySearch.entities[]?'
        cursor=$(echo "$resp" | jq -r '.data.actor.entityManagement.entitySearch.nextCursor // ""')
        [[ -z "$cursor" ]] && break
    done
}

search_partitions() {
    local cursor=""
    while :; do
        local payload
        if [[ -z "$cursor" ]]; then
            payload='{"query":"{ actor { entityManagement { entitySearch(query: \"type = '"'"'FEDERATED_LOGS_PARTITION'"'"'\") { entities { id name type ... on EntityManagementFederatedLogsPartitionEntity { isDefault setup { id } metadata { version } } } nextCursor } } } }"}'
        else
            payload=$(jq -n --arg c "$cursor" '{
                query: ("{ actor { entityManagement { entitySearch(query: \"type = '"'"'FEDERATED_LOGS_PARTITION'"'"'\", cursor: " + ($c | tojson) + ") { entities { id name type ... on EntityManagementFederatedLogsPartitionEntity { isDefault setup { id } metadata { version } } } nextCursor } } } }")
            }')
        fi
        local resp
        resp=$(nerdgraph "$payload")
        echo "$resp" | jq -c '.data.actor.entityManagement.entitySearch.entities[]?'
        cursor=$(echo "$resp" | jq -r '.data.actor.entityManagement.entitySearch.nextCursor // ""')
        [[ -z "$cursor" ]] && break
    done
}

name_contains_any() {
    local name="$1"
    shift
    for sub in "$@"; do
        case "$name" in
            *"$sub"*) return 0 ;;
        esac
    done
    return 1
}

get_entity_version() {
    local id="$1"
    local payload
    payload=$(jq -n --arg id "$id" '{query: "{ actor { entityManagement { entity(id: $id) { metadata { version } } } } }", variables: {id: $id}}')
    nerdgraph "$payload" \
        | jq -r '.data.actor.entityManagement.entity.metadata.version // empty'
}

delete_entity() {
    local id="$1"
    local version="$2"
    local label="${3:-entity}"

    if [[ -z "$version" || "$version" == "null" ]]; then
        echo "  ${label}: missing version for ${id}; skipping" >&2
        return 1
    fi

    local payload
    payload=$(jq -n --arg id "$id" --argjson v "$version" '
        {query: "mutation($id: ID!, $version: Int) { entityManagementDelete(id: $id, version: $version) { id } }",
         variables: {id: $id, version: $v}}')

    local resp
    resp=$(nerdgraph "$payload")
    local deleted_id
    deleted_id=$(echo "$resp" | jq -r '.data.entityManagementDelete.id // empty')
    if [[ "$deleted_id" == "$id" ]]; then
        echo "  ${label}: deleted ${id}"
        return 0
    fi
    echo "  ${label}: delete failed for ${id}; response: $resp" >&2
    return 1
}

# ── Main ────────────────────────────────────────────────────────────────────

echo "==> NR entity cleanup against ${ENDPOINT}"
echo "    substrings: ${SUBSTRINGS[*]}"

# Step 1: list all NGEP setups + filter by substring(s) → JSONL of matches.
#         Each line has {id, name, version}.
SETUPS_MATCHED=$(mktemp -t setups-matched.XXXXXX)
AWSCONN_MATCHED=$(mktemp -t awsconn-matched.XXXXXX)
PARTITIONS_RAW=$(mktemp -t partitions-raw.XXXXXX)
trap 'rm -f "$SETUPS_MATCHED" "$AWSCONN_MATCHED" "$PARTITIONS_RAW"' EXIT

echo "==> Listing all FEDERATED_LOGS_SETUP entities and filtering by name..."
while IFS= read -r entity; do
    [[ -z "$entity" ]] && continue
    name=$(echo "$entity" | jq -r '.name // empty')
    [[ -z "$name" ]] && continue
    if name_contains_any "$name" "${SUBSTRINGS[@]}"; then
        id=$(echo "$entity" | jq -r '.id // empty')
        version=$(echo "$entity" | jq -r '.metadata.version // empty')
        status=$(echo "$entity" | jq -r '.lifecycleStatus.status // "unknown"')
        echo "    matched setup: $name (id=$id, status=$status, version=$version)"
        echo "$entity" | jq -c '{id, name, version: .metadata.version}' >> "$SETUPS_MATCHED"
    fi
done < <(search_setups)

echo "==> Listing all AWS_CONNECTION entities and filtering by name..."
while IFS= read -r entity; do
    [[ -z "$entity" ]] && continue
    name=$(echo "$entity" | jq -r '.name // empty')
    [[ -z "$name" ]] && continue
    if name_contains_any "$name" "${SUBSTRINGS[@]}"; then
        id=$(echo "$entity" | jq -r '.id // empty')
        version=$(echo "$entity" | jq -r '.metadata.version // empty')
        echo "    matched AWS_CONNECTION: $name (id=$id, version=$version)"
        echo "$entity" | jq -c '{id, name, version: .metadata.version}' >> "$AWSCONN_MATCHED"
    fi
done < <(search_aws_connections)

setup_count=$(wc -l < "$SETUPS_MATCHED" | tr -d ' ')
awsconn_count=$(wc -l < "$AWSCONN_MATCHED" | tr -d ' ')

if [[ "$setup_count" -eq 0 && "$awsconn_count" -eq 0 ]]; then
    echo "==> No matching entities found. Nothing to do."
    exit 0
fi

# Step 2: list partitions linked to matched setups (non-default only).
PARTITIONS_MATCHED=$(mktemp -t partitions-matched.XXXXXX)
trap 'rm -f "$SETUPS_MATCHED" "$AWSCONN_MATCHED" "$PARTITIONS_RAW" "$PARTITIONS_MATCHED"' EXIT

if [[ "$setup_count" -gt 0 ]]; then
    echo "==> Listing all FEDERATED_LOGS_PARTITION entities and filtering to non-default partitions of matched setups..."
    # Build a JSON array of matched setup IDs for client-side filtering.
    matched_setup_ids=$(jq -s -c '[.[].id]' "$SETUPS_MATCHED")

    search_partitions > "$PARTITIONS_RAW"

    while IFS= read -r entity; do
        [[ -z "$entity" ]] && continue
        # Keep only non-default partitions whose .setup.id is in matched_setup_ids.
        echo "$entity" | jq -c --argjson setupIds "$matched_setup_ids" '
            if (.isDefault == false) and (.setup.id as $sid | $setupIds | index($sid))
            then {id, name, version: .metadata.version, setup_id: .setup.id}
            else empty end'
    done < "$PARTITIONS_RAW" > "$PARTITIONS_MATCHED"

    while IFS= read -r p; do
        [[ -z "$p" ]] && continue
        name=$(echo "$p" | jq -r '.name')
        id=$(echo "$p" | jq -r '.id')
        echo "    matched custom partition: $name ($id)"
    done < "$PARTITIONS_MATCHED"
fi

partition_count=$(wc -l < "$PARTITIONS_MATCHED" 2>/dev/null | tr -d ' ' || echo 0)

# Step 3: delete in order — custom partitions, then setups (default cascades),
# then AWS_CONNECTIONs (safety net).
fails=0
total=$((partition_count + setup_count + awsconn_count))

if [[ "$partition_count" -gt 0 ]]; then
    echo "==> Deleting $partition_count custom partition(s)"
    while IFS= read -r p; do
        [[ -z "$p" ]] && continue
        id=$(echo "$p" | jq -r '.id')
        version=$(echo "$p" | jq -r '.version')
        delete_entity "$id" "$version" "partition" || fails=$((fails + 1))
    done < "$PARTITIONS_MATCHED"
fi

if [[ "$setup_count" -gt 0 ]]; then
    echo "==> Deleting $setup_count setup(s) (default partition cascades)"
    while IFS= read -r s; do
        [[ -z "$s" ]] && continue
        id=$(echo "$s" | jq -r '.id')
        version=$(echo "$s" | jq -r '.version')
        delete_entity "$id" "$version" "setup" || fails=$((fails + 1))
    done < "$SETUPS_MATCHED"
fi

if [[ "$awsconn_count" -gt 0 ]]; then
    echo "==> Deleting $awsconn_count AWS_CONNECTION(s) (safety net for failed tf destroy)"
    while IFS= read -r a; do
        [[ -z "$a" ]] && continue
        id=$(echo "$a" | jq -r '.id')
        version=$(echo "$a" | jq -r '.version')
        delete_entity "$id" "$version" "aws-connection" || fails=$((fails + 1))
    done < "$AWSCONN_MATCHED"
fi

if [[ "$fails" -gt 0 ]]; then
    echo "==> $fails of $total deletion(s) failed (see logs above)"
    exit 1
fi

echo "==> All $total deletion(s) succeeded"
