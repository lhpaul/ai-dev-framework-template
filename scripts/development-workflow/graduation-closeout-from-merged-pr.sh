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
#     [--epic <number>] [--slug <slug>] \
#     [--exclude-issue <number>]... [--defer-epic-close]
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

GRADUATION_PR=""
SLUG_OVERRIDE=""
EPIC_OVERRIDE=""
DEFER_EPIC_CLOSE=0
declare -a EXCLUDED_ISSUES=()

# Populated during discovery for the summary.
DISCOVERED_SLUG=""
DISCOVERED_EPIC=""
EPIC_SOURCE=""
SLUG_SOURCE=""
DEFER_SOURCE="none"
CHILD_ARGV=()

usage() {
  cat >&2 <<'EOF'
Usage:
  graduation-closeout-from-merged-pr.sh --graduation-pr <number> \
    [--epic <number>] [--slug <slug>] \
    [--exclude-issue <number>]... [--defer-epic-close]
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
if [ -n "$EPIC_OVERRIDE" ] && ! is_positive_int "$EPIC_OVERRIDE"; then
  echo "ERROR: --epic must be a positive integer." >&2
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

# Strip fenced code blocks so example closing keywords are not treated as live refs.
strip_fenced_blocks() {
  python3 -c '
import re, sys
text = sys.stdin.read()
text = re.sub(r"```.*?```", "", text, flags=re.S)
sys.stdout.write(text)
'
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

  printf '%s\n%s\n' "$title" "$body" > "$TMP_DIR/pr-text.txt"
}

collect_pr_epic_candidates() {
  local text
  text="$(strip_fenced_blocks < "$TMP_DIR/pr-text.txt")"
  {
    printf '%s\n' "$text" | extract_epic_parent_refs
    printf '%s\n' "$text" | extract_closing_issue_numbers
  } | sort -un > "$TMP_DIR/pr-epic-candidates.txt"
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

echo "GRADUATION_CLOSEOUT_FROM_MERGED_PR_RESULT=running"
echo "GRADUATION_PR=$GRADUATION_PR"
echo "SLUG=$DISCOVERED_SLUG"
echo "SLUG_SOURCE=$SLUG_SOURCE"
echo "EPIC_ISSUE=$DISCOVERED_EPIC"
echo "EPIC_SOURCE=$EPIC_SOURCE"
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
