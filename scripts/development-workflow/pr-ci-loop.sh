#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=scripts/development-workflow/workflow-lib.sh
source "$SCRIPT_DIR/workflow-lib.sh"

usage() {
  cat <<'EOF'
Usage: ./scripts/development-workflow/pr-ci-loop.sh <pr-number> [--poll-interval seconds] [--max-wait seconds]

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
min_no_checks_wait=$((poll_interval * 2))

while :; do
  checks_json="$(gh pr view "$pr_number" --json statusCheckRollup)"
  # statusCheckRollup can include historical duplicates for the same check.
  # Keep only the latest entry per check name to avoid stale conclusions.
  normalized_checks_json="$(
    printf '%s\n' "$checks_json" | jq '
      (.statusCheckRollup // [])
      | map(
          . + {
            __check_name: (.name // .context // .workflowName // "unknown"),
            __check_ts: (.startedAt // .completedAt // "")
          }
        )
      | sort_by(.__check_name, .__check_ts)
      | group_by(.__check_name)
      | map(last | del(.__check_name, .__check_ts))
    '
  )"
  total_check_count="$(
    printf '%s\n' "$normalized_checks_json" | jq 'length'
  )"
  pending_count="$(
    printf '%s\n' "$normalized_checks_json" | jq '
      .
      | map(select(
          ((.status // "") != "" and (.status != "COMPLETED"))
          or (.state == "EXPECTED")
          or (.state == "PENDING")
          or (.state == "IN_PROGRESS")
          or (.state == "QUEUED")
        ))
      | length
    '
  )"
  pending_list="$(
    printf '%s\n' "$normalized_checks_json" | jq -r '
      .
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
  failing_count="$(
    printf '%s\n' "$normalized_checks_json" | jq '
      .
      | map(select(
          (.conclusion == "FAILURE")
          or (.conclusion == "CANCELLED")
          or (.conclusion == "TIMED_OUT")
          or (.conclusion == "ACTION_REQUIRED")
          or (.conclusion == "STARTUP_FAILURE")
          or (.state == "FAILURE")
          or (.state == "ERROR")
        ))
      | length
    '
  )"
  failing_list="$(
    printf '%s\n' "$normalized_checks_json" | jq -r '
      .
      | map(select(
          (.conclusion == "FAILURE")
          or (.conclusion == "CANCELLED")
          or (.conclusion == "TIMED_OUT")
          or (.conclusion == "ACTION_REQUIRED")
          or (.conclusion == "STARTUP_FAILURE")
          or (.state == "FAILURE")
          or (.state == "ERROR")
        ))
      | map(.name // .context // .workflowName // "unknown")
      | join(",")
    '
  )"

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
    if [ "$total_check_count" -eq 0 ] && [ "$elapsed" -lt "$min_no_checks_wait" ]; then
      sleep "$poll_interval"
      elapsed=$((elapsed + poll_interval))
      continue
    fi

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
