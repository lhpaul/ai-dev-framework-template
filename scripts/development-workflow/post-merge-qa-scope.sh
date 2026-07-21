#!/usr/bin/env bash
# post-merge-qa-scope.sh — read-only scope proposal for /post-merge-qa
#
# Proposes QA candidates for human confirmation. Does not update trackers,
# create branches, open PRs, or exercise application flows.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=scripts/development-workflow/workflow-lib.sh
source "$SCRIPT_DIR/workflow-lib.sh"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/development-workflow/post-merge-qa-scope.sh --base <develop|develop-slug>
      [--epic <number>] [--issues <csv>] [--recent-merged-prs <n>] [--json]

Read-only: proposes post-merge QA scope for human confirmation.
EOF
}

base=""
epic=""
issues_arg=""
recent_merged=0
json_output=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --base)
      shift
      base="${1:-}"
      shift
      ;;
    --epic)
      shift
      epic="${1:-}"
      shift
      ;;
    --issues)
      shift
      issues_arg="${1:-}"
      shift
      ;;
    --recent-merged-prs)
      shift
      recent_merged="${1:-0}"
      shift
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

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

candidates_file="$tmp_dir/candidates.jsonl"
: > "$candidates_file"
notes_file="$tmp_dir/notes.jsonl"
: > "$notes_file"

append_note() {
  jq -nc --arg note "$1" '{note: $note}' >> "$notes_file"
}

append_candidate() {
  local kind="$1" number="$2" title="$3" url="$4" reason="$5"
  jq -nc \
    --arg kind "$kind" \
    --argjson number "$number" \
    --arg title "$title" \
    --arg url "$url" \
    --arg reason "$reason" \
    '{kind: $kind, number: $number, title: $title, url: $url, reason: $reason}' \
    >> "$candidates_file"
}

# Explicit issues
if [ -n "$issues_arg" ]; then
  printf '%s\n' "$issues_arg" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | awk 'NF' | while IFS= read -r issue; do
    if ! printf '%s\n' "$issue" | grep -Eq '^[1-9][0-9]*$'; then
      echo "Invalid issue in --issues: $issue" >&2
      exit 64
    fi
    if ! gh issue view "$issue" --json number,title,url > "$tmp_dir/issue-$issue.json" 2>/dev/null; then
      echo "Failed to read issue #$issue" >&2
      exit 1
    fi
    jq -r '[.number, .title, .url] | @tsv' "$tmp_dir/issue-$issue.json" | while IFS=$'\t' read -r number title url; do
      append_candidate "issue" "$number" "$title" "$url" "explicit --issues input"
    done
  done
fi

# Recent merged PRs into base
if [ "$recent_merged" -gt 0 ]; then
  if ! gh pr list --base "$base" --state merged --limit "$recent_merged" \
    --json number,title,url,mergedAt > "$tmp_dir/merged-prs.json"; then
    echo "Failed to list merged PRs for base '$base'" >&2
    exit 1
  fi
  jq -c '.[]' "$tmp_dir/merged-prs.json" | while IFS= read -r row; do
    number="$(printf '%s' "$row" | jq -r '.number')"
    title="$(printf '%s' "$row" | jq -r '.title')"
    url="$(printf '%s' "$row" | jq -r '.url')"
    append_candidate "pull_request" "$number" "$title" "$url" "recent merged PR into $base"
  done
fi

# Epic association (best-effort)
if [ -n "$epic" ]; then
  if ! gh issue view "$epic" --json number,title,url,labels,body > "$tmp_dir/epic.json" 2>/dev/null; then
    echo "Failed to read epic #$epic" >&2
    exit 1
  fi
  integration_label="$(jq -r '[.labels[].name] | map(select(startswith("integration-branch:"))) | .[0] // empty' "$tmp_dir/epic.json")"
  if [ -n "$integration_label" ]; then
    slug="${integration_label#integration-branch:}"
    expected_base="develop-${slug}"
    if [ "$base" != "$expected_base" ] && [ "$base" != "develop" ]; then
      append_note "Epic #$epic has $integration_label; QA base is '$base' (expected '$expected_base' or develop). Proceeding with best-effort label search."
    fi
    # Search issues carrying the same integration-branch label
    if gh issue list --label "$integration_label" --state all --limit 50 \
      --json number,title,url > "$tmp_dir/epic-issues.json" 2>/dev/null; then
      jq -c '.[]' "$tmp_dir/epic-issues.json" | while IFS= read -r row; do
        number="$(printf '%s' "$row" | jq -r '.number')"
        title="$(printf '%s' "$row" | jq -r '.title')"
        url="$(printf '%s' "$row" | jq -r '.url')"
        # Skip the epic issue itself when it appears in the list
        if [ "$number" = "$epic" ]; then
          continue
        fi
        append_candidate "issue" "$number" "$title" "$url" "epic #$epic via $integration_label"
      done
    else
      append_note "Could not list issues for label $integration_label; ask the human to supply --issues."
    fi
  else
    append_note "Epic #$epic has no integration-branch:<slug> label; supply --issues or --recent-merged-prs for a concrete proposal."
  fi
fi

# Default: if no filters produced candidates and no notes about missing data, suggest recent merged
if [ ! -s "$candidates_file" ] && [ "$recent_merged" -eq 0 ] && [ -z "$issues_arg" ] && [ -z "$epic" ]; then
  if ! gh pr list --base "$base" --state merged --limit 10 \
    --json number,title,url,mergedAt > "$tmp_dir/default-merged.json"; then
    echo "Failed to list default merged PRs for base '$base'" >&2
    exit 1
  fi
  jq -c '.[]' "$tmp_dir/default-merged.json" | while IFS= read -r row; do
    number="$(printf '%s' "$row" | jq -r '.number')"
    title="$(printf '%s' "$row" | jq -r '.title')"
    url="$(printf '%s' "$row" | jq -r '.url')"
    append_candidate "pull_request" "$number" "$title" "$url" "default: up to 10 recent merged PRs into $base"
  done
  append_note "No explicit scope flags; proposed up to 10 recent merged PRs into $base. Confirm or adjust before testing."
fi

candidates_json="$(if [ -s "$candidates_file" ]; then jq -s 'unique_by(.kind + ":" + (.number|tostring))' "$candidates_file"; else printf '[]\n'; fi)"
notes_json="$(if [ -s "$notes_file" ]; then jq -s '[.[].note]' "$notes_file"; else printf '[]\n'; fi)"

result="$(jq -n \
  --arg base "$base" \
  --argjson candidates "$candidates_json" \
  --argjson notes "$notes_json" \
  '{
    base: $base,
    candidateCount: ($candidates | length),
    candidates: $candidates,
    notes: $notes,
    confirmationRequired: true,
    emptyScopeStop: "If the human confirms an empty scope, stop without preflight, flows, or a fix PR.",
    readOnlyGuarantee: "No tracker updates, branch creation, PR edits, merges, issue closure, or flow exercise were performed."
  }')"

if [ "$json_output" -eq 1 ]; then
  printf '%s\n' "$result"
else
  printf 'QA base: %s\n' "$base"
  printf 'Candidates: %s\n' "$(printf '%s' "$result" | jq -r '.candidateCount')"
  printf '%s\n' "$result" | jq -r '.candidates[]? | "- [\(.kind) #\(.number)] \(.title) — \(.reason)"'
  printf '%s\n' "$result" | jq -r '.notes[]? | "Note: \(.)"'
  echo "Confirmation required before exercising flows."
  echo "Read-only guarantee: No tracker updates, branch creation, PR edits, merges, issue closure, or flow exercise were performed."
fi
