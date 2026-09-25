#!/usr/bin/env bash
# list_open_framework_items.sh — the only supported entrypoint for
# release/retrospective "open framework items" reads (#1583).
#
# Consumer repositories (template.is_template not true): delegates to the
# unchanged list_open_workflow_type_issues primitive, which keeps
# Workflow-only filtering in BOTH modes — this wrapper never changes that
# primitive.
#
# Framework-mode repositories: performs its own lookup of every open,
# non-terminal project item linked to an open repo issue, REGARDLESS of
# Type — because a framework-mode repository refuses to file new Workflow
# items (see add-backlog-item.sh), so a Workflow-only filter would silently
# stop discovering this repository's own open framework work.
#
# Always prints exactly these three keys, in this order, before exiting —
# every mode, every outcome:
#   FRAMEWORK_ITEMS_LOOKUP_STATUS=ok|empty|unavailable
#   FRAMEWORK_ITEMS_LOOKUP_REASON=<empty, or a reason when STATUS=unavailable>
#   FRAMEWORK_ITEMS_JSON=<compact JSON array>
#
# Exact key spellings — no glob shorthand. The third key has NO "LOOKUP_"
# segment, so a FRAMEWORK_ITEMS_LOOKUP_* glob does not cover it.
#
# Exit codes: lookup outcomes (ok / empty / unavailable) always exit 0, so a
# `set -e` caller can capture stdout and branch on STATUS without the
# wrapper itself aborting the shell. Non-zero is reserved for usage errors.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=scripts/development-workflow/workflow-lib.sh
source "$SCRIPT_DIR/workflow-lib.sh"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/development-workflow/list_open_framework_items.sh [--repo-root <path>]

Prints, on stdout, before exit (always, in every mode):
  FRAMEWORK_ITEMS_LOOKUP_STATUS=ok|empty|unavailable
  FRAMEWORK_ITEMS_LOOKUP_REASON=<empty, or a reason when STATUS=unavailable>
  FRAMEWORK_ITEMS_JSON=<compact JSON array>

Consumer repositories (template.is_template not true) always print
STATUS=ok and delegate to list_open_workflow_type_issues (Workflow-only
filtering, unchanged).

Framework-mode repositories (template.is_template: true) return every
open, non-terminal board item regardless of Type. STATUS=unavailable when
the lookup could not be performed, with one of nine closed-list REASON
values: provider_unsupported, project_number_missing,
project_number_invalid, project_owner_unresolvable, repo_unresolvable,
issue_list_failed, issue_list_blank_or_malformed, item_list_failed,
item_list_unparseable.

Exit codes: 0 for every lookup outcome (ok / empty / unavailable). Non-zero
only for a usage error (bad arguments).
EOF
}

_emit_unavailable() {
  local reason="$1"
  print_kv FRAMEWORK_ITEMS_LOOKUP_STATUS "unavailable"
  print_kv FRAMEWORK_ITEMS_LOOKUP_REASON "$reason"
  printf 'FRAMEWORK_ITEMS_JSON=[]\n'
  echo "Warning: framework-mode open-items lookup unavailable (${reason})." >&2
}

repo_root_override=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo-root)
      [ $# -lt 2 ] || [ -z "${2:-}" ] && { echo "Missing value for --repo-root" >&2; usage >&2; exit 64; }
      repo_root_override="$2"
      shift 2
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

if [ -n "$repo_root_override" ]; then
  cd -- "$repo_root_override"
else
  cd_workflow_repo_root
fi

is_template="$(workflow_template_is_template)"

if [ "$is_template" != "true" ]; then
  consumer_json="$(list_open_workflow_type_issues)"
  print_kv FRAMEWORK_ITEMS_LOOKUP_STATUS "ok"
  print_kv FRAMEWORK_ITEMS_LOOKUP_REASON ""
  printf 'FRAMEWORK_ITEMS_JSON=%s\n' "$consumer_json"
  exit 0
fi

# --- Framework mode: own all-open-items lookup, never Type-filtered. ---

fm_provider="$(workflow_normalize_issue_tracker_provider "$(workflow_issue_tracker_provider_raw)")"
if [ "$fm_provider" != "github_projects" ]; then
  _emit_unavailable "provider_unsupported"
  exit 0
fi

fm_project_number="${GITHUB_PROJECT_NUMBER:-$(workflow_issue_tracker_project_number)}"
if [ -z "$fm_project_number" ]; then
  _emit_unavailable "project_number_missing"
  exit 0
fi
case "$fm_project_number" in
  *[!0-9]*)
    _emit_unavailable "project_number_invalid"
    exit 0
    ;;
esac

fm_owner="$(workflow_resolve_github_project_owner)"
if [ -z "$fm_owner" ]; then
  fm_owner="$(workflow_resolve_github_repo_owner)"
fi
if [ -z "$fm_owner" ]; then
  _emit_unavailable "project_owner_unresolvable"
  exit 0
fi

fm_repo_owner="$(workflow_resolve_github_repo_owner)"
fm_repo_name="$(workflow_resolve_github_repo_name)"
if [ -z "$fm_repo_owner" ] || [ -z "$fm_repo_name" ]; then
  _emit_unavailable "repo_unresolvable"
  exit 0
fi
fm_repo_slug="${fm_repo_owner}/${fm_repo_name}"

if ! fm_open_issues="$(gh issue list --repo "$fm_repo_slug" --state open --limit 1000 --json number,title,labels,createdAt,url 2>/dev/null)"; then
  _emit_unavailable "issue_list_failed"
  exit 0
fi
# A blank result is checked for emptiness only by list_open_workflow_type_issues
# and returned as [] — indistinguishable there from "no open issues" (see
# workflow-lib.sh:list_open_workflow_type_issues). This wrapper validates the
# response instead: blank, or non-array JSON, is unavailable, never empty.
if [ -z "$fm_open_issues" ]; then
  _emit_unavailable "issue_list_blank_or_malformed"
  exit 0
fi
if ! printf '%s' "$fm_open_issues" | jq -e 'type == "array"' >/dev/null 2>&1; then
  _emit_unavailable "issue_list_blank_or_malformed"
  exit 0
fi

if ! fm_project_items="$(gh project item-list "$fm_project_number" --owner "$fm_owner" --limit 1000 --format json 2>/dev/null)"; then
  _emit_unavailable "item_list_failed"
  exit 0
fi

if ! fm_result_json="$(printf '%s' "$fm_project_items" | jq -c --argjson open "$fm_open_issues" '
  def terminal($status):
    ($status // "") as $s
    | ($s == "Done" or $s == "Merged" or $s == "Released" or $s == "Cancelled");

  [ .items[]
    | . as $item
    | ($open[] | select(.number == $item.content.number)) as $issue
    | select(terminal($item.status) | not)
    | {
        number: $issue.number,
        title: $issue.title,
        url: $issue.url,
        createdAt: $issue.createdAt,
        status: ($item.status // ""),
        priority: ($item.priority // ""),
        type: ($item.type // "")
      }
  ]
' 2>/dev/null)"; then
  _emit_unavailable "item_list_unparseable"
  exit 0
fi

fm_count="$(printf '%s' "$fm_result_json" | jq 'length' 2>/dev/null || printf '')"
if [ -z "$fm_count" ]; then
  _emit_unavailable "item_list_unparseable"
  exit 0
fi

if [ "$fm_count" -eq 0 ]; then
  print_kv FRAMEWORK_ITEMS_LOOKUP_STATUS "empty"
  print_kv FRAMEWORK_ITEMS_LOOKUP_REASON ""
  printf 'FRAMEWORK_ITEMS_JSON=%s\n' "${fm_result_json:-[]}"
  exit 0
fi

print_kv FRAMEWORK_ITEMS_LOOKUP_STATUS "ok"
print_kv FRAMEWORK_ITEMS_LOOKUP_REASON ""
printf 'FRAMEWORK_ITEMS_JSON=%s\n' "$fm_result_json"
