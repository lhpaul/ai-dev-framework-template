#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=scripts/workflow-lib.sh
source "$SCRIPT_DIR/workflow-lib.sh"

usage() {
  cat <<'EOF'
Usage: ./scripts/pr-ci-loop.sh <pr-number> [--poll-interval seconds] [--max-wait seconds]

Polls GitHub required status checks for a PR until they are green, failing, or timed out.
Outputs stable key=value lines and exits with:
  0 -> green
  1 -> red
  2 -> timeout
EOF
}

if [ "$#" -lt 1 ]; then
  usage >&2
  exit 64
fi

pr_number=""
poll_interval=60
max_wait=1800

while [ "$#" -gt 0 ]; do
  case "$1" in
    --poll-interval)
      poll_interval="$2"
      shift 2
      ;;
    --max-wait)
      max_wait="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "Unknown option: $1" >&2
      exit 64
      ;;
    *)
      if [ -n "$pr_number" ]; then
        echo "Only one PR number may be provided." >&2
        exit 64
      fi
      pr_number="$1"
      shift
      ;;
  esac
done

if [ -z "$pr_number" ]; then
  usage >&2
  exit 64
fi

require_gh
cd_workflow_repo_root

elapsed=0
repo="$(repo_slug)"

while :; do
  checks_json="$(gh pr view "$pr_number" --json statusCheckRollup)"
  total_check_count="$(
    printf '%s\n' "$checks_json" | jq '(.statusCheckRollup // []) | length'
  )"
  pending_list="$(
    printf '%s\n' "$checks_json" | jq -r '
      (.statusCheckRollup // [])
      | map(select(
          ((.status // "") != "" and (.status != "COMPLETED"))
          or (.state == "EXPECTED")
          or (.state == "PENDING")
          or (.state == "IN_PROGRESS")
          or (.state == "QUEUED")
        ))
      | map(.name // .context // .workflowName // "unknown")
      | join(",")
    '
  )"
  failing_list="$(
    printf '%s\n' "$checks_json" | jq -r '
      (.statusCheckRollup // [])
      | map(select(
          (.conclusion == "FAILURE")
          or (.conclusion == "TIMED_OUT")
          or (.conclusion == "ACTION_REQUIRED")
          or (.conclusion == "CANCELLED")
          or (.conclusion == "STARTUP_FAILURE")
          or (.state == "FAILURE")
          or (.state == "ERROR")
        ))
      | map(.name // .context // .workflowName // "unknown")
      | join(",")
    '
  )"

  pending_count=0
  failing_count=0
  [ -n "$pending_list" ] && pending_count="$(printf '%s\n' "$pending_list" | awk -F',' '{print NF}')"
  [ -n "$failing_list" ] && failing_count="$(printf '%s\n' "$failing_list" | awk -F',' '{print NF}')"

  if [ "$failing_count" -gt 0 ]; then
    print_kv RESULT red
    print_kv PR_NUMBER "$pr_number"
    print_kv REPO "$repo"
    print_kv TOTAL_CHECK_COUNT "$total_check_count"
    print_kv FAILING_CHECK_COUNT "$failing_count"
    print_kv FAILING_CHECKS "$failing_list"
    print_kv PENDING_CHECK_COUNT "$pending_count"
    print_kv PENDING_CHECKS "$pending_list"
    exit 1
  fi

  if [ "$pending_count" -eq 0 ]; then
    print_kv RESULT green
    print_kv PR_NUMBER "$pr_number"
    print_kv REPO "$repo"
    print_kv TOTAL_CHECK_COUNT "$total_check_count"
    print_kv FAILING_CHECK_COUNT 0
    print_kv FAILING_CHECKS ""
    print_kv PENDING_CHECK_COUNT 0
    print_kv PENDING_CHECKS ""
    exit 0
  fi

  if [ "$elapsed" -ge "$max_wait" ]; then
    print_kv RESULT timeout
    print_kv PR_NUMBER "$pr_number"
    print_kv REPO "$repo"
    print_kv TOTAL_CHECK_COUNT "$total_check_count"
    print_kv FAILING_CHECK_COUNT "$failing_count"
    print_kv FAILING_CHECKS "$failing_list"
    print_kv PENDING_CHECK_COUNT "$pending_count"
    print_kv PENDING_CHECKS "$pending_list"
    exit 2
  fi

  sleep "$poll_interval"
  elapsed=$((elapsed + poll_interval))
done
