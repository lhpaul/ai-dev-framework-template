#!/usr/bin/env bash
# local-ai-reviewer.sh - local-only reviewer for Step 7.
#
# Builds a bounded PR review context, invokes LOCAL_AI_REVIEWER_COMMAND, and
# emits the companion-script key=value contract consumed by pr-review-loop.sh.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/development-workflow/workflow-lib.sh
source "$SCRIPT_DIR/workflow-lib.sh"

usage() {
  cat >&2 <<'EOF'
Usage: local-ai-reviewer.sh <pr_number> <owner> <repo> [--timeout <seconds>] [--repo-root <path>]

Options:
  --timeout <seconds>  Maximum seconds to wait for LOCAL_AI_REVIEWER_COMMAND.
                       Defaults to LOCAL_AI_REVIEWER_TIMEOUT or 300.
  --repo-root <path>   Repository checkout to review. When supplied, HEAD must
                       match the pull request head SHA before review runs.

Environment:
  LOCAL_AI_REVIEWER_COMMAND         Required unless LOCAL_AI_REVIEWER_DISABLED=1.
                                    The command receives CONTEXT_BUNDLE_PATH,
                                    PR_NUMBER, OWNER, REPO, BASE_BRANCH,
                                    HEAD_BRANCH, and REVIEWED_HEAD in env.
  LOCAL_AI_REVIEWER_DISABLED=1      Emit RESULT=skipped / disabled_by_config.
  LOCAL_AI_REVIEWER_EVIDENCE_FILE   Optional path for a JSON evidence artifact.
  LOCAL_AI_REVIEWER_GRAPH_STRATEGY  none|auto|code-review-graph|graphify.
EOF
}

print_result() {
  local result="$1"
  local comment_count="$2"
  local blocking_count="$3"
  local suggestion_count="$4"
  local reason="${5:-}"
  local display_result="${6:-}"

  print_kv RESULT "$result"
  print_kv COMMENT_COUNT "$comment_count"
  print_kv BLOCKING_COUNT "$blocking_count"
  print_kv SUGGESTION_COUNT "$suggestion_count"
  [ -n "$reason" ] && print_kv REASON "$reason"
  [ -n "$display_result" ] && print_kv DISPLAY_RESULT "$display_result"
  return 0
}

valid_slug_component() {
  case "$1" in
    ''|*[!A-Za-z0-9._-]*) return 1 ;;
    *) return 0 ;;
  esac
}

normalize_github_remote_slug() {
  local raw="$1"
  local slug="$raw"

  slug="${slug#git@github.com:}"
  slug="${slug#ssh://git@github.com/}"
  slug="${slug#https://github.com/}"
  slug="${slug#http://github.com/}"
  slug="${slug#https://*@github.com/}"
  slug="${slug#http://*@github.com/}"
  slug="${slug%.git}"
  printf '%s\n' "$slug"
}

redact_github_remote_slug() {
  local raw="$1"
  local slug
  case "$raw" in
    http://*@github.com/*|https://*@github.com/*)
      printf '<redacted-remote>\n'
      return 0
      ;;
  esac
  slug="$(normalize_github_remote_slug "$raw")"
  case "$slug" in
    http://*|https://*|*@*) printf '<redacted-remote>\n' ;;
    *) printf '%s\n' "$slug" ;;
  esac
}

run_with_timeout() {
  local timeout_seconds="$1"
  local stdout_file="$2"
  local stderr_file="$3"
  shift 3

  if command -v timeout >/dev/null 2>&1; then
    timeout "$timeout_seconds" "$@" >"$stdout_file" 2>"$stderr_file"
    return $?
  fi

  "$@" >"$stdout_file" 2>"$stderr_file" &
  local child_pid=$!
  local elapsed=0
  while kill -0 "$child_pid" 2>/dev/null && [ "$elapsed" -lt "$timeout_seconds" ]; do
    sleep 1
    elapsed=$((elapsed + 1))
  done
  if [ "$elapsed" -ge "$timeout_seconds" ]; then
    kill "$child_pid" 2>/dev/null || true
    wait "$child_pid" 2>/dev/null || true
    return 124
  fi
  wait "$child_pid"
}

if [ "$#" -lt 3 ]; then
  usage
  exit 2
fi

PR_NUMBER="$1"
OWNER="$2"
REPO="$3"
shift 3

case "$PR_NUMBER" in
  ''|0|*[!0-9]*)
    echo "ERROR: PR number '$PR_NUMBER' is not a valid positive integer" >&2
    exit 2
    ;;
esac
if ! valid_slug_component "$OWNER"; then
  echo "ERROR: owner '$OWNER' contains invalid characters" >&2
  exit 2
fi
if ! valid_slug_component "$REPO"; then
  echo "ERROR: repo '$REPO' contains invalid characters" >&2
  exit 2
fi

TIMEOUT="${LOCAL_AI_REVIEWER_TIMEOUT:-300}"
REPO_ROOT=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --timeout)
      [ "$#" -ge 2 ] && [ -n "${2:-}" ] || { echo "ERROR: --timeout requires a value" >&2; exit 2; }
      TIMEOUT="$2"
      shift 2
      ;;
    --repo-root)
      [ "$#" -ge 2 ] && [ -n "${2:-}" ] || { echo "ERROR: --repo-root requires a value" >&2; exit 2; }
      REPO_ROOT="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown option '$1'" >&2
      usage
      exit 2
      ;;
  esac
done

case "$TIMEOUT" in
  ''|0|*[!0-9]*)
    echo "ERROR: --timeout value '$TIMEOUT' is not a positive integer" >&2
    exit 2
    ;;
esac

if [ "${LOCAL_AI_REVIEWER_DISABLED:-0}" = "1" ]; then
  print_result skipped 0 0 0 disabled_by_config disabled_by_config
  exit 3
fi

if [ -z "${LOCAL_AI_REVIEWER_COMMAND:-}" ]; then
  echo "ERROR: LOCAL_AI_REVIEWER_COMMAND is not configured" >&2
  print_result escalate 0 0 0 missing_command missing_command
  exit 2
fi

BASE_BRANCH=""
HEAD_BRANCH=""
HEAD_SHA=""
changed_files_json="[]"
diff_name_status=""
diff_stat=""
diff_fetch_failed=0
if command -v gh >/dev/null 2>&1; then
  pr_json=""
  if pr_json="$(gh pr view "$PR_NUMBER" --repo "$OWNER/$REPO" --json baseRefName,headRefName,headRefOid 2>/dev/null)"; then
    BASE_BRANCH="$(printf '%s\n' "$pr_json" | jq -r '.baseRefName // empty' 2>/dev/null || true)"
    HEAD_BRANCH="$(printf '%s\n' "$pr_json" | jq -r '.headRefName // empty' 2>/dev/null || true)"
    HEAD_SHA="$(printf '%s\n' "$pr_json" | jq -r '.headRefOid // empty' 2>/dev/null || true)"
  fi
  if ! diff_output="$(gh pr diff "$PR_NUMBER" --repo "$OWNER/$REPO" --name-only 2>/dev/null)"; then
    diff_output=""
    diff_fetch_failed=1
  fi
  if [ -n "$diff_output" ]; then
    changed_files_json="$(printf '%s\n' "$diff_output" | jq -R -s -c 'split("\n") | map(select(length > 0))')"
  fi
fi
if [ -z "$BASE_BRANCH" ]; then
  echo "ERROR: could not resolve pull request base branch for #$PR_NUMBER" >&2
  print_result escalate 0 0 0 base_branch_unavailable base_branch_unavailable
  exit 2
fi
if [ -z "$HEAD_SHA" ]; then
  echo "ERROR: could not resolve pull request head SHA for #$PR_NUMBER" >&2
  print_result escalate 0 0 0 head_sha_unavailable head_sha_unavailable
  exit 2
fi
if [ "$diff_fetch_failed" -ne 0 ]; then
  echo "ERROR: could not fetch pull request diff for #$PR_NUMBER" >&2
  print_result escalate 0 0 0 diff_unavailable diff_unavailable
  exit 2
fi

if [ -n "$REPO_ROOT" ]; then
  if [ ! -d "$REPO_ROOT/.git" ] && ! git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    echo "ERROR: --repo-root is not a Git checkout: $REPO_ROOT" >&2
    print_result escalate 0 0 0 invalid_repo_root invalid_repo_root
    exit 2
  fi
  if ! repo_root_origin="$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null)"; then
    repo_root_origin=""
  fi
  repo_root_slug="$(normalize_github_remote_slug "$repo_root_origin")"
  if [ "$repo_root_slug" != "$OWNER/$REPO" ]; then
    echo "ERROR: --repo-root origin does not match expected repository ($(redact_github_remote_slug "$repo_root_origin") != $OWNER/$REPO)" >&2
    print_result escalate 0 0 0 repo_root_mismatch repo_root_mismatch
    exit 2
  fi
  if ! CURRENT_SHA="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null)"; then
    CURRENT_SHA=""
  fi
  if [ "$CURRENT_SHA" != "$HEAD_SHA" ]; then
    echo "ERROR: checkout HEAD does not match PR head ($CURRENT_SHA != $HEAD_SHA)" >&2
    print_result escalate 0 0 0 head_mismatch head_mismatch
    exit 2
  fi
  cd "$REPO_ROOT"
fi

if git rev-parse --verify "origin/$BASE_BRANCH" >/dev/null 2>&1; then
  if diff_name_status_full="$(git diff --name-status --find-renames --find-copies "origin/$BASE_BRANCH...HEAD" 2>/dev/null)"; then
    diff_name_status="${diff_name_status_full:0:12000}"
  fi
  if diff_stat_full="$(git diff --stat --find-renames --find-copies "origin/$BASE_BRANCH...HEAD" 2>/dev/null)"; then
    diff_stat="${diff_stat_full:0:12000}"
  fi
fi

if [ ! -f REVIEW.md ]; then
  echo "ERROR: REVIEW.md is required for local review" >&2
  print_result escalate 0 0 0 review_contract_missing review_contract_missing
  exit 2
fi

graph_strategy="${LOCAL_AI_REVIEWER_GRAPH_STRATEGY:-none}"
graph_context="none"
case "$graph_strategy" in
  none|'') graph_context="none" ;;
  auto)
    if command -v code-review-graph >/dev/null 2>&1; then
      graph_context="code-review-graph"
    elif command -v graphify >/dev/null 2>&1; then
      graph_context="graphify"
    else
      graph_context="skipped"
    fi
    ;;
  code-review-graph)
    command -v code-review-graph >/dev/null 2>&1 && graph_context="code-review-graph" || graph_context="skipped"
    ;;
  graphify)
    command -v graphify >/dev/null 2>&1 && graph_context="graphify" || graph_context="skipped"
    ;;
  *)
    echo "ERROR: invalid LOCAL_AI_REVIEWER_GRAPH_STRATEGY '$graph_strategy'" >&2
    print_result escalate 0 0 0 malformed_output malformed_output
    exit 2
    ;;
esac

context_file="$(mktemp)"
stdout_file="$(mktemp)"
stderr_file="$(mktemp)"
cleanup() {
  rm -f "${context_file:-}" "${stdout_file:-}" "${stderr_file:-}"
}
trap cleanup EXIT

jq -n \
  --arg pr_number "$PR_NUMBER" \
  --arg owner "$OWNER" \
  --arg repo "$REPO" \
  --arg base_branch "$BASE_BRANCH" \
  --arg head_branch "$HEAD_BRANCH" \
  --arg reviewed_head "$HEAD_SHA" \
  --arg graph_context "$graph_context" \
  --arg diff_name_status "$diff_name_status" \
  --arg diff_stat "$diff_stat" \
  --argjson changed_files "$changed_files_json" \
  '{
    schema_version: "local_ai_reviewer_context.v1",
    pr_number: ($pr_number | tonumber),
    owner: $owner,
    repo: $repo,
    base_branch: $base_branch,
    head_branch: $head_branch,
    reviewed_head: $reviewed_head,
    changed_files: $changed_files,
    diff_name_status: $diff_name_status,
    diff_stat: $diff_stat,
    review_contract: "REVIEW.md",
    graph_context: $graph_context
  }' >"$context_file"

print_kv BASE_BRANCH "$BASE_BRANCH"
[ -n "$HEAD_BRANCH" ] && print_kv HEAD_BRANCH "$HEAD_BRANCH"
print_kv REVIEWED_HEAD "$HEAD_SHA"
print_kv GRAPH_CONTEXT "$graph_context"

set +e
CONTEXT_BUNDLE_PATH="$context_file" \
PR_NUMBER="$PR_NUMBER" \
OWNER="$OWNER" \
REPO="$REPO" \
BASE_BRANCH="$BASE_BRANCH" \
HEAD_BRANCH="$HEAD_BRANCH" \
REVIEWED_HEAD="$HEAD_SHA" \
  run_with_timeout "$TIMEOUT" "$stdout_file" "$stderr_file" sh -c "$LOCAL_AI_REVIEWER_COMMAND"
command_exit=$?
set -e

command_stdout="$(cat "$stdout_file" 2>/dev/null || true)"
command_stderr="$(cat "$stderr_file" 2>/dev/null || true)"

if [ "$command_exit" -eq 124 ]; then
  echo "WARN: local AI reviewer timed out after ${TIMEOUT}s" >&2
  print_result escalate 0 0 0 timeout timeout
  exit 2
fi

combined_output="${command_stdout}
${command_stderr}"
setup_probe_output="$command_stderr"
if ! printf '%s\n' "$command_stdout" | jq -e . >/dev/null 2>&1; then
  setup_probe_output="$combined_output"
fi
if printf '%s\n' "$setup_probe_output" | grep -Eiq 'missing[[:space:]_-]+model|model[[:space:]_-]+access|model.*unavailable'; then
  print_result escalate 0 0 0 missing_model_access missing_model_access
  exit 2
fi
if printf '%s\n' "$setup_probe_output" | grep -Eiq 'missing[[:space:]_-]+credentials|credentials[[:space:]_-]+missing|unauthori[sz]ed|forbidden|(^|[^[:alnum:]_])(401|403)([^[:alnum:]_]|$)'; then
  print_result escalate 0 0 0 missing_credentials missing_credentials
  exit 2
fi
if [ -z "$(printf '%s' "$command_stdout" | tr -d '[:space:]')" ]; then
  echo "WARN: local AI reviewer produced no machine output" >&2
  print_result escalate 0 0 0 malformed_output malformed_output
  exit 2
fi

parse_result="$(
  printf '%s\n' "$command_stdout" | jq -r --arg expected_head "$HEAD_SHA" '
    def findings:
      if (.findings? | type) == "array" then .findings
      elif (.comments? | type) == "array" then .comments
      elif (.issues? | type) == "array" then .issues
      else [] end;
    def text_value:
      [.body?, .message?, .description?, .title?, .summary?, .comment?, .text?]
      | map(select(type == "string" and length > 0)) | .[0] // "";
    def path_value:
      [.path?, .file?, .filename?, .filepath?, .location.path?]
      | map(select(type == "string" and length > 0)) | .[0] // "";
    def line_value:
      [.line?, .startLine?, .start_line?, .location.line?]
      | map(select((type == "number") or (type == "string" and length > 0))) | .[0] // "";
    def severity_text:
      [.severity?, .level?, .priority?, .type?, .classification?, .kind?, .result?]
      | map(select(type == "string")) | join(" ") | ascii_downcase;
    def scope_text:
      [.scope?, .disposition?, .policy?, .category?]
      | map(select(type == "string")) | join(" ") | ascii_downcase;
    def explicit_advisory:
      ((.advisory? == true) or (.decision_bound? == true) or (.scope_expanding? == true))
      or (scope_text | test("advisory|scope.expanding|decision.bound|optional|polish"));
    def blocking:
      (severity_text | test("critical|blocker|blocking|important|error|bug|security|vulnerability|high|major|must.fix|needs.fixes|changes.requested"))
      or (.clear_in_scope? == true)
      or (scope_text | test("clear.in.scope|in.scope|must.fix|needs.fixes"));
    def advisory:
      explicit_advisory or (severity_text | test("minor|low|nit|nitpick|trivial|info|informational|advisory|optional"));
    . as $root
    | ($root.result // "") as $raw_result
    | ($raw_result | tostring | ascii_downcase | gsub("-"; "_")) as $result
    | ($root.reviewed_head // $root.head_sha // $root.head // $expected_head) as $reviewed
    | if $reviewed != $expected_head then
        "PARSE_STATUS=head_mismatch"
      elif ($result != "" and (["clean","needs_fixes","needs_rerun","skipped","escalate"] | index($result) | not)) then
        "PARSE_STATUS=malformed"
      else
        (findings) as $findings
        | ($findings | length) as $comments
        | ($findings | map(select(blocking)) | length) as $blocking
        | ($findings | map(select((blocking | not) and advisory)) | length) as $advisory
        | ($findings | map(select((blocking | not) and (advisory | not))) | length) as $unknown
        | ($findings | map(select(blocking or ((blocking | not) and (advisory | not))))) as $blocking_findings
        | ($blocking_findings
            | to_entries
            | map(
                [
                  "BLOCKING_\(.key + 1)_PATH=\(.value | path_value)",
                  "BLOCKING_\(.key + 1)_LINE=\(.value | line_value)",
                  "BLOCKING_\(.key + 1)_BODY=\(.value | text_value | gsub("\n"; "\\n"))"
                ]
              )
            | flatten
            | join("\n")) as $blocking_lines
        | if $unknown > 0 then
            "PARSE_STATUS=ok\nRESULT=needs_fixes\nCOMMENT_COUNT=\($comments)\nBLOCKING_COUNT=\($blocking + $unknown)\nSUGGESTION_COUNT=\($advisory)\n\($blocking_lines)"
          elif $result == "clean" and $blocking > 0 then
            "PARSE_STATUS=ok\nRESULT=needs_fixes\nCOMMENT_COUNT=\($comments)\nBLOCKING_COUNT=\($blocking)\nSUGGESTION_COUNT=\($advisory)\n\($blocking_lines)"
          elif $result == "" then
            (if $blocking > 0 then "needs_fixes" else "clean" end) as $inferred
            | "PARSE_STATUS=ok\nRESULT=\($inferred)\nCOMMENT_COUNT=\($comments)\nBLOCKING_COUNT=\($blocking)\nSUGGESTION_COUNT=\($advisory)\n\(if $blocking > 0 then $blocking_lines else "" end)"
          else
            "PARSE_STATUS=ok\nRESULT=\($result)\nREASON=\($root.reason // "")\nCOMMENT_COUNT=\($comments)\nBLOCKING_COUNT=\($blocking)\nSUGGESTION_COUNT=\($advisory)\n\(if $result == "needs_fixes" then $blocking_lines else "" end)"
          end
      end
  ' 2>/dev/null
)" || parse_result=""

parse_status="$(printf '%s\n' "$parse_result" | awk -F= '$1 == "PARSE_STATUS" { print $2; exit }')"
case "$parse_status" in
  ok) ;;
  head_mismatch)
    print_result escalate 0 0 0 head_mismatch head_mismatch
    exit 2
    ;;
  *)
    echo "WARN: local AI reviewer output was malformed" >&2
    print_result escalate 0 0 0 malformed_output malformed_output
    exit 2
    ;;
esac

result="$(printf '%s\n' "$parse_result" | awk -F= '$1 == "RESULT" { print $2; exit }')"
reason="$(printf '%s\n' "$parse_result" | awk -F= '$1 == "REASON" { print $2; exit }')"
comment_count="$(printf '%s\n' "$parse_result" | awk -F= '$1 == "COMMENT_COUNT" { print $2; exit }')"
blocking_count="$(printf '%s\n' "$parse_result" | awk -F= '$1 == "BLOCKING_COUNT" { print $2; exit }')"
suggestion_count="$(printf '%s\n' "$parse_result" | awk -F= '$1 == "SUGGESTION_COUNT" { print $2; exit }')"

comment_count="${comment_count:-0}"
blocking_count="${blocking_count:-0}"
suggestion_count="${suggestion_count:-0}"
reason="${reason:-}"

write_evidence_file() {
  local final_result="$1"
  local final_reason="$2"
  local final_comment_count="$3"
  local final_blocking_count="$4"
  local final_suggestion_count="$5"

  [ -n "${LOCAL_AI_REVIEWER_EVIDENCE_FILE:-}" ] || return 0
  jq -n \
    --arg schema_version "local_ai_reviewer_evidence.v1" \
    --arg result "$final_result" \
    --arg reason "$final_reason" \
    --arg pr_number "$PR_NUMBER" \
    --arg owner "$OWNER" \
    --arg repo "$REPO" \
    --arg base_branch "$BASE_BRANCH" \
    --arg head_branch "$HEAD_BRANCH" \
    --arg reviewed_head "$HEAD_SHA" \
    --arg graph_context "$graph_context" \
    --arg diff_name_status "$diff_name_status" \
    --arg diff_stat "$diff_stat" \
    --argjson changed_files "$changed_files_json" \
    --argjson comment_count "$final_comment_count" \
    --argjson blocking_count "$final_blocking_count" \
    --argjson suggestion_count "$final_suggestion_count" \
    '{
      schema_version: $schema_version,
      result: $result,
      reason: $reason,
      pr_number: ($pr_number | tonumber),
      owner: $owner,
      repo: $repo,
      base_branch: $base_branch,
      head_branch: $head_branch,
      reviewed_head: $reviewed_head,
      graph_context: $graph_context,
      counts: {
        comments: $comment_count,
        blocking: $blocking_count,
        suggestions: $suggestion_count
      },
      context_summary: {
        changed_files: $changed_files,
        diff_name_status: $diff_name_status,
        diff_stat: $diff_stat
      }
    }' >"$LOCAL_AI_REVIEWER_EVIDENCE_FILE"
}

case "$result" in
  clean)
    if [ "$command_exit" -ne 0 ]; then
      write_evidence_file escalate malformed_output "$comment_count" "$blocking_count" "$suggestion_count"
      print_result escalate "$comment_count" "$blocking_count" "$suggestion_count" malformed_output malformed_output
      exit 2
    fi
    write_evidence_file clean "" "$comment_count" 0 "$suggestion_count"
    print_result clean "$comment_count" 0 "$suggestion_count"
    exit 0
    ;;
  needs_fixes)
    [ "$blocking_count" -eq 0 ] && blocking_count=1
    [ "$comment_count" -eq 0 ] && comment_count=1
    write_evidence_file needs_fixes local_ai_review_findings "$comment_count" "$blocking_count" "$suggestion_count"
    print_result needs_fixes "$comment_count" "$blocking_count" "$suggestion_count" local_ai_review_findings
    printf '%s\n' "$parse_result" | awk '/^BLOCKING_[0-9]+_(PATH|LINE|BODY)=/ { print }'
    exit 1
    ;;
  needs_rerun)
    write_evidence_file needs_rerun "${reason:-needs_rerun}" "$comment_count" "$blocking_count" "$suggestion_count"
    print_result needs_rerun "$comment_count" "$blocking_count" "$suggestion_count" "${reason:-needs_rerun}"
    exit 1
    ;;
  skipped)
    write_evidence_file skipped "${reason:-disabled_by_config}" "$comment_count" "$blocking_count" "$suggestion_count"
    print_result skipped "$comment_count" "$blocking_count" "$suggestion_count" "${reason:-disabled_by_config}" "${reason:-disabled_by_config}"
    exit 3
    ;;
  escalate)
    write_evidence_file escalate "${reason:-malformed_output}" "$comment_count" "$blocking_count" "$suggestion_count"
    print_result escalate "$comment_count" "$blocking_count" "$suggestion_count" "${reason:-malformed_output}" "${reason:-malformed_output}"
    exit 2
    ;;
  *)
    write_evidence_file escalate malformed_output 0 0 0
    print_result escalate 0 0 0 malformed_output malformed_output
    exit 2
    ;;
esac
