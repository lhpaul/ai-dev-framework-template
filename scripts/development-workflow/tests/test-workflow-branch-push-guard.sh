#!/usr/bin/env bash
# test-workflow-branch-push-guard.sh - Unit tests for workflow branch push guard.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"
GUARD="$REPO_ROOT/scripts/development-workflow/workflow-branch-push-guard.sh"

TMP_ROOT="$(mktemp -d)"
MOCK_BIN="$TMP_ROOT/bin"
CALL_LOG="$TMP_ROOT/calls.log"
AUTH_FILE="$TMP_ROOT/auth.json"
COMMENT_BODY="$TMP_ROOT/comment-body.txt"
CLAIM_BODY="$TMP_ROOT/claim-body.txt"
REV_PARSE_COUNT="$TMP_ROOT/rev-parse-count.txt"
mkdir -p "$MOCK_BIN" "$TMP_ROOT/repo/.git"
: > "$CALL_LOG"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

cat > "$MOCK_BIN/git" <<'MOCK_GIT'
#!/usr/bin/env bash
set -euo pipefail

printf 'git %s\n' "$*" >> "$WORKFLOW_PUSH_GUARD_CALL_LOG"

if [ "${1:-}" = "-C" ]; then
  shift 2
fi

case "$*" in
  remote\ get-url\ origin)
    case "${MOCK_REMOTE_MODE:-github}" in
      github) printf 'git@github.com:lhpaul/ai-dev-framework-template.git\n' ;;
      mismatch) printf 'git@github.com:other/repo.git\n' ;;
      malformed) printf '/tmp/local.git\n' ;;
    esac
    ;;
  ls-remote\ --exit-code\ origin\ refs/heads/feature/test)
    case "${MOCK_REMOTE_REF:-published}" in
      published) printf 'abc123\trefs/heads/feature/test\n' ;;
      stale) printf 'def456\trefs/heads/feature/test\n' ;;
      unpublished) exit 2 ;;
      fail) exit 128 ;;
    esac
    ;;
  rev-parse\ HEAD)
    if [ -n "${WORKFLOW_PUSH_GUARD_REV_PARSE_COUNT:-}" ]; then
      rev_parse_count="$(cat "$WORKFLOW_PUSH_GUARD_REV_PARSE_COUNT" 2>/dev/null || printf '0')"
      rev_parse_count=$((rev_parse_count + 1))
      printf '%s\n' "$rev_parse_count" > "$WORKFLOW_PUSH_GUARD_REV_PARSE_COUNT"
    else
      rev_parse_count="$(grep -c 'rev-parse HEAD' "$WORKFLOW_PUSH_GUARD_CALL_LOG" || true)"
    fi
    if [ "${MOCK_HEAD_TIP_SECOND:-}" = "fail" ] && [ "$rev_parse_count" -ge 2 ]; then
      exit 128
    elif [ -n "${MOCK_HEAD_TIP_SECOND:-}" ] && [ "$rev_parse_count" -ge 2 ]; then
      printf '%s\n' "$MOCK_HEAD_TIP_SECOND"
    else
      printf '%s\n' "${MOCK_HEAD_TIP:-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb}"
    fi
    ;;
  rev-parse\ refs/heads/feature/test\^\{commit\})
    if [ "${MOCK_LOCAL_BRANCH_TIP:-}" = "fail" ]; then
      exit 128
    fi
    printf '%s\n' "${MOCK_LOCAL_BRANCH_TIP:-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb}"
    ;;
  push\ origin\ bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb:refs/heads/feature/test)
    exit 0
    ;;
  push\ --force-with-lease=refs/heads/feature/test:abc123\ origin\ bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb:refs/heads/feature/test)
    case "${MOCK_PUSH_MODE:-ok}" in
      ok) exit 0 ;;
      fail) exit 1 ;;
    esac
    ;;
  *)
    printf 'unexpected git invocation: git %s\n' "$*" >&2
    exit 64
    ;;
esac
MOCK_GIT
chmod +x "$MOCK_BIN/git"

cat > "$MOCK_BIN/gh" <<'MOCK_GH'
#!/usr/bin/env bash
set -euo pipefail

printf 'gh %s\n' "$*" >> "$WORKFLOW_PUSH_GUARD_CALL_LOG"

case "$*" in
  api\ user\ --jq\ .login)
    printf '%s\n' "${MOCK_OPERATOR_LOGIN:-lhpaul}"
    ;;
  api\ repos/lhpaul/ai-dev-framework-template/issues/comments/9001)
    body="$(python3 - "$WORKFLOW_PUSH_GUARD_COMMENT_BODY" <<'PY'
from pathlib import Path
import json, sys
print(json.dumps(Path(sys.argv[1]).read_text()))
PY
)"
    printf '{"user":{"login":"%s","type":"%s"},"issue_url":"https://api.github.com/repos/lhpaul/ai-dev-framework-template/issues/%s","body":%s}\n' "${MOCK_COMMENT_AUTHOR:-trusted-human}" "${MOCK_COMMENT_USER_TYPE:-User}" "${MOCK_COMMENT_ISSUE_NUMBER:-1423}" "$body"
    ;;
  api\ repos/lhpaul/ai-dev-framework-template/collaborators/*/permission\ --jq\ .permission\ //\ empty)
    printf '%s\n' "${MOCK_COMMENT_PERMISSION:-admin}"
    ;;
	  pr\ comment\ 1423\ --body*)
	    if [ "${MOCK_PR_COMMENT_MODE:-ok}" = "fail" ]; then
	      printf 'comment failed\n' >&2
	      exit 1
	    fi
	    printf '%s\n' "$*" | sed 's/^pr comment 1423 --body //' > "$WORKFLOW_PUSH_GUARD_CLAIM_BODY"
	    printf 'https://github.com/lhpaul/ai-dev-framework-template/pull/1423#issuecomment-1\n'
	    ;;
	  api\ -X\ POST\ repos/lhpaul/ai-dev-framework-template/git/refs\ -f\ ref=refs/tags/workflow-force-push-locks/*\ -f\ sha=abc123)
	    if [ "${MOCK_EXISTING_CLAIM:-none}" = "other" ]; then
	      printf '{"message":"Reference already exists"}\n' >&2
	      exit 1
	    fi
	    if [ "${MOCK_LOCK_MODE:-ok}" = "fail" ]; then
	      printf '{"message":"Resource not accessible by integration"}\n' >&2
	      exit 1
	    fi
	    printf '{"ref":"refs/tags/workflow-force-push-locks/mock"}\n'
	    ;;
	  api\ -X\ DELETE\ repos/lhpaul/ai-dev-framework-template/git/refs/tags/workflow-force-push-locks/*)
	    printf '{}\n'
	    ;;
  api\ --paginate\ --slurp\ repos/lhpaul/ai-dev-framework-template/issues/1423/comments?per_page=100)
    if [ "${MOCK_EXISTING_CLAIM:-none}" = "other" ]; then
      python3 - <<'PY'
import json
print(json.dumps([[
  {"id": 1, "created_at": "2026-08-01T00:00:00Z", "body": "workflow-force-push-authorization-claim\nauthorization_id=auth-1\nrun_id=other\nstate=claimed"},
  {"id": 2, "created_at": "2026-08-01T00:00:01Z", "body": "workflow-force-push-authorization-claim\nauthorization_id=auth-1\nrun_id=current\nstate=claimed"},
]]))
PY
    else
      python3 - "$WORKFLOW_PUSH_GUARD_CLAIM_BODY" <<'PY'
from pathlib import Path
import json, sys
body = Path(sys.argv[1]).read_text()
print(json.dumps([[{"id": 1, "created_at": "2026-08-01T00:00:00Z", "body": body}]]))
PY
    fi
    ;;
  *)
    printf 'unexpected gh invocation: gh %s\n' "$*" >&2
    exit 64
    ;;
esac
MOCK_GH
chmod +x "$MOCK_BIN/gh"

export PATH="$MOCK_BIN:$PATH"
export WORKFLOW_PUSH_GUARD_CALL_LOG="$CALL_LOG"
export WORKFLOW_PUSH_GUARD_COMMENT_BODY="$COMMENT_BODY"
export WORKFLOW_PUSH_GUARD_CLAIM_BODY="$CLAIM_BODY"
export WORKFLOW_PUSH_GUARD_REV_PARSE_COUNT="$REV_PARSE_COUNT"

PASS_COUNT=0
FAIL_COUNT=0

run_test() {
  local name="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    printf 'PASS: %s\n' "$name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    printf 'FAIL: %s - expected %s, got %s\n' "$name" "$expected" "$actual"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

guard_field() {
  local output="$1" field="$2"
  printf '%s\n' "$output" | awk -F= -v key="$field" '$1 == key {print $2}' | tail -n 1
}

file_count() {
  local pattern="$1" path="$2"
  awk -v pattern="$pattern" 'index($0, pattern) {count += 1} END {print count + 0}' "$path"
}

call_log_count() {
  local pattern="$1"
  file_count "$pattern" "$CALL_LOG"
}

write_auth() {
  local action="${1:-force-with-lease}"
  local repo="${2:-lhpaul/ai-dev-framework-template}"
  local branch="${3:-refs/heads/feature/test}"
  local tip="${4:-abc123}"
  local operator="${5:-lhpaul}"
  local expires="${6:-2099-01-01T00:00:00Z}"
  local new_tip="${7:-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb}"
  local authorized_by="${8:-trusted-human}"

  cat > "$COMMENT_BODY" <<EOF
authorization_id=auth-1
canonical_repo=$repo
pr_number=1423
branch_ref=$branch
action=$action
operator_login=$operator
expected_remote_tip=$tip
authorized_new_tip=$new_tip
expires_at=$expires
EOF
  local fp
  fp="$(printf '%s' "$(cat "$COMMENT_BODY")" | openssl dgst -sha256 -r | awk '{print $1}')"
  cat > "$AUTH_FILE" <<JSON
{
  "schema_version": "1",
  "authorization_id": "auth-1",
  "canonical_repo": "$repo",
  "pr_number": 1423,
  "branch_ref": "$branch",
  "action": "$action",
  "expected_remote_tip": "$tip",
  "authorized_new_tip": "$new_tip",
  "operator_login": "$operator",
  "authorized_by": "$authorized_by",
  "source_kind": "github_comment",
  "source_id": 9001,
  "source_url": "https://github.com/lhpaul/ai-dev-framework-template/pull/1423#issuecomment-9001",
  "source_fingerprint_sha256": "sha256:$fp",
  "issued_at": "2026-08-01T00:00:00Z",
  "expires_at": "$expires",
  "single_use": true
}
JSON
}

run_guard() {
  "$GUARD" \
    --repo-root "$TMP_ROOT/repo" \
    --remote origin \
    --repo lhpaul/ai-dev-framework-template \
    --branch-ref refs/heads/feature/test \
    --mode "$1" \
    --pr 1423 \
    "${@:2}"
}

echo ""
echo "=== Workflow branch push guard ==="

export MOCK_REMOTE_REF=published MOCK_REMOTE_MODE=github MOCK_HEAD_TIP=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
normal_output="$(run_guard normal -- origin feature/test)"
run_test "normal_published_allowed" "allowed" "$(guard_field "$normal_output" PUSH_GUARD_RESULT)"
run_test "normal_published_reason" "normal_push_allowed" "$(guard_field "$normal_output" PUSH_GUARD_REASON)"
run_test "normal_published_push_executed" "1" "$(call_log_count 'push origin bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb:refs/heads/feature/test')"

export MOCK_REMOTE_REF=unpublished
unpublished_output="$(run_guard normal -- origin feature/test)"
run_test "normal_unpublished_allowed" "allowed" "$(guard_field "$unpublished_output" PUSH_GUARD_RESULT)"
run_test "normal_unpublished_reason" "unpublished_ref_allowed" "$(guard_field "$unpublished_output" PUSH_GUARD_REASON)"
run_test "normal_unpublished_push_executed" "2" "$(call_log_count 'push origin bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb:refs/heads/feature/test')"

set +e
missing_local_branch_output="$(MOCK_LOCAL_BRANCH_TIP=fail "$GUARD" \
  --repo-root "$TMP_ROOT/repo" \
  --remote origin \
  --repo lhpaul/ai-dev-framework-template \
  --branch-ref refs/heads/feature/test \
  --mode normal \
  --pr 1423 \
  -- origin feature/test 2>&1)"
missing_local_branch_status=$?
set -e
run_test "normal_requires_local_branch_status" "2" "$missing_local_branch_status"
run_test "normal_requires_local_branch_reason" "local_branch_tip_unavailable" "$(guard_field "$missing_local_branch_output" PUSH_GUARD_REASON)"

export MOCK_REMOTE_REF=published
set +e
missing_auth_output="$(run_guard force-with-lease --expected-remote-tip abc123 -- --force-with-lease=refs/heads/feature/test:abc123 origin refs/heads/feature/test:refs/heads/feature/test)"
missing_auth_status=$?
set -e
run_test "missing_auth_status" "1" "$missing_auth_status"
run_test "missing_auth_blocks" "missing_authorization" "$(guard_field "$missing_auth_output" PUSH_GUARD_REASON)"
run_test "missing_auth_no_push" "0" "$(call_log_count 'push --force-with-lease')"

set +e
normal_force_output="$(run_guard normal -- --force origin refs/heads/feature/test:refs/heads/feature/test)"
normal_force_status=$?
set -e
run_test "normal_mode_rejects_force_args_status" "2" "$normal_force_status"
run_test "normal_mode_rejects_force_args_reason" "push_args_force_flag_with_normal_mode" "$(guard_field "$normal_force_output" PUSH_GUARD_REASON)"

write_auth
authorized_output="$(run_guard force-with-lease --expected-remote-tip abc123 --authorization-json "$AUTH_FILE" -- --force-with-lease=refs/heads/feature/test:abc123 origin refs/heads/feature/test:refs/heads/feature/test)"
run_test "authorized_allowed" "allowed" "$(guard_field "$authorized_output" PUSH_GUARD_RESULT)"
run_test "authorized_reason" "authorized_once" "$(guard_field "$authorized_output" PUSH_GUARD_REASON)"
run_test "authorized_consumed" "true" "$(guard_field "$authorized_output" AUTHORIZATION_CONSUMED)"
run_test "authorized_push_executed" "1" "$(call_log_count 'push --force-with-lease=refs/heads/feature/test:abc123 origin bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb:refs/heads/feature/test')"

write_auth
printf '0\n' > "$REV_PARSE_COUNT"
export MOCK_HEAD_TIP_SECOND=cccccccccccccccccccccccccccccccccccccccc
set +e
drifted_head_output="$(run_guard force-with-lease --expected-remote-tip abc123 --authorization-json "$AUTH_FILE" -- --force-with-lease=refs/heads/feature/test:abc123 origin refs/heads/feature/test:refs/heads/feature/test)"
drifted_head_status=$?
set -e
unset MOCK_HEAD_TIP_SECOND
run_test "drifted_head_status" "1" "$drifted_head_status"
run_test "drifted_head_blocks" "authorization_scope_mismatch" "$(guard_field "$drifted_head_output" PUSH_GUARD_REASON)"
run_test "drifted_head_no_push" "1" "$(call_log_count 'push --force-with-lease=refs/heads/feature/test:abc123 origin bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb:refs/heads/feature/test')"
run_test "drifted_head_rolled_back_marker" "1" "$(file_count 'reason=head_tip_mismatch' "$CLAIM_BODY")"
run_test "drifted_head_releases_lock" "1" "$(call_log_count 'api -X DELETE repos/lhpaul/ai-dev-framework-template/git/refs/tags/workflow-force-push-locks/')"

write_auth
printf '0\n' > "$REV_PARSE_COUNT"
export MOCK_HEAD_TIP_SECOND=fail
set +e
final_head_lookup_fail_output="$(run_guard force-with-lease --expected-remote-tip abc123 --authorization-json "$AUTH_FILE" -- --force-with-lease=refs/heads/feature/test:abc123 origin refs/heads/feature/test:refs/heads/feature/test)"
final_head_lookup_fail_status=$?
set -e
unset MOCK_HEAD_TIP_SECOND
run_test "final_head_lookup_failure_status" "2" "$final_head_lookup_fail_status"
run_test "final_head_lookup_failure_reason" "head_tip_unavailable" "$(guard_field "$final_head_lookup_fail_output" PUSH_GUARD_REASON)"
run_test "final_head_lookup_failure_no_push" "1" "$(call_log_count 'push --force-with-lease=refs/heads/feature/test:abc123 origin bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb:refs/heads/feature/test')"
run_test "final_head_lookup_failure_rolled_back_marker" "1" "$(file_count 'reason=head_tip_unavailable' "$CLAIM_BODY")"
run_test "final_head_lookup_failure_releases_lock" "2" "$(call_log_count 'api -X DELETE repos/lhpaul/ai-dev-framework-template/git/refs/tags/workflow-force-push-locks/')"

write_auth force-with-lease other/repo
set +e
wrong_repo_output="$(run_guard force-with-lease --expected-remote-tip abc123 --authorization-json "$AUTH_FILE" -- --force-with-lease=refs/heads/feature/test:abc123 origin refs/heads/feature/test:refs/heads/feature/test)"
wrong_repo_status=$?
set -e
run_test "wrong_repo_status" "1" "$wrong_repo_status"
run_test "wrong_repo_blocks" "authorization_scope_mismatch" "$(guard_field "$wrong_repo_output" PUSH_GUARD_REASON)"

write_auth
export MOCK_REMOTE_REF=stale
set +e
stale_output="$(run_guard force-with-lease --expected-remote-tip abc123 --authorization-json "$AUTH_FILE" -- --force-with-lease=refs/heads/feature/test:abc123 origin refs/heads/feature/test:refs/heads/feature/test)"
stale_status=$?
set -e
run_test "stale_tip_status" "1" "$stale_status"
run_test "stale_tip_blocks" "remote_tip_mismatch" "$(guard_field "$stale_output" PUSH_GUARD_REASON)"

export MOCK_REMOTE_REF=published MOCK_COMMENT_AUTHOR=agent-bot
write_auth
set +e
untrusted_output="$(run_guard force-with-lease --expected-remote-tip abc123 --authorization-json "$AUTH_FILE" -- --force-with-lease=refs/heads/feature/test:abc123 origin refs/heads/feature/test:refs/heads/feature/test)"
untrusted_status=$?
set -e
unset MOCK_COMMENT_AUTHOR
run_test "untrusted_source_status" "1" "$untrusted_status"
run_test "untrusted_source_blocks" "untrusted_authorization_source" "$(guard_field "$untrusted_output" PUSH_GUARD_REASON)"

export MOCK_COMMENT_AUTHOR=lhpaul
write_auth force-with-lease lhpaul/ai-dev-framework-template refs/heads/feature/test abc123 lhpaul 2099-01-01T00:00:00Z bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb lhpaul
set +e
self_authorization_output="$(run_guard force-with-lease --expected-remote-tip abc123 --authorization-json "$AUTH_FILE" -- --force-with-lease=refs/heads/feature/test:abc123 origin refs/heads/feature/test:refs/heads/feature/test)"
self_authorization_status=$?
set -e
unset MOCK_COMMENT_AUTHOR
run_test "self_authorization_status" "1" "$self_authorization_status"
run_test "self_authorization_blocks" "untrusted_authorization_source" "$(guard_field "$self_authorization_output" PUSH_GUARD_REASON)"

export MOCK_COMMENT_USER_TYPE=Bot
write_auth
set +e
bot_authorization_output="$(run_guard force-with-lease --expected-remote-tip abc123 --authorization-json "$AUTH_FILE" -- --force-with-lease=refs/heads/feature/test:abc123 origin refs/heads/feature/test:refs/heads/feature/test)"
bot_authorization_status=$?
set -e
unset MOCK_COMMENT_USER_TYPE
run_test "bot_authorization_status" "1" "$bot_authorization_status"
run_test "bot_authorization_blocks" "untrusted_authorization_source" "$(guard_field "$bot_authorization_output" PUSH_GUARD_REASON)"

export MOCK_COMMENT_PERMISSION=write
write_auth
set +e
non_admin_authorization_output="$(run_guard force-with-lease --expected-remote-tip abc123 --authorization-json "$AUTH_FILE" -- --force-with-lease=refs/heads/feature/test:abc123 origin refs/heads/feature/test:refs/heads/feature/test)"
non_admin_authorization_status=$?
set -e
unset MOCK_COMMENT_PERMISSION
run_test "non_admin_authorization_status" "1" "$non_admin_authorization_status"
run_test "non_admin_authorization_blocks" "untrusted_authorization_source" "$(guard_field "$non_admin_authorization_output" PUSH_GUARD_REASON)"

export MOCK_COMMENT_ISSUE_NUMBER=9999
write_auth
set +e
wrong_comment_issue_output="$(run_guard force-with-lease --expected-remote-tip abc123 --authorization-json "$AUTH_FILE" -- --force-with-lease=refs/heads/feature/test:abc123 origin refs/heads/feature/test:refs/heads/feature/test)"
wrong_comment_issue_status=$?
set -e
unset MOCK_COMMENT_ISSUE_NUMBER
run_test "wrong_comment_issue_status" "1" "$wrong_comment_issue_status"
run_test "wrong_comment_issue_blocks" "untrusted_authorization_source" "$(guard_field "$wrong_comment_issue_output" PUSH_GUARD_REASON)"

write_auth
printf 'authorization_id=auth-1\ncanonical_repo=other/repo\npr_number=1423\nbranch_ref=refs/heads/feature/test\naction=force-with-lease\nexpected_remote_tip=abc123\nauthorized_new_tip=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\nexpires_at=2099-01-01T00:00:00Z\n' > "$COMMENT_BODY"
comment_scope_fp="$(printf '%s' "$(cat "$COMMENT_BODY")" | openssl dgst -sha256 -r | awk '{print $1}')"
jq --arg fp "sha256:$comment_scope_fp" '.source_fingerprint_sha256 = $fp' "$AUTH_FILE" > "$AUTH_FILE.tmp"
mv "$AUTH_FILE.tmp" "$AUTH_FILE"
set +e
wrong_comment_scope_output="$(run_guard force-with-lease --expected-remote-tip abc123 --authorization-json "$AUTH_FILE" -- --force-with-lease=refs/heads/feature/test:abc123 origin refs/heads/feature/test:refs/heads/feature/test)"
wrong_comment_scope_status=$?
set -e
run_test "wrong_comment_scope_status" "1" "$wrong_comment_scope_status"
run_test "wrong_comment_scope_blocks" "untrusted_authorization_source" "$(guard_field "$wrong_comment_scope_output" PUSH_GUARD_REASON)"

write_auth
printf 'authorization_id=auth-1\ncanonical_repo=lhpaul/ai-dev-framework-template\npr_number=1423\nbranch_ref=refs/heads/feature/test\naction=force-with-lease\noperator_login=other-operator\nexpected_remote_tip=abc123\nauthorized_new_tip=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\nexpires_at=2099-01-01T00:00:00Z\n' > "$COMMENT_BODY"
comment_operator_fp="$(printf '%s' "$(cat "$COMMENT_BODY")" | openssl dgst -sha256 -r | awk '{print $1}')"
jq --arg fp "sha256:$comment_operator_fp" '.source_fingerprint_sha256 = $fp' "$AUTH_FILE" > "$AUTH_FILE.tmp"
mv "$AUTH_FILE.tmp" "$AUTH_FILE"
set +e
wrong_comment_operator_output="$(run_guard force-with-lease --expected-remote-tip abc123 --authorization-json "$AUTH_FILE" -- --force-with-lease=refs/heads/feature/test:abc123 origin refs/heads/feature/test:refs/heads/feature/test)"
wrong_comment_operator_status=$?
set -e
run_test "wrong_comment_operator_status" "1" "$wrong_comment_operator_status"
run_test "wrong_comment_operator_blocks" "untrusted_authorization_source" "$(guard_field "$wrong_comment_operator_output" PUSH_GUARD_REASON)"

write_auth
jq '.authorized_new_tip = "cccccccccccccccccccccccccccccccccccccccc"' "$AUTH_FILE" > "$AUTH_FILE.tmp"
mv "$AUTH_FILE.tmp" "$AUTH_FILE"
set +e
wrong_local_new_tip_output="$(run_guard force-with-lease --expected-remote-tip abc123 --authorization-json "$AUTH_FILE" -- --force-with-lease=refs/heads/feature/test:abc123 origin refs/heads/feature/test:refs/heads/feature/test)"
wrong_local_new_tip_status=$?
set -e
run_test "wrong_local_new_tip_status" "1" "$wrong_local_new_tip_status"
run_test "wrong_local_new_tip_blocks" "authorization_scope_mismatch" "$(guard_field "$wrong_local_new_tip_output" PUSH_GUARD_REASON)"

write_auth
printf 'authorization_id=auth-1\ncanonical_repo=lhpaul/ai-dev-framework-template\npr_number=1423\nbranch_ref=refs/heads/feature/test\naction=force-with-lease\noperator_login=lhpaul\nexpected_remote_tip=abc123\nauthorized_new_tip=cccccccccccccccccccccccccccccccccccccccc\nexpires_at=2099-01-01T00:00:00Z\n' > "$COMMENT_BODY"
comment_new_tip_fp="$(printf '%s' "$(cat "$COMMENT_BODY")" | openssl dgst -sha256 -r | awk '{print $1}')"
jq --arg fp "sha256:$comment_new_tip_fp" '.source_fingerprint_sha256 = $fp' "$AUTH_FILE" > "$AUTH_FILE.tmp"
mv "$AUTH_FILE.tmp" "$AUTH_FILE"
set +e
wrong_comment_new_tip_output="$(run_guard force-with-lease --expected-remote-tip abc123 --authorization-json "$AUTH_FILE" -- --force-with-lease=refs/heads/feature/test:abc123 origin refs/heads/feature/test:refs/heads/feature/test)"
wrong_comment_new_tip_status=$?
set -e
run_test "wrong_comment_new_tip_status" "1" "$wrong_comment_new_tip_status"
run_test "wrong_comment_new_tip_blocks" "untrusted_authorization_source" "$(guard_field "$wrong_comment_new_tip_output" PUSH_GUARD_REASON)"

write_auth force-with-lease lhpaul/ai-dev-framework-template refs/heads/feature/test abc123 lhpaul 2026-08-01T00:00:00Z
expired_comment_fp="$(printf '%s' "$(cat "$COMMENT_BODY")" | openssl dgst -sha256 -r | awk '{print $1}')"
jq --arg fp "sha256:$expired_comment_fp" '.source_fingerprint_sha256 = $fp | .expires_at = "2099-01-01T00:00:00Z"' "$AUTH_FILE" > "$AUTH_FILE.tmp"
mv "$AUTH_FILE.tmp" "$AUTH_FILE"
set +e
locally_extended_expiry_output="$(run_guard force-with-lease --expected-remote-tip abc123 --authorization-json "$AUTH_FILE" -- --force-with-lease=refs/heads/feature/test:abc123 origin refs/heads/feature/test:refs/heads/feature/test)"
locally_extended_expiry_status=$?
set -e
run_test "locally_extended_expiry_status" "1" "$locally_extended_expiry_status"
run_test "locally_extended_expiry_blocks" "untrusted_authorization_source" "$(guard_field "$locally_extended_expiry_output" PUSH_GUARD_REASON)"

write_auth force-with-lease lhpaul/ai-dev-framework-template refs/heads/feature/test abc123 lhpaul 2026-08-01T00:00:00Z
set +e
expired_authorization_output="$(run_guard force-with-lease --expected-remote-tip abc123 --authorization-json "$AUTH_FILE" -- --force-with-lease=refs/heads/feature/test:abc123 origin refs/heads/feature/test:refs/heads/feature/test)"
expired_authorization_status=$?
set -e
run_test "expired_authorization_status" "1" "$expired_authorization_status"
run_test "expired_authorization_blocks" "authorization_expired" "$(guard_field "$expired_authorization_output" PUSH_GUARD_REASON)"

export MOCK_EXISTING_CLAIM=other
write_auth
set +e
claimed_output="$(run_guard force-with-lease --expected-remote-tip abc123 --authorization-json "$AUTH_FILE" -- --force-with-lease=refs/heads/feature/test:abc123 origin refs/heads/feature/test:refs/heads/feature/test)"
claimed_status=$?
set -e
unset MOCK_EXISTING_CLAIM
run_test "existing_claim_status" "1" "$claimed_status"
run_test "existing_claim_blocks" "authorization_already_claimed" "$(guard_field "$claimed_output" PUSH_GUARD_REASON)"

export MOCK_LOCK_MODE=fail
write_auth
set +e
lock_fail_output="$(run_guard force-with-lease --expected-remote-tip abc123 --authorization-json "$AUTH_FILE" -- --force-with-lease=refs/heads/feature/test:abc123 origin refs/heads/feature/test:refs/heads/feature/test)"
lock_fail_status=$?
set -e
unset MOCK_LOCK_MODE
run_test "lock_failure_status" "2" "$lock_fail_status"
run_test "lock_failure_reason" "lock_claim_failed" "$(guard_field "$lock_fail_output" PUSH_GUARD_REASON)"

export MOCK_PR_COMMENT_MODE=fail
write_auth
set +e
claim_fail_output="$(run_guard force-with-lease --expected-remote-tip abc123 --authorization-json "$AUTH_FILE" -- --force-with-lease=refs/heads/feature/test:abc123 origin refs/heads/feature/test:refs/heads/feature/test)"
claim_fail_status=$?
set -e
unset MOCK_PR_COMMENT_MODE
run_test "claim_marker_failure_status" "2" "$claim_fail_status"
run_test "claim_marker_failure_reason" "claim_marker_failed" "$(guard_field "$claim_fail_output" PUSH_GUARD_REASON)"
run_test "claim_marker_failure_releases_lock" "3" "$(call_log_count 'api -X DELETE repos/lhpaul/ai-dev-framework-template/git/refs/tags/workflow-force-push-locks/')"

write_auth
export MOCK_PUSH_MODE=fail
set +e
push_fail_output="$(run_guard force-with-lease --expected-remote-tip abc123 --authorization-json "$AUTH_FILE" -- --force-with-lease=refs/heads/feature/test:abc123 origin refs/heads/feature/test:refs/heads/feature/test)"
push_fail_status=$?
set -e
unset MOCK_PUSH_MODE
run_test "conditional_failure_status" "1" "$push_fail_status"
run_test "conditional_failure_blocks" "conditional_update_failed" "$(guard_field "$push_fail_output" PUSH_GUARD_REASON)"
run_test "conditional_failure_unconsumed" "false" "$(guard_field "$push_fail_output" AUTHORIZATION_CONSUMED)"
run_test "conditional_failure_rolled_back_marker" "1" "$(file_count 'state=rolled_back' "$CLAIM_BODY")"
run_test "conditional_failure_releases_lock" "4" "$(call_log_count 'api -X DELETE repos/lhpaul/ai-dev-framework-template/git/refs/tags/workflow-force-push-locks/')"

export MOCK_REMOTE_REF=fail
set +e
lookup_fail_output="$(run_guard normal -- origin feature/test)"
lookup_fail_status=$?
set -e
run_test "remote_lookup_failure_status" "2" "$lookup_fail_status"
run_test "remote_lookup_failure_reason" "remote_lookup_failed" "$(guard_field "$lookup_fail_output" PUSH_GUARD_REASON)"

export MOCK_REMOTE_REF=published MOCK_REMOTE_MODE=mismatch
set +e
remote_mismatch_output="$(run_guard normal -- origin feature/test)"
remote_mismatch_status=$?
set -e
run_test "remote_mismatch_status" "2" "$remote_mismatch_status"
run_test "remote_mismatch_reason" "remote_repo_mismatch" "$(guard_field "$remote_mismatch_output" PUSH_GUARD_REASON)"

echo ""
echo "=== Summary ==="
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"

if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi
