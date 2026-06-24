#!/usr/bin/env bash
# hub-preflight-product-repos.sh - bootstrap workflow readiness labels and validate
# CI policy for workflow_hub product repositories before delegated orchestration.

set -euo pipefail
trap 'case $? in 141) exit 0 ;; *) exit $? ;; esac' EXIT

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=scripts/development-workflow/hub-product-repo-lib.sh
source "$SCRIPT_DIR/hub-product-repo-lib.sh"

usage() {
  cat <<'USAGE'
Usage: hub-preflight-product-repos.sh (--repo <name> | --all) [--repo-root <path>] [--labels-only] [--ci-only]

Workflow_hub preflight for configured product repositories:
  - Ensures standard workflow readiness labels exist on the GitHub repository
  - Validates CI policy (required vs explicit none) before delegated merge runs

Requires gh authentication for remote label and workflow inspection.
USAGE
}

REPO_NAME=""
ALL=false
REPO_ROOT="$HUB_REPO_ROOT"
LABELS_ONLY=false
CI_ONLY=false

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo)
      [ "$#" -ge 2 ] || hub_die "--repo requires a value"
      REPO_NAME="$2"
      shift 2
      ;;
    --all)
      ALL=true
      shift
      ;;
    --repo-root)
      [ "$#" -ge 2 ] || hub_die "--repo-root requires a value"
      REPO_ROOT="$2"
      shift 2
      ;;
    --labels-only)
      LABELS_ONLY=true
      shift
      ;;
    --ci-only)
      CI_ONLY=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      hub_die "unknown argument '$1'"
      ;;
  esac
done

if [ "$LABELS_ONLY" = "true" ] && [ "$CI_ONLY" = "true" ]; then
  hub_die "--labels-only and --ci-only cannot be used together"
fi

RUN_LABELS=true
RUN_CI=true
if [ "$LABELS_ONLY" = "true" ]; then
  RUN_CI=false
fi
if [ "$CI_ONLY" = "true" ]; then
  RUN_LABELS=false
fi

hub_require_workflow_hub_mode "$REPO_ROOT"

if ! command -v gh >/dev/null 2>&1; then
  hub_die "gh CLI is required for hub-preflight-product-repos.sh"
fi
if ! gh auth status >/dev/null 2>&1; then
  hub_die "gh is not authenticated; run gh auth login before product-repo preflight"
fi

ok_count=0
failed_count=0
skipped_count=0
exit_code=0

hub_ensure_readiness_label() {
  local github_repo="$1"
  local name="$2"
  local color="$3"
  local description="$4"

  if gh label list --repo "$github_repo" --search "$name" --json name \
    | jq -e --arg name "$name" '.[] | select(.name == $name)' >/dev/null 2>&1; then
    printf '  LABEL_EXISTING=%s\n' "$name"
    return 0
  fi
  if gh label create "$name" --repo "$github_repo" --color "$color" --description "$description" 2>/dev/null; then
    printf '  LABEL_CREATED=%s\n' "$name"
    return 0
  fi
  if gh label list --repo "$github_repo" --search "$name" --json name \
    | jq -e --arg name "$name" '.[] | select(.name == $name)' >/dev/null 2>&1; then
    printf '  LABEL_EXISTING=%s\n' "$name"
    return 0
  fi
  printf '  LABEL_FAILED=%s\n' "$name"
  return 1
}

hub_bootstrap_labels() {
  local github_repo="$1"
  local label_failed=0
  hub_ensure_readiness_label "$github_repo" "ready-for-human-review" "0E8A16" \
    "Internal review is clean; automated reviewers clean or skipped; CI is green." || label_failed=1
  hub_ensure_readiness_label "$github_repo" "needs-fixes" "B60205" \
    "CI failing and/or blocking automated reviewer feedback remains." || label_failed=1
  hub_ensure_readiness_label "$github_repo" "ready-for-regression" "e4e669" \
    "PR is ready for regression testing" || label_failed=1
  hub_ensure_readiness_label "$github_repo" "human-checkpoint-required" "5319E7" \
    "Explicit human checkpoint feedback still required before delegated merge" || label_failed=1
  return "$label_failed"
}

hub_probe_ci_workflows() {
  local github_repo="$1"
  gh api "repos/$github_repo/actions/workflows" --jq '.total_count // 0' 2>/dev/null || echo "-1"
}

if ! selected_repos="$(hub_selected_repos "$REPO_ROOT" "$REPO_NAME" "$ALL")"; then
  printf 'RESULT=failed\n'
  hub_print_summary 0 0 0 0 0 0 1
  exit 1
fi

while IFS= read -r selected_repo; do
  [ -n "$selected_repo" ] || continue
  printf 'REPO %s\n' "$selected_repo"

  if ! context="$(hub_resolve_context_json "$REPO_ROOT" "$selected_repo")"; then
    printf '  STATUS=failed\n'
    printf '  REASON=resolver_failed\n'
    failed_count=$((failed_count + 1))
    exit_code=1
    continue
  fi

  github_repo="$(hub_json_field "$context" TARGET_GITHUB_REPO)"
  if [ -z "$github_repo" ]; then
    git_url="$(hub_json_field "$context" TARGET_GIT_URL)"
    github_repo="$(hub_github_repo_from_url "$git_url")"
  fi
  ci_policy="$(hub_json_field "$context" TARGET_CI_POLICY)"
  [ -n "$ci_policy" ] || ci_policy="required"

  printf '  GITHUB_REPO=%s\n' "${github_repo:-}"
  printf '  CI_POLICY=%s\n' "$ci_policy"

  if [ -z "$github_repo" ]; then
    printf '  STATUS=skipped\n'
    printf '  REASON=missing_github_repo_slug\n'
    skipped_count=$((skipped_count + 1))
    continue
  fi

  repo_failed=0

  if [ "$RUN_LABELS" = "true" ]; then
    if hub_bootstrap_labels "$github_repo"; then
      printf '  LABELS=ok\n'
    else
      printf '  LABELS=failed\n'
      repo_failed=1
    fi
  fi

  if [ "$RUN_CI" = "true" ]; then
    workflow_count="$(hub_probe_ci_workflows "$github_repo")"
    printf '  CI_WORKFLOW_COUNT=%s\n' "$workflow_count"
    if [ "$workflow_count" = "-1" ]; then
      printf '  CI_PREFLIGHT=failed\n'
      printf '  CI_PREFLIGHT_REASON=workflow_query_failed\n'
      repo_failed=1
    elif [ "$workflow_count" -eq 0 ] && [ "$ci_policy" = "required" ]; then
      printf '  CI_PREFLIGHT=failed\n'
      printf '  CI_PREFLIGHT_REASON=no_github_actions_workflows\n'
      printf '  GUIDANCE=Add GitHub Actions workflows to %s or set ci_policy: none on workflow_hub.product_repos[] for this repository.\n' "$selected_repo"
      repo_failed=1
    else
      printf '  CI_PREFLIGHT=ok\n'
    fi
  fi

  if [ "$repo_failed" -eq 1 ]; then
    printf '  STATUS=failed\n'
    failed_count=$((failed_count + 1))
    exit_code=1
  else
    printf '  STATUS=ok\n'
    ok_count=$((ok_count + 1))
  fi
done <<< "$selected_repos"

if [ "$exit_code" -eq 0 ]; then
  printf 'RESULT=ok\n'
else
  printf 'RESULT=failed\n'
fi

hub_print_summary "$ok_count" "$skipped_count" 0 0 0 0 "$failed_count"
exit "$exit_code"
