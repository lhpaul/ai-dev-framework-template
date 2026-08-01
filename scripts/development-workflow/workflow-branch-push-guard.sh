#!/usr/bin/env bash
# Guard workflow PR branch pushes so shared history is not rewritten without
# exact, trusted, single-use human authorization.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  workflow-branch-push-guard.sh --repo-root <path> --remote <name> \
    --repo <owner/repo> --branch-ref refs/heads/<branch> \
    --mode normal|force|force-with-lease --pr <number> \
    [--expected-remote-tip <sha>] [--authorization-json <file>] \
    -- <git-push-args>

Exit codes:
  0  guarded push succeeded
  1  policy blocked before remote mutation
  2  helper, input, authentication, or trusted-source verification failure
EOF
}

repo_root=""
remote=""
canonical_repo=""
branch_ref=""
mode=""
pr_number=""
expected_remote_tip=""
authorization_json=""
push_args=()

die() {
  printf 'PUSH_GUARD_RESULT=helper_failed\n'
  printf 'PUSH_GUARD_REASON=%s\n' "$1"
  exit 2
}

block() {
  printf 'PUSH_GUARD_RESULT=blocked\n'
  printf 'PUSH_GUARD_REASON=%s\n' "$1"
  printf 'BRANCH_REF=%s\n' "${branch_ref:-}"
  printf 'EXPECTED_REMOTE_TIP=%s\n' "${expected_remote_tip:-}"
  printf 'AUTHORIZATION_CONSUMED=false\n'
  exit 1
}

allowed() {
  printf 'PUSH_GUARD_RESULT=allowed\n'
  printf 'PUSH_GUARD_REASON=%s\n' "$1"
  printf 'BRANCH_REF=%s\n' "$branch_ref"
  printf 'EXPECTED_REMOTE_TIP=%s\n' "${expected_remote_tip:-}"
  printf 'AUTHORIZATION_CONSUMED=%s\n' "$2"
}

require_value() {
  local option="$1"
  local value="${2:-}"
  [ -n "$value" ] || die "${option}_missing_value"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo-root)
      require_value repo_root "${2:-}"
      repo_root="$2"
      shift 2
      ;;
    --remote)
      require_value remote "${2:-}"
      remote="$2"
      shift 2
      ;;
    --repo)
      require_value repo "${2:-}"
      canonical_repo="$2"
      shift 2
      ;;
    --branch-ref)
      require_value branch_ref "${2:-}"
      branch_ref="$2"
      shift 2
      ;;
    --mode)
      require_value mode "${2:-}"
      mode="$2"
      shift 2
      ;;
    --pr)
      require_value pr "${2:-}"
      pr_number="$2"
      shift 2
      ;;
    --expected-remote-tip)
      require_value expected_remote_tip "${2:-}"
      expected_remote_tip="$2"
      shift 2
      ;;
    --authorization-json)
      require_value authorization_json "${2:-}"
      authorization_json="$2"
      shift 2
      ;;
    --)
      shift
      push_args=("$@")
      break
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "invalid_argument"
      ;;
  esac
done

[ -n "$repo_root" ] || die "missing_repo_root"
[ -d "$repo_root/.git" ] || git -C "$repo_root" rev-parse --git-dir >/dev/null 2>&1 || die "invalid_repo_root"
[ -n "$remote" ] || die "missing_remote"
case "$canonical_repo" in
  */*) ;;
  *) die "invalid_repo" ;;
esac
case "$branch_ref" in
  refs/heads/*) ;;
  *) die "invalid_branch_ref" ;;
esac
case "$mode" in
  normal|force|force-with-lease) ;;
  *) die "invalid_mode" ;;
esac
case "$pr_number" in
  ''|*[!0-9]*) die "invalid_pr_number" ;;
esac
[ "${#push_args[@]}" -gt 0 ] || die "missing_push_args"

remote_url="$(git -C "$repo_root" remote get-url "$remote" 2>/dev/null)" || die "remote_url_unavailable"

github_repo_from_url() {
  local url="$1"
  local path=""
  case "$url" in
    https://github.com/*)
      path="${url#https://github.com/}"
      ;;
    https://*@github.com/*)
      path="${url#https://*@github.com/}"
      ;;
    git@github.com:*)
      path="${url#git@github.com:}"
      ;;
    ssh://git@github.com/*)
      path="${url#ssh://git@github.com/}"
      ;;
    *)
      return 1
      ;;
  esac
  path="${path%.git}"
  path="${path%%/*/*/*}"
  case "$path" in
    */*) printf '%s\n' "$path" ;;
    *) return 1 ;;
  esac
}

remote_repo="$(github_repo_from_url "$remote_url" 2>/dev/null || true)"
[ -n "$remote_repo" ] || die "remote_repo_unresolved"
[ "$remote_repo" = "$canonical_repo" ] || die "remote_repo_mismatch"

remote_tip=""
ls_remote_output=""
set +e
ls_remote_output="$(git -C "$repo_root" ls-remote --exit-code "$remote" "$branch_ref" 2>/dev/null)"
ls_remote_status=$?
set -e
case "$ls_remote_status" in
  0)
    remote_tip="$(printf '%s\n' "$ls_remote_output" | awk 'NR == 1 {print $1}')"
    [ -n "$remote_tip" ] || die "remote_tip_unreadable"
    ;;
  2)
    remote_tip=""
    ;;
  *)
    die "remote_lookup_failed"
    ;;
esac

if [ "$mode" = "normal" ]; then
  if [ -z "$remote_tip" ]; then
    push_reason="unpublished_ref_allowed"
  else
    push_reason="normal_push_allowed"
  fi
  git -C "$repo_root" push "${push_args[@]}" || die "push_failed"
  allowed "$push_reason" "false"
  exit 0
fi

[ -n "$expected_remote_tip" ] || die "missing_expected_remote_tip"
[ -n "$authorization_json" ] || block "missing_authorization"
[ -f "$authorization_json" ] || die "authorization_file_unreadable"
[ -n "$remote_tip" ] || block "remote_tip_mismatch"
[ "$remote_tip" = "$expected_remote_tip" ] || block "remote_tip_mismatch"

json_get() {
  local path="$1"
  jq -r "$path // empty" "$authorization_json" 2>/dev/null
}

auth_schema_version="$(json_get '.schema_version')"
authorization_id="$(json_get '.authorization_id')"
auth_repo="$(json_get '.canonical_repo')"
auth_pr="$(json_get '.pr_number | tostring')"
auth_branch_ref="$(json_get '.branch_ref')"
auth_action="$(json_get '.action')"
auth_expected_tip="$(json_get '.expected_remote_tip')"
auth_operator="$(json_get '.operator_login')"
auth_authorized_by="$(json_get '.authorized_by')"
auth_source_kind="$(json_get '.source_kind')"
auth_source_id="$(json_get '.source_id | tostring')"
auth_source_fingerprint="$(json_get '.source_fingerprint_sha256')"
auth_expires_at="$(json_get '.expires_at')"
auth_single_use="$(json_get '.single_use | tostring')"

for required in auth_schema_version authorization_id auth_repo auth_pr auth_branch_ref auth_action auth_expected_tip auth_operator auth_authorized_by auth_source_kind auth_source_id auth_source_fingerprint auth_expires_at auth_single_use; do
  [ -n "${!required}" ] || block "authorization_scope_mismatch"
done

[ "$auth_schema_version" = "1" ] || block "authorization_scope_mismatch"
[ "$auth_repo" = "$canonical_repo" ] || block "authorization_scope_mismatch"
[ "$auth_pr" = "$pr_number" ] || block "authorization_scope_mismatch"
[ "$auth_branch_ref" = "$branch_ref" ] || block "authorization_scope_mismatch"
[ "$auth_action" = "$mode" ] || block "authorization_scope_mismatch"
[ "$auth_expected_tip" = "$expected_remote_tip" ] || block "authorization_scope_mismatch"
[ "$auth_single_use" = "true" ] || block "authorization_scope_mismatch"
[ "$auth_authorized_by" = "$auth_operator" ] || block "authorization_scope_mismatch"

if ! python3 - "$auth_expires_at" <<'PY' >/dev/null 2>&1
from datetime import datetime, timezone
import sys
raw = sys.argv[1].replace("Z", "+00:00")
expires = datetime.fromisoformat(raw)
if expires.tzinfo is None:
    expires = expires.replace(tzinfo=timezone.utc)
raise SystemExit(0 if expires > datetime.now(timezone.utc) else 1)
PY
then
  block "authorization_expired"
fi

operator_login="$(gh api user --jq '.login' 2>/dev/null)" || die "gh_user_unavailable"
[ "$operator_login" = "$auth_operator" ] || block "authorization_scope_mismatch"

case "$auth_source_kind" in
  github_comment|github_pr_comment|github_issue_comment)
    comment_json="$(gh api "repos/${canonical_repo}/issues/comments/${auth_source_id}" 2>/dev/null)" || die "trusted_source_unavailable"
    comment_author="$(printf '%s\n' "$comment_json" | jq -r '.user.login // empty')"
    comment_body="$(printf '%s\n' "$comment_json" | jq -r '.body // empty')"
    [ "$comment_author" = "$auth_authorized_by" ] || block "untrusted_authorization_source"
    printf '%s\n' "$comment_body" | grep -Fq "$authorization_id" || block "untrusted_authorization_source"
    computed_fingerprint="$(printf '%s' "$comment_body" | openssl dgst -sha256 -r | awk '{print $1}')"
    case "$auth_source_fingerprint" in
      sha256:*) expected_fingerprint="${auth_source_fingerprint#sha256:}" ;;
      *) expected_fingerprint="$auth_source_fingerprint" ;;
    esac
    [ "$computed_fingerprint" = "$expected_fingerprint" ] || block "untrusted_authorization_source"
    ;;
  *)
    block "untrusted_authorization_source"
    ;;
esac

claim_run_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
claim_body="workflow-force-push-authorization-claim
authorization_id=${authorization_id}
canonical_repo=${canonical_repo}
branch_ref=${branch_ref}
expected_remote_tip=${expected_remote_tip}
run_id=${claim_run_id}
state=claimed"
gh pr comment "$pr_number" --body "$claim_body" >/dev/null || die "claim_marker_failed"

comments_json="$(gh api --paginate --slurp "repos/${canonical_repo}/issues/${pr_number}/comments?per_page=100" 2>/dev/null)" || die "claim_marker_read_failed"
winner_run_id="$(printf '%s\n' "$comments_json" | jq -r --arg auth "$authorization_id" '
  [ .[][]? | select((.body // "") | contains("workflow-force-push-authorization-claim") and contains("authorization_id=" + $auth) and contains("state=claimed")) ] |
  sort_by(.created_at, .id) |
  .[0].body // "" |
  (try capture("run_id=(?<run_id>[^\\n]+)").run_id catch empty)
' 2>/dev/null)" || die "claim_marker_parse_failed"
[ "$winner_run_id" = "$claim_run_id" ] || block "authorization_already_claimed"

set +e
git -C "$repo_root" push "${push_args[@]}"
push_status=$?
set -e
if [ "$push_status" -ne 0 ]; then
  rollback_body="workflow-force-push-authorization-claim
authorization_id=${authorization_id}
canonical_repo=${canonical_repo}
branch_ref=${branch_ref}
expected_remote_tip=${expected_remote_tip}
run_id=${claim_run_id}
state=rolled_back
reason=conditional_update_failed"
  gh pr comment "$pr_number" --body "$rollback_body" >/dev/null 2>&1 || true
  block "conditional_update_failed"
fi

consumed_body="workflow-force-push-authorization-claim
authorization_id=${authorization_id}
canonical_repo=${canonical_repo}
branch_ref=${branch_ref}
expected_remote_tip=${expected_remote_tip}
run_id=${claim_run_id}
state=consumed"
gh pr comment "$pr_number" --body "$consumed_body" >/dev/null 2>&1 || true
allowed "authorized_once" "true"
