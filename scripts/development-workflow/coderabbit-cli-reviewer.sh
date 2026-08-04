#!/usr/bin/env bash
# coderabbit-cli-reviewer.sh - CodeRabbit CLI reviewer for Step 7.
#
# Wraps CodeRabbit CLI agent-mode review output and emits the standard
# companion-script key=value contract consumed by pr-review-loop.sh.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/development-workflow/workflow-lib.sh
source "$SCRIPT_DIR/workflow-lib.sh"

usage() {
  cat >&2 <<'EOF'
Usage: coderabbit-cli-reviewer.sh <pr_number> <owner> <repo> [--timeout <seconds>] [--repo-root <path>]

Options:
  --timeout <seconds>  Maximum seconds to wait for the CodeRabbit CLI.
                       Defaults to CODERABBIT_CLI_REVIEW_TIMEOUT or 120.
  --repo-root <path>   Repository checkout to review. When supplied, HEAD must
                       match the pull request head SHA before the CLI is run.
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

emit_rate_limited_result() {
  echo "WARN: CodeRabbit CLI rate limit detected" >&2
  if [ "$RATE_LIMIT_POLICY" = "strict" ]; then
    print_result escalate 0 0 0 rate_limited "rate_limited"
    exit 2
  fi
  print_result skipped 0 0 0 rate_limited "rate_limited"
  exit 3
}

valid_slug_component() {
  case "$1" in
    ''|*[!A-Za-z0-9._-]*) return 1 ;;
    *) return 0 ;;
  esac
}

AUTH_PATTERN='unauthori[sz]ed|forbidden|(^|[^[:alnum:]_])(401|403)([^[:alnum:]_]|$)|auth(entication)?[[:space:]_-]+(failed|required|error|unavailable)|login[[:space:]_-]+(failed|required)'

if [ "$#" -lt 3 ]; then
  usage
  exit 3
fi

PR_NUMBER="$1"
OWNER="$2"
REPO="$3"
shift 3

case "$PR_NUMBER" in
  ''|0|*[!0-9]*)
    echo "ERROR: PR number '$PR_NUMBER' is not a valid positive integer" >&2
    exit 3
    ;;
esac
if ! valid_slug_component "$OWNER"; then
  echo "ERROR: owner '$OWNER' contains invalid characters" >&2
  exit 3
fi
if ! valid_slug_component "$REPO"; then
  echo "ERROR: repo '$REPO' contains invalid characters" >&2
  exit 3
fi

TIMEOUT="${CODERABBIT_CLI_REVIEW_TIMEOUT:-120}"
REPO_ROOT=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --timeout)
      if [ "$#" -lt 2 ] || [ -z "${2:-}" ]; then
        echo "ERROR: --timeout requires a value" >&2
        exit 3
      fi
      TIMEOUT="$2"
      shift 2
      ;;
    --repo-root)
      if [ "$#" -lt 2 ] || [ -z "${2:-}" ]; then
        echo "ERROR: --repo-root requires a value" >&2
        exit 3
      fi
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
      exit 3
      ;;
  esac
done

case "$TIMEOUT" in
  ''|0|*[!0-9]*)
    echo "ERROR: --timeout value '$TIMEOUT' is not a positive integer" >&2
    exit 3
    ;;
esac

rate_limit_policy_from_file() {
  local config_file="$1"
  local value=""
  if [ -n "$config_file" ] && [ -f "$config_file" ]; then
    value="$(
      awk '
        function trim(v) {
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
          gsub(/^["'"'"']|["'"'"']$/, "", v)
          return v
        }
        /^review:[[:space:]]*$/ { in_review=1; next }
        in_review && /^[^[:space:]#].*:[[:space:]]*/ { in_review=0 }
        in_review && /^[[:space:]][[:space:]]coderabbit_cli:[[:space:]]*$/ { in_cli=1; next }
        in_cli && /^[[:space:]][[:space:]][^[:space:]#].*:[[:space:]]*/ { in_cli=0 }
        in_cli && /^[[:space:]][[:space:]][[:space:]][[:space:]]rate_limit_policy:[[:space:]]*/ {
          line = $0
          sub(/^[[:space:]]*rate_limit_policy:[[:space:]]*/, "", line)
          sub(/[[:space:]]+#.*$/, "", line)
          print trim(line)
          exit
        }
      ' "$config_file"
    )"
  fi
  printf '%s' "$value"
}

rate_limit_policy_from_config() {
  local config_file
  local local_file
  local value=""

  local_file="$(workflow_local_config_file 2>/dev/null || true)"
  if [ -n "$local_file" ] && [ -f "$local_file" ]; then
    value="$(rate_limit_policy_from_file "$local_file")"
  fi

  if [ -z "$value" ]; then
    config_file="$(workflow_effective_config_file 2>/dev/null || true)"
    value="$(rate_limit_policy_from_file "$config_file")"
  fi

  printf '%s' "$value"
}

RATE_LIMIT_POLICY="${CODERABBIT_CLI_RATE_LIMIT_POLICY:-}"
if [ -z "$RATE_LIMIT_POLICY" ]; then
  RATE_LIMIT_POLICY="$(rate_limit_policy_from_config)"
fi
RATE_LIMIT_POLICY="${RATE_LIMIT_POLICY:-warn}"
case "$RATE_LIMIT_POLICY" in
  warn|strict) ;;
  *)
    echo "WARN: invalid CodeRabbit CLI rate-limit policy '$RATE_LIMIT_POLICY'; defaulting to warn" >&2
    RATE_LIMIT_POLICY="warn"
    ;;
esac

BASE_BRANCH=""
HEAD_BRANCH=""
HEAD_SHA=""
if command -v gh >/dev/null 2>&1; then
  pr_json=""
  if pr_json="$(gh pr view "$PR_NUMBER" --repo "$OWNER/$REPO" --json baseRefName,headRefName,headRefOid 2>/dev/null)"; then
    BASE_BRANCH="$(printf '%s\n' "$pr_json" | jq -r '.baseRefName // empty' 2>/dev/null || true)"
    HEAD_BRANCH="$(printf '%s\n' "$pr_json" | jq -r '.headRefName // empty' 2>/dev/null || true)"
    HEAD_SHA="$(printf '%s\n' "$pr_json" | jq -r '.headRefOid // empty' 2>/dev/null || true)"
  fi
fi
BASE_BRANCH="${BASE_BRANCH:-develop}"

if [ -n "$REPO_ROOT" ]; then
  if [ ! -d "$REPO_ROOT/.git" ] && ! git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    echo "ERROR: --repo-root is not a Git checkout: $REPO_ROOT" >&2
    print_result escalate 0 0 0 invalid_repo_root "invalid_repo_root"
    exit 2
  fi
  if [ -z "$HEAD_SHA" ]; then
    echo "ERROR: could not resolve pull request head SHA for #$PR_NUMBER" >&2
    print_result escalate 0 0 0 head_sha_unavailable "head_sha_unavailable"
    exit 2
  fi
  if ! CURRENT_SHA="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null)"; then
    CURRENT_SHA=""
  fi
  if [ "$CURRENT_SHA" != "$HEAD_SHA" ]; then
    echo "ERROR: checkout HEAD does not match PR head ($CURRENT_SHA != $HEAD_SHA)" >&2
    print_result escalate 0 0 0 checkout_head_mismatch "checkout_head_mismatch"
    exit 2
  fi
  cd "$REPO_ROOT"
fi

if command -v cr >/dev/null 2>&1; then
  CODERABBIT_CMD="cr"
  CODERABBIT_SUBCOMMAND=""
elif command -v coderabbit >/dev/null 2>&1; then
  CODERABBIT_CMD="coderabbit"
  CODERABBIT_SUBCOMMAND="review"
else
  echo "INFO: CodeRabbit CLI not found on PATH" >&2
  print_result skipped 0 0 0 unavailable "unavailable"
  exit 3
fi
print_kv CLI_COMMAND "$CODERABBIT_CMD"
print_kv BASE_BRANCH "$BASE_BRANCH"
[ -n "$HEAD_BRANCH" ] && print_kv HEAD_BRANCH "$HEAD_BRANCH"

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

stdout_file="$(mktemp)"
stderr_file="$(mktemp)"
cleanup() {
  rm -f "${stdout_file:-}" "${stderr_file:-}"
}
trap cleanup EXIT

set +e
if [ -n "$CODERABBIT_SUBCOMMAND" ]; then
  run_with_timeout "$TIMEOUT" "$stdout_file" "$stderr_file" \
    "$CODERABBIT_CMD" "$CODERABBIT_SUBCOMMAND" --agent --base "$BASE_BRANCH"
else
  run_with_timeout "$TIMEOUT" "$stdout_file" "$stderr_file" \
    "$CODERABBIT_CMD" --agent --base "$BASE_BRANCH"
fi
cli_exit=$?
set -e

cli_stdout="$(cat "$stdout_file" 2>/dev/null || true)"
cli_stderr="$(cat "$stderr_file" 2>/dev/null || true)"
combined_output="${cli_stdout}
${cli_stderr}"

if [ "$cli_exit" -eq 124 ]; then
  echo "WARN: CodeRabbit CLI timed out after ${TIMEOUT}s" >&2
  print_result skipped 0 0 0 timeout "timeout"
  exit 3
fi

if [ -z "$(printf '%s' "$cli_stdout" | tr -d '[:space:]')" ]; then
  echo "WARN: CodeRabbit CLI produced no JSON output (exit $cli_exit)" >&2
  if printf '%s\n' "$combined_output" | grep -Eiq 'rate[ -]?limit|too many requests|HTTP[[:space:]]*429'; then
    emit_rate_limited_result
  elif printf '%s\n' "$cli_stderr" | grep -Eiq "$AUTH_PATTERN"; then
    print_result skipped 0 0 0 unauthorized "unavailable"
  else
    print_result skipped 0 0 0 no_output "skipped"
  fi
  exit 3
fi

normalized_stdout_json="$(
  printf '%s\n' "$cli_stdout" | jq -sc '
    def event_finding:
      select(((.type // "") | tostring | ascii_downcase) == "finding")
      | (.finding // .data // .);
    if length == 1 then
      .[0] as $one
      | if (($one | type) == "object" and (($one.type // "") | tostring | ascii_downcase) == "finding") then
          {findings: [($one | event_finding)]}
        else
          $one
        end
    else
      {findings: [.[] | objects | event_finding]}
    end
  ' 2>/dev/null
)" || normalized_stdout_json=""

parse_result="$(
  printf '%s\n' "$normalized_stdout_json" | jq -r '
    def walk_scalars:
      if type == "object" then .[] | walk_scalars
      elif type == "array" then .[] | walk_scalars
      else . end;
    def finding_arrays:
      if type == "array" then
        .
      else
        [
          .findings?, .comments?, .issues?, .results?, .reviews?, .feedback?,
          .review.findings?, .review.comments?, .review.issues?,
          .data.findings?, .data.comments?, .data.issues?
        ]
        | map(select(type == "array"))
        | if length == 0 then null else add end
      end;
    def severity_text:
      [
        .severity?, .level?, .category?, .type?, .priority?, .impact?,
        .classification?, .kind?, .status?, .state?
      ]
      | map(select(type == "string"))
      | join(" ")
      | ascii_downcase;
    def blocking:
      severity_text as $s
      | ($s | test("critical|blocker|blocking|error|bug|security|vulnerability|high|major|must.fix|changes.requested|needs.fixes|needs.changes"));
    def advisory:
      severity_text as $s
      | ($s | test("minor|low|medium|suggestion|advisory|nit|nitpick|trivial|warning|info|informational|style"));
    . as $root
    | ($root | finding_arrays) as $findings
    | if ($findings | type) != "array" then
        "PARSE_STATUS=missing_findings"
      else
        ($findings | length) as $comments
        | ($findings | map(select(blocking)) | length) as $blocking
        | ($findings | map(select((blocking | not) and advisory)) | length) as $explicit_advisory
        | ($comments - $blocking) as $suggestions
        | if ($findings | map(select((blocking | not) and (advisory | not))) | length) > 0 then
            "PARSE_STATUS=ambiguous"
          else
            "PARSE_STATUS=ok\nCOMMENT_COUNT=\($comments)\nBLOCKING_COUNT=\($blocking)\nSUGGESTION_COUNT=\($suggestions)\nEXPLICIT_ADVISORY_COUNT=\($explicit_advisory)"
          end
      end
  ' 2>/dev/null
)" || parse_result=""
blocking_findings_json="$(
  printf '%s\n' "$normalized_stdout_json" | jq -c '
    def finding_arrays:
      if type == "array" then
        .
      else
        [
          .findings?, .comments?, .issues?, .results?, .reviews?, .feedback?,
          .review.findings?, .review.comments?, .review.issues?,
          .data.findings?, .data.comments?, .data.issues?
        ]
        | map(select(type == "array"))
        | if length == 0 then [] else add end
      end;
    def severity_text:
      [
        .severity?, .level?, .category?, .type?, .priority?, .impact?,
        .classification?, .kind?, .status?, .state?
      ]
      | map(select(type == "string"))
      | join(" ")
      | ascii_downcase;
    def blocking:
      severity_text as $s
      | ($s | test("critical|blocker|blocking|error|bug|security|vulnerability|high|major|must.fix|changes.requested|needs.fixes|needs.changes"));
    def text_value:
      [
        .message?, .body?, .description?, .title?, .summary?, .comment?, .text?,
        .finding.message?, .finding.body?, .finding.description?
      ]
      | map(select(type == "string" and length > 0))
      | .[0] // "";
    def path_value:
      [
        .path?, .file?, .filename?, .filepath?, .filePath?,
        .location.path?, .location.file?, .position.path?
      ]
      | map(select(type == "string" and length > 0))
      | .[0] // "";
    def line_value:
      [
        .line?, .startLine?, .start_line?, .location.line?, .location.startLine?,
        .position.line?
      ]
      | map(select((type == "number") or (type == "string" and length > 0)))
      | .[0] // "";
    [finding_arrays[] | select(blocking) | {path: path_value, line: (line_value | tostring), body: text_value}]
  ' 2>/dev/null
)" || blocking_findings_json="[]"

parse_status="$(printf '%s\n' "$parse_result" | awk -F= '$1 == "PARSE_STATUS" { print $2; exit }')"
rate_limit_output=false
if printf '%s\n' "$combined_output" | grep -Eiq 'rate[ -]?limit|too many requests|HTTP[[:space:]]*429'; then
  rate_limit_output=true
fi
auth_output=false
if printf '%s\n' "$cli_stderr" | grep -Eiq "$AUTH_PATTERN"; then
  auth_output=true
elif [ -n "$normalized_stdout_json" ] && printf '%s\n' "$normalized_stdout_json" | jq -e '
  def auth_text:
    test("unauthori[sz]ed|forbidden|(^|[^[:alnum:]_])(401|403)([^[:alnum:]_]|$)|auth(entication)?[[:space:]_-]+(failed|required|error|unavailable)|login[[:space:]_-]+(failed|required)"; "i");
  if type == "object" then
    [(.error? // empty), (.reason? // empty), (.status? // empty)]
    | map(select(type == "string"))
    | any(auth_text)
  else
    false
  end
' >/dev/null 2>&1; then
  auth_output=true
fi
case "$parse_status" in
  ok)
    comment_count="$(printf '%s\n' "$parse_result" | awk -F= '$1 == "COMMENT_COUNT" { print $2; exit }')"
    blocking_count="$(printf '%s\n' "$parse_result" | awk -F= '$1 == "BLOCKING_COUNT" { print $2; exit }')"
    suggestion_count="$(printf '%s\n' "$parse_result" | awk -F= '$1 == "SUGGESTION_COUNT" { print $2; exit }')"
    comment_count="${comment_count:-0}"
    blocking_count="${blocking_count:-0}"
    suggestion_count="${suggestion_count:-0}"
    if [ "$comment_count" -eq 0 ] && [ "$rate_limit_output" = true ]; then
      emit_rate_limited_result
    fi
    if [ "$comment_count" -eq 0 ] && [ "$auth_output" = true ]; then
      echo "WARN: CodeRabbit CLI authentication appears unavailable" >&2
      print_result skipped 0 0 0 unauthorized "unavailable"
      exit 3
    fi
    if [ "$blocking_count" -gt 0 ]; then
      print_result needs_fixes "$comment_count" "$blocking_count" "$suggestion_count"
      index=1
      while IFS= read -r blocking_finding; do
        [ -n "$blocking_finding" ] || continue
        print_kv "BLOCKING_${index}_PATH" "$(printf '%s\n' "$blocking_finding" | jq -r '.path // ""')"
        print_kv "BLOCKING_${index}_LINE" "$(printf '%s\n' "$blocking_finding" | jq -r '.line // ""')"
        print_kv_escaped "BLOCKING_${index}_BODY" "$(printf '%s\n' "$blocking_finding" | jq -r '.body // ""')"
        index=$((index + 1))
      done < <(printf '%s\n' "$blocking_findings_json" | jq -c '.[]?' 2>/dev/null)
      exit 1
    fi
    if [ "$cli_exit" -ne 0 ]; then
      echo "WARN: CodeRabbit CLI exited non-zero after producing non-blocking JSON (exit $cli_exit)" >&2
      print_result skipped 0 0 0 cli_failed "skipped"
      exit 3
    fi
    print_result clean "$comment_count" 0 "$suggestion_count"
    exit 0
    ;;
  missing_findings)
    if [ "$rate_limit_output" = true ]; then
      emit_rate_limited_result
    elif [ "$auth_output" = true ]; then
      echo "WARN: CodeRabbit CLI authentication appears unavailable" >&2
      print_result skipped 0 0 0 unauthorized "unavailable"
    else
      echo "WARN: CodeRabbit CLI JSON did not contain a recognized findings array" >&2
      print_result skipped 0 0 0 invalid_json "skipped"
    fi
    exit 3
    ;;
  ambiguous)
    echo "WARN: CodeRabbit CLI JSON contained findings with ambiguous severity" >&2
    print_result skipped 0 0 0 ambiguous_output "skipped"
    exit 3
    ;;
  *)
    if [ "$rate_limit_output" = true ]; then
      emit_rate_limited_result
    elif [ "$auth_output" = true ]; then
      echo "WARN: CodeRabbit CLI authentication appears unavailable" >&2
      print_result skipped 0 0 0 unauthorized "unavailable"
    else
      echo "WARN: CodeRabbit CLI output was not recognized as valid JSON" >&2
      print_result skipped 0 0 0 invalid_json "skipped"
    fi
    exit 3
    ;;
esac
