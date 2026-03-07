#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=scripts/workflow-lib.sh
source "$SCRIPT_DIR/workflow-lib.sh"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/workflow-next-action.sh --branch <branch>
  ./scripts/workflow-next-action.sh --pr <number>
  ./scripts/workflow-next-action.sh --development <path>

Classifies the next deterministic workflow action and prints stable key=value lines.
EOF
}

branch_name=""
pr_number=""
development_path=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --branch)
      branch_name="$2"
      shift 2
      ;;
    --pr)
      pr_number="$2"
      shift 2
      ;;
    --development)
      development_path="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 64
      ;;
  esac
done

targets=0
[ -n "$branch_name" ] && targets=$((targets + 1))
[ -n "$pr_number" ] && targets=$((targets + 1))
[ -n "$development_path" ] && targets=$((targets + 1))

if [ "$targets" -ne 1 ]; then
  usage >&2
  exit 64
fi

cd_workflow_repo_root

if [ -n "$pr_number" ]; then
  require_gh
  branch_name="$(gh pr view "$pr_number" --json headRefName --jq '.headRefName')"
  labels="$(gh pr view "$pr_number" --json labels --jq '[.labels[].name] | join(",")')"

  print_kv TARGET "pr:$pr_number"
  print_kv BRANCH "$branch_name"
  print_kv REVIEW_AGENT "$(reviewer_for_branch "$branch_name")"

  case ",$labels," in
    *,agent:ready-for-review,*)
      print_kv NEXT_ACTION wait-human-review
      exit 0
      ;;
    *,agent:needs-fixes,*)
      print_kv NEXT_ACTION resume-fix-loop
      exit 0
      ;;
    *)
      print_kv NEXT_ACTION resolve-pr-readiness
      exit 0
      ;;
  esac
fi

if [ -n "$branch_name" ]; then
  pr_number="$(open_pr_number_for_branch "$branch_name" || true)"

  print_kv TARGET "branch:$branch_name"
  print_kv BRANCH "$branch_name"
  print_kv REVIEW_AGENT "$(reviewer_for_branch "$branch_name")"

  if [ -n "$pr_number" ]; then
    labels="$(gh pr view "$pr_number" --json labels --jq '[.labels[].name] | join(",")')"
    print_kv PR_NUMBER "$pr_number"
    case ",$labels," in
      *,agent:ready-for-review,*)
        print_kv NEXT_ACTION wait-human-review
        exit 0
        ;;
      *,agent:needs-fixes,*)
        print_kv NEXT_ACTION resume-fix-loop
        exit 0
        ;;
      *)
        print_kv NEXT_ACTION resolve-pr-readiness
        exit 0
        ;;
    esac
  fi

  case "$(branch_prefix "$branch_name")" in
    spec)
      print_kv NEXT_ACTION run-spec-review-and-open-pr
      ;;
    implementation-plan)
      print_kv NEXT_ACTION run-plan-review-and-open-pr
      ;;
    feature|fix|hotfix)
      print_kv NEXT_ACTION run-code-review-and-open-pr
      ;;
    *)
      print_kv NEXT_ACTION unknown
      ;;
  esac
  exit 0
fi

if [ ! -d "$development_path" ]; then
  echo "Development path does not exist: $development_path" >&2
  exit 66
fi

spec_file="$(find "$development_path" -maxdepth 1 -type f -name '1_*_specs.md' | head -n 1)"
if [ -z "$spec_file" ]; then
  echo "No spec file found in $development_path" >&2
  exit 66
fi

status_line="$(sed -n 's/^\*\*Status\*\*: //p' "$spec_file" | head -n 1)"

print_kv TARGET "development:$development_path"
print_kv SPEC_FILE "$spec_file"
print_kv STATUS "$status_line"

case "$status_line" in
  "Spec Ready")
    print_kv NEXT_ACTION write-plan
    ;;
  "Plan Ready")
    print_kv NEXT_ACTION implement
    ;;
  "In Development")
    print_kv NEXT_ACTION resolve-development-pr
    ;;
  *)
    print_kv NEXT_ACTION unknown
    ;;
esac
