#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/development-workflow/run-item-scope-resolver.sh"
TMP_DIR="$(mktemp -d)"
MOCK_BIN="$TMP_DIR/bin"
mkdir -p "$MOCK_BIN"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local file="$1"
  local pattern="$2"
  local message="$3"

  grep -Fq -- "$pattern" "$file" || fail "$message"
}

assert_not_contains() {
  local file="$1"
  local pattern="$2"
  local message="$3"

  if grep -Fq -- "$pattern" "$file"; then
    fail "$message"
  fi
}

cat > "$MOCK_BIN/gh" <<'MOCK_GH'
#!/usr/bin/env bash
case "$*" in
  "pr view 123 --json state --jq .state"|"pr view 124 --json state --jq .state")
    exit 1
    ;;
  "issue view 123 --json state --jq .state"|"issue view 124 --json state --jq .state")
    printf 'OPEN\n'
    ;;
  "issue view 123 --json subIssues --jq .subIssues.totalCount"|"issue view 124 --json subIssues --jq .subIssues.totalCount")
    printf '0\n'
    ;;
  "issue view 123 --json labels --jq [.labels[].name] | map(ascii_downcase) | map(select(. == \"epic\")) | length"|"issue view 124 --json labels --jq [.labels[].name] | map(ascii_downcase) | map(select(. == \"epic\")) | length")
    printf '0\n'
    ;;
  *)
    printf 'unexpected gh invocation: %s\n' "$*" >&2
    exit 64
    ;;
esac
MOCK_GH
chmod +x "$MOCK_BIN/gh"

mock_resolver="$TMP_DIR/mock-run-epic-scope-resolver.sh"
cat > "$mock_resolver" <<'MOCK_RESOLVER'
#!/usr/bin/env bash
{
  printf 'env:%s\n' "${RUN_EPIC_SCOPE_RESOLVER_INTERNAL_ITEMS:-}"
  printf 'args:'
  printf '<%s>' "$@"
  printf '\n'
} >> "$RUN_ITEM_SCOPE_RESOLVER_CAPTURE"

jq -n '{
  items: [{number: 0, title: "Mock item"}],
  groups: {eligible: [], blocked: [], already_merged: [], in_review: [], ambiguous: [], out_of_scope: []},
  baseBranch: "develop",
  baseReason: "test mock",
  readOnlyGuarantee: "mock read-only"
}'
MOCK_RESOLVER
chmod +x "$mock_resolver"

capture_hash="$TMP_DIR/hash-target.capture"
PATH="$MOCK_BIN:$PATH" \
RUN_ITEM_SCOPE_RESOLVER_CAPTURE="$capture_hash" \
RUN_EPIC_SCOPE_RESOLVER_CMD="$mock_resolver" \
  bash "$SCRIPT" --target "#123" --json >/dev/null

assert_contains "$capture_hash" "args:<--items><123>" \
  "leading # target should be stripped before forwarding --items"
assert_not_contains "$capture_hash" "<#123>" \
  "downstream resolver must not receive the raw #123 token"

capture_internal="$TMP_DIR/internal-items.capture"
PATH="$MOCK_BIN:$PATH" \
RUN_ITEM_SCOPE_RESOLVER_CAPTURE="$capture_internal" \
RUN_EPIC_SCOPE_RESOLVER_CMD="$mock_resolver" \
  bash "$SCRIPT" --issue 124 --json >/dev/null

assert_contains "$capture_internal" "env:1" \
  "RUN_EPIC_SCOPE_RESOLVER_INTERNAL_ITEMS=1 should be forwarded to downstream resolver"
assert_contains "$capture_internal" "args:<--items><124>" \
  "numeric --issue should be forwarded as a single internal item"

printf 'run item scope resolver tests passed\n'
