#!/usr/bin/env bash
#
# graduation-closeout-lib.sh — closeout-only tracker provider helpers.
#
# Kept out of workflow-lib.sh so shared provider resolution stays identical to
# develop for all other callers. Requires workflow-lib.sh to be sourced first
# (workflow_config_provider, workflow_normalize_issue_tracker_provider,
# workflow_repo_root).
#
# Sourced by:
#   - scripts/development-workflow/graduation-closeout.sh
#   - scripts/development-workflow/graduation-closeout-from-merged-pr.sh
#
# This file defines functions only and runs nothing on source.

# graduation_closeout_issue_tracker_provider_in_file <config_file>
# Read issue_tracker.provider under a section header that may carry a trailing
# comment (`issue_tracker: # ...`). Does not change workflow_config_provider.
graduation_closeout_issue_tracker_provider_in_file() {
  local config_file="$1"
  [ -f "$config_file" ] || return 0
  awk '
    function trim(value) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      gsub(/^["'"'"']|["'"'"']$/, "", value)
      return value
    }
    /^issue_tracker:[[:space:]]*(#.*)?$/ { in_section = 1; next }
    in_section && /^[^[:space:]#]/ { exit }
    in_section && /^[[:space:]][[:space:]]provider:[[:space:]]*/ {
      line = $0
      sub(/^[[:space:]]*provider:[[:space:]]*/, "", line)
      sub(/[[:space:]]+#.*$/, "", line)
      print trim(line)
      exit
    }
  ' "$config_file"
}

# graduation_closeout_tracker_provider_raw [repo_root]
# Resolve issue_tracker.provider for graduation closeout.
# - Prefer shared .ai-dev-workflow.yaml via workflow_config_provider (same as
#   post-merge-cleanup; no .ai-dev-workflow.local.yaml).
# - If that is empty, a closeout-local comment-tolerant read may recover
#   provider: linear so Linear safety still applies under commented headers
#   (callers then fail closed when the shared bridge cannot read linear).
# - Non-Linear (github_*, none, other, undeclared) always returns the legacy
#   workflow_config_provider result — never exit 64 — so GitHub closeout stays
#   byte-identical to develop.
graduation_closeout_tracker_provider_raw() {
  local repo_root="${1:-$(workflow_repo_root)}"
  local shared="$repo_root/.ai-dev-workflow.yaml"
  local legacy="" local_raw="" local_norm=""

  [ -f "$shared" ] || return 0

  legacy="$(workflow_config_provider issue_tracker "$shared")"
  if [ -n "$legacy" ]; then
    printf '%s' "$legacy"
    return 0
  fi

  local_raw="$(graduation_closeout_issue_tracker_provider_in_file "$shared")"
  local_norm="$(workflow_normalize_issue_tracker_provider "$local_raw")"
  if [ "$local_norm" = "linear" ]; then
    printf '%s' "$local_raw"
    return 0
  fi

  printf '%s' "$legacy"
  return 0
}

# Compatibility aliases used by existing closeout call sites / docs.
workflow_graduation_closeout_issue_tracker_provider_in_file() {
  graduation_closeout_issue_tracker_provider_in_file "$@"
}

workflow_graduation_closeout_tracker_provider_raw() {
  graduation_closeout_tracker_provider_raw "$@"
}

# graduation_closeout_linear_native_status <linear_issue_id>
# Native Linear status when the orchestrator bridge (or test fixture) supplies it.
# Env: WORKFLOW_LINEAR_NATIVE_STATUS_<ID> (non-alnum → underscore, uppercased).
# Tests: MOCK_LINEAR_STATUS_DIR/<linear_issue_id> file contents.
graduation_closeout_linear_native_status() {
  local issue_id="$1"
  local sanitized key value

  sanitized="$(printf '%s' "$issue_id" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '_')"
  key="WORKFLOW_LINEAR_NATIVE_STATUS_$(printf '%s' "$sanitized" | tr '[:lower:]' '[:upper:]')"
  value="${!key-}"
  if [ -n "$value" ]; then
    printf '%s' "$value"
    return 0
  fi
  if [ -n "${MOCK_LINEAR_STATUS_DIR:-}" ] && [ -f "${MOCK_LINEAR_STATUS_DIR}/${issue_id}" ]; then
    cat "${MOCK_LINEAR_STATUS_DIR}/${issue_id}"
    return 0
  fi
  return 0
}
