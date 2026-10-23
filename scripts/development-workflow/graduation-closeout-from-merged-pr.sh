#!/usr/bin/env bash
#
# Merge-time discovery wrapper for graduation closeout.
#
# When a graduation PR (develop-<slug> → develop) merges, discover slug/epic/
# deferral signals and invoke the same reconciler used by Protocol 05b Step 5.
#
# Usage:
#   ./scripts/development-workflow/graduation-closeout-from-merged-pr.sh \
#     --graduation-pr <number> \
#     [--epic <epic-id>] [--slug <slug>] \
#     [--exclude-issue <number>]... [--defer-epic-close] [--dry-run]
#
#   --epic  Optional override. GitHub issue number when tracker is
#           github_projects / github_issues. With provider linear, a native
#           Linear ID (e.g. LEA-326). A bare number with linear fails closed.
#
#   --dry-run  Forwarded to graduation-closeout.sh; prints planned mutations
#           and applies none.
#
# Exit codes:
#   0 — discovery succeeded and graduation-closeout.sh passed
#   1 — discovery failed closed, or child reconciler failed
#   64 — usage / invalid arguments

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=./workflow-lib.sh
# shellcheck disable=SC1091
. "$SCRIPT_DIR/workflow-lib.sh"
# shellcheck source=./graduation-closeout-lib.sh
# shellcheck disable=SC1091
. "$SCRIPT_DIR/graduation-closeout-lib.sh"
# shellcheck source=./closing-keyword-lib.sh
# shellcheck disable=SC1091
. "$SCRIPT_DIR/closing-keyword-lib.sh"

GRADUATION_PR=""
SLUG_OVERRIDE=""
EPIC_OVERRIDE=""
DEFER_EPIC_CLOSE=0
DRY_RUN=0
declare -a EXCLUDED_ISSUES=()

# Populated during discovery for the summary.
DISCOVERED_SLUG=""
DISCOVERED_EPIC=""
EPIC_SOURCE=""
SLUG_SOURCE=""
DEFER_SOURCE="none"
TRACKER_PROVIDER=""
CHILD_ARGV=()

usage() {
  cat >&2 <<'EOF'
Usage:
  graduation-closeout-from-merged-pr.sh --graduation-pr <number> \
    [--epic <epic-id>] [--slug <slug>] \
    [--exclude-issue <number>]... [--defer-epic-close] [--dry-run]

  --epic  GitHub issue number, or with issue_tracker.provider=linear a native
          Linear ID (e.g. LEA-326). Bare numbers fail closed under linear.
  --dry-run  Forwarded to graduation-closeout.sh (print mutations, apply none).
EOF
}

require_value() {
  local option="$1"
  if [ "$#" -lt 2 ] || [ -z "${2:-}" ] || [ "${2#--}" != "$2" ]; then
    echo "$option requires a value." >&2
    usage
    exit 64
  fi
}

is_positive_int() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
    0*) return 1 ;;
    *) return 0 ;;
  esac
}

is_linear_issue_id() {
  [[ "$1" =~ ^[A-Z][A-Z0-9_]*-[0-9]+$ ]]
}

is_valid_slug() {
  case "$1" in
    ''|*[^a-zA-Z0-9._-]*) return 1 ;;
    *) return 0 ;;
  esac
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --graduation-pr)
      require_value "$@"
      GRADUATION_PR="$2"
      shift 2
      ;;
    --slug)
      require_value "$@"
      SLUG_OVERRIDE="$2"
      shift 2
      ;;
    --epic)
      require_value "$@"
      EPIC_OVERRIDE="$2"
      shift 2
      ;;
    --exclude-issue)
      require_value "$@"
      EXCLUDED_ISSUES+=("$2")
      shift 2
      ;;
    --defer-epic-close)
      DEFER_EPIC_CLOSE=1
      DEFER_SOURCE="cli"
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 64
      ;;
  esac
done

if ! is_positive_int "$GRADUATION_PR"; then
  echo "ERROR: --graduation-pr must be a positive integer." >&2
  exit 64
fi
if [ -n "$SLUG_OVERRIDE" ] && ! is_valid_slug "$SLUG_OVERRIDE"; then
  echo "ERROR: --slug must be non-empty and contain only letters, numbers, dot, underscore, or hyphen." >&2
  exit 64
fi
for excluded in ${EXCLUDED_ISSUES[@]+"${EXCLUDED_ISSUES[@]}"}; do
  if ! is_positive_int "$excluded"; then
    echo "ERROR: --exclude-issue must be a positive integer." >&2
    exit 64
  fi
done

cd_workflow_repo_root
require_gh

REPO_SLUG="$(repo_slug)"
REPO_OWNER="${REPO_SLUG%%/*}"
REPO_NAME="${REPO_SLUG#*/}"

TRACKER_PROVIDER_RAW=""
TRACKER_PROVIDER_RAW="$(workflow_graduation_closeout_tracker_provider_raw "$(pwd)")" || exit $?
TRACKER_PROVIDER="$(workflow_normalize_issue_tracker_provider "$TRACKER_PROVIDER_RAW")"
case "$TRACKER_PROVIDER" in
  linear) ;;
  github_projects|github_issues|'')
    TRACKER_PROVIDER="${TRACKER_PROVIDER:-github_projects}"
    ;;
  none)
    TRACKER_PROVIDER="github_projects"
    ;;
  *)
    printf 'configuration: configuration validation error; key=issue_tracker.provider\n' >&2
    exit 64
    ;;
esac

# Shared parser must also see linear — update_tracker_status_best_effort uses
# that path. Fail closed before epic discovery or child closeout mutations.
if [ "$TRACKER_PROVIDER" = "linear" ]; then
  SHARED_TRACKER_PROVIDER="$(workflow_normalize_issue_tracker_provider "$(workflow_config_provider issue_tracker "$(pwd)/.ai-dev-workflow.yaml")")"
  if [ "$SHARED_TRACKER_PROVIDER" != "linear" ]; then
    echo "ERROR: issue_tracker.provider is linear but the tracker bridge cannot read it (commented section header?). Remove the trailing comment from the 'issue_tracker:' line in .ai-dev-workflow.yaml and rerun." >&2
    exit 64
  fi
fi

if [ -n "$EPIC_OVERRIDE" ]; then
  if [ "$TRACKER_PROVIDER" = "linear" ]; then
    if ! is_linear_issue_id "$EPIC_OVERRIDE"; then
      echo "ERROR: with issue_tracker.provider=linear, --epic must be a native Linear ID with team prefix (e.g. LEA-326), not a bare number. Refusing to mutate GitHub issues from a numeric suffix." >&2
      exit 64
    fi
  elif ! is_positive_int "$EPIC_OVERRIDE"; then
    echo "ERROR: --epic must be a positive integer." >&2
    exit 64
  fi
fi

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

fail_closed() {
  local reason="$1"
  echo "GRADUATION_CLOSEOUT_FROM_MERGED_PR_RESULT=failed" >&2
  echo "FAILURE_REASON=${reason}" >&2
  echo "ERROR: ${reason}" >&2
  exit 1
}

extract_closing_issue_numbers() {
  grep -ioE '(^|[^[:alnum:]_])(close[sd]?|fix(es|ed)?|resolve[sd]?)[[:space:]]+(issue[[:space:]]+)?#[0-9]+' \
    | grep -oE '[0-9]+$' \
    | sort -un || true
}

extract_epic_parent_refs() {
  grep -ioE '(^|[^[:alnum:]_])(epic|parent)[[:space:]]*#[0-9]+' \
    | grep -oE '[0-9]+$' \
    | sort -un || true
}

# Linear epic / parent refs: "Epic LEA-326", "Parent LEA-326", bare "LEA-326".
extract_linear_epic_refs() {
  grep -ioE '(^|[^[:alnum:]_])((epic|parent)[[:space:]]+)?[A-Z][A-Z0-9_]*-[0-9]+' \
    | grep -oE '[A-Z][A-Z0-9_]*-[0-9]+' \
    | sort -u || true
}

read_merged_graduation_pr() {
  local pr_json parsed state base_ref head_ref title body
  if ! pr_json="$(gh pr view "$GRADUATION_PR" --json number,state,mergedAt,baseRefName,headRefName,title,body,merged 2>/dev/null)"; then
    fail_closed "could_not_read_graduation_pr"
  fi
  if ! parsed="$(printf '%s' "$pr_json" | python3 -c '
import json, sys
try:
    pr = json.load(sys.stdin)
except Exception:
    sys.exit(1)
merged = pr.get("merged")
merged_at = pr.get("mergedAt") or ""
state = pr.get("state") or ""
is_merged = bool(merged) or bool(merged_at) or state == "MERGED"
print("true" if is_merged else "false")
print(pr.get("baseRefName") or "")
print(pr.get("headRefName") or "")
title = (pr.get("title") or "").replace("\n", " ")
body = (pr.get("body") or "")
print(title)
print("---BODY---")
sys.stdout.write(body)
')"; then
    fail_closed "could_not_parse_graduation_pr"
  fi
  state="$(printf '%s\n' "$parsed" | sed -n '1p')"
  base_ref="$(printf '%s\n' "$parsed" | sed -n '2p')"
  head_ref="$(printf '%s\n' "$parsed" | sed -n '3p')"
  title="$(printf '%s\n' "$parsed" | sed -n '4p')"
  body="$(printf '%s\n' "$parsed" | sed -n '6,$p')"

  if [ "$state" != "true" ]; then
    fail_closed "graduation_pr_not_merged"
  fi
  if [ "$base_ref" != "develop" ]; then
    fail_closed "graduation_pr_base_not_develop"
  fi
  case "$head_ref" in
    develop-*)
      DISCOVERED_SLUG="${head_ref#develop-}"
      SLUG_SOURCE="pr_head"
      ;;
    *)
      fail_closed "head_not_graduation_branch"
      ;;
  esac
  if ! is_valid_slug "$DISCOVERED_SLUG"; then
    fail_closed "invalid_graduation_slug"
  fi
  if [ -n "$SLUG_OVERRIDE" ]; then
    if [ "$SLUG_OVERRIDE" != "$DISCOVERED_SLUG" ]; then
      fail_closed "slug_override_mismatch"
    fi
    SLUG_SOURCE="cli_override"
  fi

  # Combined text is for Linear only (unchanged join). GitHub closeout filters
  # title and body as independent documents — see collect_pr_epic_candidates.
  printf '%s\n%s\n' "$title" "$body" > "$TMP_DIR/pr-text.txt"
  printf '%s' "$title" > "$TMP_DIR/pr-title.txt"
  printf '%s' "$body" > "$TMP_DIR/pr-body.txt"
}

# Drop indented Markdown code lines (4+ spaces or a leading tab) after fence
# stripping. Used only for Linear epic-ID text discovery (deferred tracker
# action), never for GitHub issue mutation — GitHub closeout uses GFM render.
strip_indented_code_lines() {
  python3 -c '
import sys
for line in sys.stdin:
    if line.startswith("\t"):
        continue
    leading = len(line) - len(line.lstrip(" "))
    if leading >= 4:
        continue
    sys.stdout.write(line)
'
}

collect_pr_epic_candidates() {
  local text
  if [ "$TRACKER_PROVIDER" = "linear" ]; then
    # Shared fence filter + simple indented-code strip. Epic IDs drive Linear
    # deferred actions only — never GitHub issue mutations.
    if ! text="$(strip_fenced_pr_body_blocks < "$TMP_DIR/pr-text.txt")"; then
      fail_closed "could_not_strip_fenced_blocks"
    fi
    if ! text="$(printf '%s' "$text" | strip_indented_code_lines)"; then
      fail_closed "could_not_strip_indented_code"
    fi
    printf '%s\n' "$text" | extract_linear_epic_refs | sort -u > "$TMP_DIR/pr-epic-candidates.txt"
    return 0
  fi
  # github_projects / github_issues: render title and body via GitHub GFM,
  # extract visible text outside <pre>/<code>, then union epic/closing refs
  # (closing via shared closing_keyword_live_refs). Fail closed for text refs
  # when render/extract fails — never scan raw markdown.
  local context title_raw body_raw title_text body_text
  context="${REPO_OWNER}/${REPO_NAME}"
  title_raw="$(cat "$TMP_DIR/pr-title.txt")"
  body_raw="$(cat "$TMP_DIR/pr-body.txt")"
  title_text=""
  body_text=""
  if printf '%s' "$title_raw" | graduation_closeout_raw_has_closing_keyword_candidate \
    || printf '%s' "$title_raw" | graduation_closeout_raw_has_epic_or_parent_ref; then
    if ! title_text="$(printf '%s' "$title_raw" | graduation_closeout_github_visible_text_from_markdown "$context")"; then
      echo "CLOSEOUT_TEXT_REFS_UNAVAILABLE pr=${GRADUATION_PR} reason=gfm_render_or_extract_failed" >&2
      : > "$TMP_DIR/pr-epic-candidates.txt"
      return 0
    fi
  fi
  if printf '%s' "$body_raw" | graduation_closeout_raw_has_closing_keyword_candidate \
    || printf '%s' "$body_raw" | graduation_closeout_raw_has_epic_or_parent_ref; then
    if ! body_text="$(printf '%s' "$body_raw" | graduation_closeout_github_visible_text_from_markdown "$context")"; then
      echo "CLOSEOUT_TEXT_REFS_UNAVAILABLE pr=${GRADUATION_PR} reason=gfm_render_or_extract_failed" >&2
      : > "$TMP_DIR/pr-epic-candidates.txt"
      return 0
    fi
  fi
  {
    printf '%s\n' "$title_text" | extract_epic_parent_refs
    printf '%s\n' "$title_text" | closing_keyword_live_refs
    printf '%s\n' "$body_text" | extract_epic_parent_refs
    printf '%s\n' "$body_text" | closing_keyword_live_refs
  } | sed '/^$/d' | sort -un > "$TMP_DIR/pr-epic-candidates.txt"
}

discover_epic_via_label_parents() {
  local label="integration-branch:${DISCOVERED_SLUG}"
  local issues_json response parents
  : > "$TMP_DIR/label-parents.txt"
  if ! issues_json="$(gh issue list --label "$label" --state all --limit 1000 --json number 2>/dev/null)"; then
    return 1
  fi
  printf '%s' "$issues_json" | python3 -c '
import json, sys
try:
    items = json.load(sys.stdin)
except Exception:
    sys.exit(1)
for item in items or []:
    number = item.get("number")
    if number:
        print(number)
' > "$TMP_DIR/label-issues.txt" || return 1

  if [ ! -s "$TMP_DIR/label-issues.txt" ]; then
    return 1
  fi

  while IFS= read -r issue; do
    [ -z "$issue" ] && continue
    # shellcheck disable=SC2016 # GraphQL variables are expanded by GitHub.
    if ! response="$(gh api graphql \
      -F owner="$REPO_OWNER" \
      -F repo="$REPO_NAME" \
      -F number="$issue" \
      -f query='
        query($owner: String!, $repo: String!, $number: Int!) {
          repository(owner: $owner, name: $repo) {
            issue(number: $number) {
              parent { number }
            }
          }
        }
      ' 2>/dev/null)"; then
      continue
    fi
    printf '%s' "$response" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
parent = ((((data.get("data") or {}).get("repository") or {}).get("issue") or {}).get("parent") or {})
number = parent.get("number")
if number:
    print(number)
' >> "$TMP_DIR/label-parents.txt" || true
  done < "$TMP_DIR/label-issues.txt"

  if [ ! -s "$TMP_DIR/label-parents.txt" ]; then
    return 1
  fi
  parents="$(sort -un "$TMP_DIR/label-parents.txt")"
  if [ "$(printf '%s\n' "$parents" | grep -c .)" -ne 1 ]; then
    return 1
  fi
  printf '%s\n' "$parents"
}

resolve_epic() {
  local count parent_epic
  if [ -n "$EPIC_OVERRIDE" ]; then
    DISCOVERED_EPIC="$EPIC_OVERRIDE"
    EPIC_SOURCE="cli_override"
    return 0
  fi

  collect_pr_epic_candidates
  count="$(grep -c . "$TMP_DIR/pr-epic-candidates.txt" 2>/dev/null || true)"
  count="${count:-0}"
  if [ "$count" -eq 1 ]; then
    DISCOVERED_EPIC="$(cat "$TMP_DIR/pr-epic-candidates.txt")"
    EPIC_SOURCE="pr_reference"
    return 0
  fi

  # Linear epics are not GitHub issues — never discover via GitHub parent GraphQL
  # or treat a numeric suffix as the epic.
  if [ "$TRACKER_PROVIDER" = "linear" ]; then
    if [ "$count" -gt 1 ]; then
      fail_closed "ambiguous_epic_candidates"
    fi
    fail_closed "epic_discovery_failed"
  fi

  if parent_epic="$(discover_epic_via_label_parents)"; then
    if [ "$count" -gt 1 ]; then
      # Ambiguous PR refs: accept parent convergence only when it matches exactly
      # one of the PR candidates, or when PR candidates were empty (handled above).
      if grep -qx "$parent_epic" "$TMP_DIR/pr-epic-candidates.txt"; then
        DISCOVERED_EPIC="$parent_epic"
        EPIC_SOURCE="label_parent_converged"
        return 0
      fi
      fail_closed "ambiguous_epic_candidates"
    fi
    DISCOVERED_EPIC="$parent_epic"
    EPIC_SOURCE="label_parent_converged"
    return 0
  fi

  if [ "$count" -gt 1 ]; then
    fail_closed "ambiguous_epic_candidates"
  fi
  fail_closed "epic_discovery_failed"
}

epic_has_defer_label() {
  local labels_csv old_ifs label normalized
  # Linear epics have no GitHub issue labels; defer only via CLI.
  if [ "$TRACKER_PROVIDER" = "linear" ]; then
    return 1
  fi
  if ! labels_csv="$(gh issue view "$DISCOVERED_EPIC" --json labels --jq '[.labels[].name] | join(",")' 2>/dev/null)"; then
    return 1
  fi
  [ -z "$labels_csv" ] && return 1
  old_ifs="$IFS"
  IFS=','
  # shellcheck disable=SC2086
  for label in $labels_csv; do
    normalized="$(printf '%s' "$label" | tr '[:upper:]' '[:lower:]')"
    if [ "$normalized" = "defer-epic-close" ]; then
      IFS="$old_ifs"
      return 0
    fi
  done
  IFS="$old_ifs"
  return 1
}

read_merged_graduation_pr
resolve_epic

if [ "$DEFER_EPIC_CLOSE" -eq 0 ] && epic_has_defer_label; then
  DEFER_EPIC_CLOSE=1
  DEFER_SOURCE="epic_label"
fi

CHILD_ARGV=(
  "$SCRIPT_DIR/graduation-closeout.sh"
  --slug "$DISCOVERED_SLUG"
  --graduation-pr "$GRADUATION_PR"
  --epic "$DISCOVERED_EPIC"
)
for excluded in ${EXCLUDED_ISSUES[@]+"${EXCLUDED_ISSUES[@]}"}; do
  CHILD_ARGV+=(--exclude-issue "$excluded")
done
if [ "$DEFER_EPIC_CLOSE" -eq 1 ]; then
  CHILD_ARGV+=(--defer-epic-close)
fi
if [ "$DRY_RUN" -eq 1 ]; then
  CHILD_ARGV+=(--dry-run)
fi

echo "GRADUATION_CLOSEOUT_FROM_MERGED_PR_RESULT=running"
echo "GRADUATION_PR=$GRADUATION_PR"
echo "SLUG=$DISCOVERED_SLUG"
echo "SLUG_SOURCE=$SLUG_SOURCE"
echo "EPIC_ISSUE=$DISCOVERED_EPIC"
echo "EPIC_SOURCE=$EPIC_SOURCE"
echo "TRACKER_PROVIDER=$TRACKER_PROVIDER"
echo "DRY_RUN=$DRY_RUN"
echo "DEFER_EPIC_CLOSE=$DEFER_EPIC_CLOSE"
echo "DEFER_SOURCE=$DEFER_SOURCE"
echo "CHILD_COMMAND=${CHILD_ARGV[*]}"

CHILD_STATUS=0
"${CHILD_ARGV[@]}" || CHILD_STATUS=$?

if [ "$CHILD_STATUS" -eq 0 ]; then
  echo "GRADUATION_CLOSEOUT_FROM_MERGED_PR_RESULT=pass"
  exit 0
fi
echo "GRADUATION_CLOSEOUT_FROM_MERGED_PR_RESULT=failed"
echo "FAILURE_REASON=child_closeout_failed"
exit 1
