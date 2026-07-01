#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/development-workflow/actions-cost-audit.sh"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local text="$1"
  local pattern="$2"
  local message="$3"

  printf '%s\n' "$text" | grep -Eq "$pattern" || fail "$message"
}

assert_not_contains() {
  local text="$1"
  local pattern="$2"
  local message="$3"

  if printf '%s\n' "$text" | grep -Eq "$pattern"; then
    fail "$message"
  fi
}

cat > "$TMP_DIR/gh" <<'MOCK_GH'
#!/usr/bin/env bash
set -euo pipefail

case "${GH_MOCK_MODE:-success}" in
  success)
    cat <<'JSON'
[
  {
    "databaseId": 101,
    "workflowName": "PR-Agent",
    "workflowDatabaseId": 11,
    "status": "completed",
    "conclusion": "success",
    "createdAt": "2026-07-01T13:00:00Z",
    "startedAt": "2026-07-01T13:01:00Z",
    "updatedAt": "2026-07-01T13:04:00Z",
    "event": "issue_comment",
    "headBranch": "feature/example",
    "url": "https://github.example/runs/101"
  },
  {
    "databaseId": 102,
    "workflowName": "PR-Agent",
    "workflowDatabaseId": 11,
    "status": "completed",
    "conclusion": "success",
    "createdAt": "2026-07-01T12:00:00Z",
    "startedAt": "2026-07-01T12:00:30Z",
    "updatedAt": "2026-07-01T12:02:30Z",
    "event": "issue_comment",
    "headBranch": "feature/example",
    "url": "https://github.example/runs/102"
  },
  {
    "databaseId": 201,
    "workflowName": "CI",
    "workflowDatabaseId": 22,
    "status": "completed",
    "conclusion": "success",
    "createdAt": "2026-07-01T11:00:00Z",
    "startedAt": "2026-07-01T11:00:00Z",
    "updatedAt": "2026-07-01T11:10:00Z",
    "event": "pull_request",
    "headBranch": "feature/example",
    "url": "https://github.example/runs/201"
  },
  {
    "databaseId": 202,
    "workflowName": "CI",
    "workflowDatabaseId": 22,
    "status": "in_progress",
    "conclusion": null,
    "createdAt": "2026-07-01T10:00:00Z",
    "startedAt": "2026-07-01T10:01:00Z",
    "updatedAt": null,
    "event": "pull_request",
    "headBranch": "feature/example",
    "url": "https://github.example/runs/202"
  },
  {
    "databaseId": 301,
    "workflowName": "Old Workflow",
    "workflowDatabaseId": 33,
    "status": "completed",
    "conclusion": "success",
    "createdAt": "2026-06-01T10:00:00Z",
    "startedAt": "2026-06-01T10:00:00Z",
    "updatedAt": "2026-06-01T10:05:00Z",
    "event": "push",
    "headBranch": "develop",
    "url": "https://github.example/runs/301"
  }
]
JSON
    ;;
  empty)
    printf '[]\n'
    ;;
  fail)
    printf 'HTTP 403: Resource not accessible by integration\n' >&2
    exit 1
    ;;
  *)
    printf 'unknown GH_MOCK_MODE\n' >&2
    exit 2
    ;;
esac
MOCK_GH
chmod +x "$TMP_DIR/gh"

run_audit() {
  PATH="$TMP_DIR:$PATH" "$SCRIPT" "$@"
}

output="$(GH_MOCK_MODE=success run_audit --limit 5)"
assert_contains "$output" '^# GitHub Actions Cost Audit$' "report heading missing"
assert_contains "$output" '\| CI \| 2 \| 1 \| 1 \| 10m \| 10m \|' "CI aggregation should include incomplete run and completed duration"
assert_contains "$output" '\| PR-Agent \| 2 \| 2 \| 0 \| 5m \| 2\.5m \|' "PR-Agent aggregation should sum and average duration"
assert_contains "$output" 'Incomplete duration records: 1' "incomplete duration count missing"
assert_contains "$output" 'Public/private cost-risk framing' "cost-risk framing section missing"
assert_contains "$output" 'Private downstream repositories can consume included or paid runner minutes' "private downstream risk language missing"
assert_contains "$output" '\| make opt-in \|' "make opt-in recommendation outcome missing"
assert_contains "$output" '\| keep \|' "keep recommendation outcome missing"
assert_contains "$output" '\| investigate \|' "investigate recommendation outcome missing"

repo_output="$(GH_MOCK_MODE=success run_audit --limit 1 --repo "owner/repo with space")"
assert_contains "$repo_output" 'owner/repo with space' "repo argument with spaces should be preserved in output"

since_output="$(GH_MOCK_MODE=success run_audit --limit 5 --since 2026-07-01T00:00:00Z)"
assert_contains "$since_output" 'since 2026-07-01T00:00:00Z' "since scope should be printed"
assert_not_contains "$since_output" 'Old Workflow' "since filter should remove older runs"

empty_output="$(GH_MOCK_MODE=empty run_audit --limit 5)"
assert_contains "$empty_output" 'No workflow run data was available' "empty run history should produce no-data report"
assert_contains "$empty_output" '\| disable \|' "empty report should still include recommendation vocabulary"

if GH_MOCK_MODE=fail run_audit --limit 5 >"$TMP_DIR/fail.out" 2>"$TMP_DIR/fail.err"; then
  fail "permission failure should exit non-zero"
fi
assert_contains "$(cat "$TMP_DIR/fail.err")" 'ERROR: gh run list failed' "permission failure should include actionable error"

if run_audit --limit 0 >"$TMP_DIR/limit.out" 2>"$TMP_DIR/limit.err"; then
  fail "limit zero should exit non-zero"
fi
assert_contains "$(cat "$TMP_DIR/limit.err")" 'limit must be greater than 0' "limit validation message missing"

if run_audit --limit " " >"$TMP_DIR/blank-limit.out" 2>"$TMP_DIR/blank-limit.err"; then
  fail "whitespace-only limit should exit non-zero"
fi
assert_contains "$(cat "$TMP_DIR/blank-limit.err")" 'limit must be a positive integer' "blank limit validation message missing"

if run_audit --since not-a-date >"$TMP_DIR/since.out" 2>"$TMP_DIR/since.err"; then
  fail "invalid since timestamp should exit non-zero"
fi
assert_contains "$(cat "$TMP_DIR/since.err")" 'ISO-8601 UTC timestamp' "invalid since validation message missing"

printf 'actions cost audit checks passed\n'
