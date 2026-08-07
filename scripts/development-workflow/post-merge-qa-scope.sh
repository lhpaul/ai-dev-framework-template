#!/usr/bin/env bash
# post-merge-qa-scope.sh — read-only scope proposal for /post-merge-qa
#
# Proposes QA candidates for human confirmation. Does not update trackers,
# create branches, open PRs, or exercise application flows.
#
# List calls use an explicit --limit (proposal size). Results are not fully
# paginated; the human confirms/adjusts scope before any testing.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/workflow-lib.sh"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/development-workflow/post-merge-qa-scope.sh --base <develop|develop-slug>
      [--epic <number>] [--issues <csv>] [--tracker-items <csv>]
      [--recent-merged-prs <n>] [--json]

Read-only: proposes post-merge QA scope for human confirmation.
List queries are intentionally capped with --limit; confirm or adjust before testing.
Provider-backed tracker discovery should be performed by the configured tracker
connector/CLI and passed with --tracker-items. This helper remains provider-neutral.
EOF
}

base=""
epic=""
issues_arg=""
tracker_items_arg=""
recent_merged=0
json_output=0
missing_value_option=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --base)
      shift
      if [ "$#" -eq 0 ] || [[ "$1" == -* ]]; then
        base=""
        missing_value_option="--base"
      else
        base="$1"
        shift
      fi
      ;;
    --epic)
      shift
      if [ "$#" -eq 0 ] || [[ "$1" == -* ]]; then
        epic=""
        missing_value_option="--epic"
      else
        epic="$1"
        shift
      fi
      ;;
    --issues)
      shift
      if [ "$#" -eq 0 ] || [[ "$1" == -* ]]; then
        issues_arg=""
        missing_value_option="--issues"
      else
        issues_arg="$1"
        shift
      fi
      ;;
    --tracker-items)
      shift
      if [ "$#" -eq 0 ] || [[ "$1" == -* ]]; then
        tracker_items_arg=""
        missing_value_option="--tracker-items"
      else
        tracker_items_arg="$1"
        shift
      fi
      ;;
    --recent-merged-prs)
      shift
      if [ "$#" -eq 0 ] || [[ "$1" == -* ]]; then
        recent_merged=""
        missing_value_option="--recent-merged-prs"
      else
        recent_merged="$1"
        shift
      fi
      ;;
    --json)
      json_output=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

if [ -n "$missing_value_option" ]; then
  echo "$missing_value_option requires a value" >&2
  usage >&2
  exit 64
fi

if [ -z "$base" ]; then
  echo "--base is required (develop or develop-<slug>)" >&2
  usage >&2
  exit 64
fi

if ! printf '%s\n' "$base" | grep -Eq '^develop(-[A-Za-z0-9][A-Za-z0-9._-]*)?$'; then
  echo "Disallowed base '$base'. Allowed: develop or develop-<slug>." >&2
  exit 64
fi

if [ -n "$epic" ] && ! printf '%s\n' "$epic" | grep -Eq '^[1-9][0-9]*$'; then
  echo "--epic must be a positive issue number" >&2
  exit 64
fi

if ! printf '%s\n' "$recent_merged" | grep -Eq '^[0-9]+$'; then
  echo "--recent-merged-prs must be a non-negative integer" >&2
  exit 64
fi

tmp_dir="$(mktemp -d)" || {
  echo "Failed to create temp directory" >&2
  exit 1
}
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

candidates_file="$tmp_dir/candidates.jsonl"
: > "$candidates_file"
notes_file="$tmp_dir/notes.jsonl"
: > "$notes_file"

effective_config_file="$(workflow_effective_config_file 2>/dev/null || true)"
tracker_provider_raw=""
if [ -n "$effective_config_file" ]; then
  tracker_provider_raw="$(workflow_config_provider issue_tracker "$effective_config_file")"
fi
tracker_provider="$(workflow_normalize_issue_tracker_provider "$tracker_provider_raw")"
tracker_discovery_required=false
if [ "$base" = "develop" ] && [ -n "$tracker_provider" ] && [ "$tracker_provider" != "none" ]; then
  tracker_discovery_required=true
fi

append_note() {
  jq -nc --arg note "$1" '{note: $note}' >> "$notes_file"
}

append_candidate() {
  local kind="$1" identifier="$2" title="$3" url="$4" reason="$5"
  jq -nc \
    --arg kind "$kind" \
    --arg id "$identifier" \
    --arg title "$title" \
    --arg url "$url" \
    --arg reason "$reason" \
    '{
      kind: $kind,
      id: $id,
      title: $title,
      url: $url,
      reason: $reason
    } + (if ($id | test("^[1-9][0-9]*$")) then {number: ($id | tonumber)} else {} end)' \
    >> "$candidates_file"
}

# Append pull_request/issue rows from a JSON array file (no pipeline subshell).
# Malformed rows are skipped with a note so one bad API object cannot abort the proposal.
append_rows_from_json_array() {
  local json_file="$1" kind="$2" reason="$3" skip_number="${4:-}"
  local count row number title url
  count="$(jq 'length' "$json_file")" || {
    echo "Failed to parse JSON array from $json_file" >&2
    exit 1
  }
  if [ "$count" -eq 0 ]; then
    append_note "No $kind candidates returned for: $reason"
    return 0
  fi
  while IFS= read -r row; do
    if ! number="$(printf '%s' "$row" | jq -er '.number')"; then
      append_note "Skipped malformed $kind row (missing number) for: $reason"
      continue
    fi
    if ! title="$(printf '%s' "$row" | jq -er '.title')"; then
      append_note "Skipped malformed $kind #$number (missing title) for: $reason"
      continue
    fi
    if ! url="$(printf '%s' "$row" | jq -er '.url')"; then
      append_note "Skipped malformed $kind #$number (missing url) for: $reason"
      continue
    fi
    if [ -n "$skip_number" ] && [ "$number" = "$skip_number" ]; then
      continue
    fi
    append_candidate "$kind" "$number" "$title" "$url" "$reason"
  done < <(jq -c '.[]' "$json_file")
}

# Keep only GitHub issues explicitly associated with a merged implementation PR.
# Closing references are unavailable for non-default PR bases, so accept either
# an issue reference in the title/body or a canonical workflow branch identifier.
filter_issues_referenced_by_merged_prs() {
  local issues_file="$1" merged_prs_file="$2" output_file="$3"
  jq --slurpfile merged_prs "$merged_prs_file" \
    '[.[] | .number as $number | select(any($merged_prs[0][]?; . as $pr | (($pr.headRefName // "") | test("^(feature|fix|refactor|hotfix)/")) and (((($pr.headRefName // "") | test("^(feature|fix|refactor|hotfix)/([A-Za-z][A-Za-z0-9]{0,7}-)?" + ($number | tostring) + "(-|$)")) or ((($pr.title // "") + "\n" + ($pr.body // "")) | test("(^|[^0-9])#" + ($number | tostring) + "([^0-9]|$)"))))))]' \
    "$issues_file" > "$output_file"
}

filter_merged_prs_for_issues() {
  local merged_prs_file="$1" issues_file="$2" output_file="$3"
  jq --slurpfile issues "$issues_file" \
    '($issues[0] | map(.number)) as $issue_numbers | [.[] | . as $pr | select((($pr.headRefName // "") | test("^(feature|fix|refactor|hotfix)/")) and any($issue_numbers[]; . as $number | (($pr.headRefName // "") | test("^(feature|fix|refactor|hotfix)/([A-Za-z][A-Za-z0-9]{0,7}-)?" + ($number | tostring) + "(-|$)")) or ((($pr.title // "") + "\n" + ($pr.body // "")) | test("(^|[^0-9])#" + ($number | tostring) + "([^0-9]|$)"))))]' \
    "$merged_prs_file" > "$output_file"
}

# Explicit issues (file-backed loop — exits abort the main script)
if [ -n "$issues_arg" ]; then
  issues_list="$tmp_dir/issues-list.txt"
  printf '%s\n' "$issues_arg" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | awk 'NF' > "$issues_list"
  if [ ! -s "$issues_list" ]; then
    echo "--issues must contain at least one issue" >&2
    exit 64
  fi
  while IFS= read -r issue; do
    if ! printf '%s\n' "$issue" | grep -Eq '^[1-9][0-9]*$'; then
      echo "Invalid issue in --issues: $issue" >&2
      exit 64
    fi
    if ! gh issue view "$issue" --json number,title,url > "$tmp_dir/issue-$issue.json" 2>/dev/null; then
      echo "Failed to read issue #$issue" >&2
      exit 1
    fi
    number="$(jq -er '.number' "$tmp_dir/issue-$issue.json")" || exit 1
    title="$(jq -er '.title' "$tmp_dir/issue-$issue.json")" || exit 1
    url="$(jq -er '.url' "$tmp_dir/issue-$issue.json")" || exit 1
    append_candidate "issue" "$number" "$title" "$url" "explicit --issues input"
  done < "$issues_list"
fi

# Provider-backed tracker items resolved outside this helper. Keep this generic:
# Linear, Jira, ClickUp, GitHub Projects, and other trackers use different APIs.
if [ -n "$tracker_items_arg" ]; then
  tracker_items_list="$tmp_dir/tracker-items-list.txt"
  printf '%s\n' "$tracker_items_arg" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | awk 'NF' > "$tracker_items_list"
  if [ ! -s "$tracker_items_list" ]; then
    echo "--tracker-items must contain at least one tracker item" >&2
    exit 64
  fi
  while IFS= read -r tracker_item; do
    if ! printf '%s\n' "$tracker_item" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._:-]*$'; then
      echo "Invalid tracker item in --tracker-items: $tracker_item" >&2
      exit 64
    fi
    append_candidate "tracker_item" "$tracker_item" "$tracker_item" "" "explicit provider-backed tracker item input"
  done < "$tracker_items_list"
  append_note "Tracker items were supplied explicitly after provider-backed discovery outside this helper."
fi

# Recent merged PRs into base (intentionally capped; human confirms)
if [ "$recent_merged" -gt 0 ]; then
  if ! gh pr list --base "$base" --state merged --limit "$recent_merged" \
    --json number,title,url,mergedAt > "$tmp_dir/merged-prs.json"; then
    echo "Failed to list merged PRs for base '$base'" >&2
    exit 1
  fi
  append_rows_from_json_array "$tmp_dir/merged-prs.json" "pull_request" "recent merged PR into $base (limit $recent_merged)"
  append_note "Merged-PR proposal is capped at --recent-merged-prs=$recent_merged (not fully paginated)."
fi

epic_discovery_degraded=false
# Epic association (best-effort)
if [ -n "$epic" ]; then
  if ! gh issue view "$epic" --json number,title,url,labels,body > "$tmp_dir/epic.json" 2>/dev/null; then
    echo "Failed to read epic #$epic" >&2
    exit 1
  fi
  integration_label="$(jq -r '[.labels[].name] | map(select(startswith("integration-branch:"))) | .[0] // empty' "$tmp_dir/epic.json")" || {
    echo "Failed to parse epic labels" >&2
    exit 1
  }
  if [ -n "$integration_label" ]; then
    slug="${integration_label#integration-branch:}"
    expected_base="develop-${slug}"
    if [ "$base" != "$expected_base" ] && [ "$base" != "develop" ]; then
      append_note "Epic #$epic has $integration_label; QA base is '$base' (expected '$expected_base' or develop). Proceeding with best-effort label search."
    fi
    if gh issue list --label "$integration_label" --state all --limit 50 \
      --json number,title,url > "$tmp_dir/epic-issues.json" 2>/dev/null; then
      if gh pr list --base "$base" --state merged --limit 50 \
        --json number,title,url,mergedAt,headRefName,body > "$tmp_dir/epic-merged-prs.json"; then
        if ! filter_issues_referenced_by_merged_prs "$tmp_dir/epic-issues.json" "$tmp_dir/epic-merged-prs.json" "$tmp_dir/epic-merged-issues.json"; then
          echo "Failed to match epic issues to merged PRs for base '$base'" >&2
          exit 1
        fi
        append_rows_from_json_array "$tmp_dir/epic-merged-issues.json" "issue" "epic #$epic via $integration_label and merged PR references (limit 50)" "$epic"
        if ! filter_merged_prs_for_issues "$tmp_dir/epic-merged-prs.json" "$tmp_dir/epic-merged-issues.json" "$tmp_dir/epic-associated-prs.json"; then
          echo "Failed to match merged PRs to epic issues for base '$base'" >&2
          exit 1
        fi
        append_rows_from_json_array "$tmp_dir/epic-associated-prs.json" "pull_request" "epic #$epic associated merged PRs into $base (limit 50)"
        append_note "Epic issue and merged-PR lists are capped at 50 and include only explicitly associated items."
      else
        epic_discovery_degraded=true
        append_note "Could not list merged PRs for epic #$epic on $base; no label-only items were proposed."
      fi
    else
      epic_discovery_degraded=true
      append_note "Could not list issues for label $integration_label; ask the human to supply --issues."
    fi
  else
    append_note "Epic #$epic has no integration-branch:<slug> label; supply --issues or --recent-merged-prs for a concrete proposal."
  fi
fi

# Default: if no filters produced candidates, suggest recent merged
integration_discovery_degraded=false
if [ ! -s "$candidates_file" ] && [ "$recent_merged" -eq 0 ] && [ -z "$issues_arg" ] && [ -z "$tracker_items_arg" ] && [ -z "$epic" ]; then
  if [ "$tracker_discovery_required" = true ]; then
    append_note "Configured issue tracker '$tracker_provider' requires provider-backed post-merge discovery on develop. Resolve eligible items and pass them with --tracker-items before human confirmation; PR-derived fallback was not proposed."
  else
    if ! gh pr list --base "$base" --state merged --limit 10 \
      --json number,title,url,mergedAt,headRefName,body > "$tmp_dir/default-merged.json"; then
      echo "Failed to list default merged PRs for base '$base'" >&2
      exit 1
    fi
    if [[ "$base" =~ ^develop-(.+)$ ]]; then
      integration_slug="$(printf '%s' "$base" | sed 's/^develop-//')"
      integration_label="integration-branch:$integration_slug"
      if gh issue list --label "$integration_label" --state all --limit 50 \
        --json number,title,url > "$tmp_dir/default-integration-label-issues.json" 2>/dev/null; then
        filter_issues_referenced_by_merged_prs "$tmp_dir/default-integration-label-issues.json" "$tmp_dir/default-merged.json" "$tmp_dir/default-integration-issues.json" || {
          echo "Failed to match integration-branch issues to merged PRs for base '$base'" >&2
          exit 1
        }
        append_rows_from_json_array "$tmp_dir/default-integration-issues.json" "issue" "default integration branch via $integration_label and merged PR references (limit 50)"
        append_note "Integration-branch issue list is capped at 50 and includes only items explicitly referenced by merged PR title, body, or canonical branch name."
      else
        integration_discovery_degraded=true
        append_note "Could not list issues for label $integration_label; the default proposal includes only merged PRs."
      fi
    fi
    append_rows_from_json_array "$tmp_dir/default-merged.json" "pull_request" "default: up to 10 recent merged PRs into $base"
    append_note "No explicit scope flags; proposed up to 10 recent merged PRs into $base (capped, not fully paginated). Confirm or adjust before testing."
  fi
fi

candidates_json="$(if [ -s "$candidates_file" ]; then jq -e -s 'unique_by(.kind + ":" + .id)' "$candidates_file"; else printf '[]\n'; fi)" || {
  echo "Failed to build candidates JSON" >&2
  exit 1
}
notes_json="$(if [ -s "$notes_file" ]; then jq -e -s '[.[].note]' "$notes_file"; else printf '[]\n'; fi)" || {
  echo "Failed to build notes JSON" >&2
  exit 1
}

scope_source="merged-prs"
provider_backed=false
fallback=true
if [ -n "$tracker_items_arg" ]; then
  scope_source="tracker-post-merge"
  provider_backed=true
  fallback=false
elif [ -n "$issues_arg" ]; then
  scope_source="explicit"
  fallback=false
elif [ -n "$epic" ]; then
  scope_source="epic"
  if [ "$epic_discovery_degraded" = true ]; then
    fallback=true
  else
    fallback=false
  fi
elif [ "$recent_merged" -gt 0 ]; then
  scope_source="explicit"
  fallback=false
elif [ "$base" != "develop" ]; then
  if [ "$integration_discovery_degraded" = true ]; then
    scope_source="merged-prs"
  else
    scope_source="integration-branch"
    fallback=false
  fi
elif [ "$tracker_discovery_required" = true ]; then
  scope_source="tracker-post-merge"
  fallback=false
fi

confirmation_required=true
discovery_required=false
empty_scope_stop="If the human confirms an empty scope, stop without preflight, flows, or a fix PR."
if [ "$tracker_discovery_required" = true ] && [ ! -s "$candidates_file" ] && [ "$recent_merged" -eq 0 ] && [ -z "$issues_arg" ] && [ -z "$tracker_items_arg" ] && [ -z "$epic" ]; then
  confirmation_required=false
  discovery_required=true
  empty_scope_stop="Provider-backed tracker discovery is required before QA scope can be confirmed."
elif [ "$epic_discovery_degraded" = true ] && [ ! -s "$candidates_file" ]; then
  confirmation_required=false
  discovery_required=true
  empty_scope_stop="Epic discovery failed before a concrete QA scope could be confirmed; supply --issues, --tracker-items, or rerun discovery."
fi

result="$(jq -n \
  --arg base "$base" \
  --arg scope_source "$scope_source" \
  --argjson provider_backed "$provider_backed" \
  --argjson fallback "$fallback" \
  --argjson confirmation_required "$confirmation_required" \
  --argjson discovery_required "$discovery_required" \
  --argjson candidates "$candidates_json" \
  --argjson notes "$notes_json" \
  --arg empty_scope_stop "$empty_scope_stop" \
  '{
    base: $base,
    scopeSource: $scope_source,
    providerBacked: $provider_backed,
    fallback: $fallback,
    candidateCount: ($candidates | length),
    candidates: $candidates,
    notes: $notes,
    confirmationRequired: $confirmation_required,
    discoveryRequired: $discovery_required,
    emptyScopeStop: $empty_scope_stop,
    readOnlyGuarantee: "No tracker updates, branch creation, PR edits, merges, issue closure, or flow exercise were performed."
  }')" || {
  echo "Failed to build scope proposal JSON" >&2
  exit 1
}

if [ "$json_output" -eq 1 ]; then
  printf '%s\n' "$result"
else
  printf 'QA base: %s\n' "$base"
  printf 'Scope source: %s\n' "$(printf '%s' "$result" | jq -er '.scopeSource')"
  printf 'Provider-backed: %s\n' "$(printf '%s' "$result" | jq -er '.providerBacked')"
  printf 'Fallback: %s\n' "$(printf '%s' "$result" | jq -er '.fallback')"
  printf 'Candidates: %s\n' "$(printf '%s' "$result" | jq -er '.candidateCount')"
  printf '%s\n' "$result" | jq -r '.candidates[]? | "- [\(.kind) #\(.number // .id)] \(.title) — \(.reason)"'
  printf '%s\n' "$result" | jq -r '.notes[]? | "Note: \(.)"'
  if [ "$(printf '%s' "$result" | jq -er '.confirmationRequired')" = true ]; then
    echo "Confirmation required before exercising flows."
  else
    echo "Provider-backed tracker discovery is required before QA scope can be confirmed."
  fi
  echo "Read-only guarantee: No tracker updates, branch creation, PR edits, merges, issue closure, or flow exercise were performed."
fi
