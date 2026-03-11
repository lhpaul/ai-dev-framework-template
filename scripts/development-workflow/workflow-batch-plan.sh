#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=scripts/development-workflow/workflow-lib.sh
source "$SCRIPT_DIR/workflow-lib.sh"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/development-workflow/workflow-batch-plan.sh [development-path ...]

Classifies development folders into batch-planning candidates for the batch
orchestrator. If no paths are given, scans docs/specs/developments/*.
EOF
}

batch_hint_for_action() {
  case "$1" in
    write-plan) printf 'plan-creation\n' ;;
    implement) printf 'implementation\n' ;;
    resolve-development-pr) printf 'resume-development-pr\n' ;;
    *) printf 'manual-review\n' ;;
  esac
}

parallel_safe_for_action() {
  case "$1" in
    write-plan) printf 'yes\n' ;;
    implement|resolve-development-pr) printf 'conditional\n' ;;
    *) printf 'no\n' ;;
  esac
}

cd_workflow_repo_root

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

if [ "$#" -gt 0 ]; then
  development_paths=("$@")
else
  if [ -d "docs/specs/developments" ]; then
    development_paths=()
    while IFS= read -r path; do
      development_paths+=("$path")
    done < <(find "docs/specs/developments" -mindepth 1 -maxdepth 1 -type d | sort)
  else
    development_paths=()
  fi
fi

if [ "${#development_paths[@]}" -eq 0 ]; then
  echo "(none)"
  exit 0
fi

for development_path in "${development_paths[@]}"; do
  if [ ! -d "$development_path" ]; then
    echo "Skipping missing development path: $development_path" >&2
    continue
  fi

  slug="$(basename "$development_path" | sed 's/^[0-9]\{14\}_//')"
  next_action_output="$("$SCRIPT_DIR/workflow-next-action.sh" --development "$development_path")"

  status=""
  next_action=""
  linear_issue=""
  while IFS='=' read -r key value; do
    case "$key" in
      STATUS) status="$value" ;;
      NEXT_ACTION) next_action="$value" ;;
      LINEAR_ISSUE) linear_issue="$value" ;;
    esac
  done <<< "$next_action_output"

  print_kv TARGET "development:$development_path"
  print_kv DEVELOPMENT_PATH "$development_path"
  print_kv SLUG "$slug"
  [ -n "$linear_issue" ] && print_kv LINEAR_ISSUE "$linear_issue"
  print_kv STATUS "$status"
  print_kv NEXT_ACTION "$next_action"
  print_kv BATCH_HINT "$(batch_hint_for_action "$next_action")"
  print_kv PARALLEL_SAFE "$(parallel_safe_for_action "$next_action")"
  echo
done
