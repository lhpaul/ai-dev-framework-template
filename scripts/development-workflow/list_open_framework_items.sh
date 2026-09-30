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
the lookup could not be performed, with one of eleven closed-list REASON
values: provider_unsupported, project_number_missing,
project_number_invalid, project_owner_unresolvable, repo_unresolvable,
issue_list_failed, issue_list_blank_or_malformed, issue_list_truncated,
item_list_failed, item_list_unparseable, item_list_truncated.

Both reads are exhaustive: the open-issue list and the project item list
are re-read with a larger fetch cap until complete. A repository or board
still larger than the hard bound (64000 records) is reported as
issue_list_truncated / item_list_truncated rather than a partial list.
Board items join open issues by repository AND number; an item from another
repository, or one that identifies no repository, is never matched.

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

# codex-github finding (#1583): workflow_template_is_template (and the
# config-provider/project-number readers below) default to
# workflow_config_file(), which resolves relative to workflow-lib.sh's own
# location, NOT the current directory — so --repo-root pointing at a
# different repository would silently read framework mode from the wrong
# config. Resolve and pass the target repo's own config file explicitly
# everywhere this script reads mode/provider/project-number, now that the
# cd above has landed us in the requested repository root.
fm_config_file="$PWD/.ai-dev-workflow.yaml"

is_template="$(workflow_template_is_template "$fm_config_file")"

if [ "$is_template" != "true" ]; then
  consumer_json="$(list_open_workflow_type_issues)"
  print_kv FRAMEWORK_ITEMS_LOOKUP_STATUS "ok"
  print_kv FRAMEWORK_ITEMS_LOOKUP_REASON ""
  printf 'FRAMEWORK_ITEMS_JSON=%s\n' "$consumer_json"
  exit 0
fi

# --- Framework mode: own all-open-items lookup, never Type-filtered. ---

fm_provider="$(workflow_normalize_issue_tracker_provider "$(workflow_config_provider issue_tracker "$fm_config_file")")"
if [ "$fm_provider" != "github_projects" ]; then
  _emit_unavailable "provider_unsupported"
  exit 0
fi

fm_project_number="${GITHUB_PROJECT_NUMBER:-$(workflow_config_field issue_tracker project_number "$fm_config_file")}"
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

# Exhaustive read (#1804): --limit is a fetch cap, so the helper repeats the
# read with a larger cap until the result is provably complete, and refuses
# a still-truncated list past WORKFLOW_GH_LIST_MAX_RECORDS.
fm_read_rc=0
fm_open_issues="$(workflow_gh_list_open_issues_exhaustive "$fm_repo_slug")" || fm_read_rc=$?
case "$fm_read_rc" in
  0) ;;
  2)
    _emit_unavailable "issue_list_blank_or_malformed"
    exit 0
    ;;
  3)
    _emit_unavailable "issue_list_truncated"
    exit 0
    ;;
  *)
    _emit_unavailable "issue_list_failed"
    exit 0
    ;;
esac
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

# --query "is:issue" excludes pull requests and draft issues from the
# project item list: issue and PR content share independent number
# sequences within a project's cross-repository scope, so joining by
# .content.number alone (below) could otherwise accept a PR item whose
# number happens to match an open issue's number, and emit that issue with
# the PR's status/priority/type (codex-github finding, #1583).
fm_read_rc=0
fm_project_items="$(workflow_gh_project_items_exhaustive "$fm_project_number" "$fm_owner" "is:issue")" || fm_read_rc=$?
case "$fm_read_rc" in
  0) ;;
  2)
    _emit_unavailable "item_list_unparseable"
    exit 0
    ;;
  3)
    _emit_unavailable "item_list_truncated"
    exit 0
    ;;
  *)
    _emit_unavailable "item_list_failed"
    exit 0
    ;;
esac

# Framework mode never reads Type for FILTERING (that is the whole point of
# this wrapper — see framework-lookup-ignores-type-field), but the output
# JSON still reports the classification value for release/retrospective
# consumers, so that projection must resolve the same configured/fallback
# candidate key set the (untouched) Workflow lookup primitive uses, not a
# hardcoded ".type" — a board with issue_tracker.custom_fields.type_field
# set to e.g. "Custom Type" exposes that value under a derived item-list
# key, never literally "type" (codex-github finding, #1583).
fm_type_preferred_field="$(workflow_issue_tracker_custom_field type_field "$fm_config_file")"
fm_type_candidate_keys_json="$(_workflow_lowti_candidate_keys_json "$fm_type_preferred_field")"

# Join by issue number is only safe within one repository: an
# organization-owned project can span multiple repositories, and issue
# numbers are not globally unique across them (codex-github finding,
# #1583). Join by (repository, number): the item's repository comes from
# the live-verified content.repository ("owner/repo") or, failing that,
# content.url; an item that identifies no repository is never joined
# (fails closed, #1804). See WORKFLOW_PROJECT_ITEM_REPO_JQ_DEFS.
#
# The open issues reach jq through a file (--slurpfile), never as one
# --argjson argument: a large repository's issue list would exceed the OS
# argument-size limit and fail the join (#1804).
if ! fm_open_file="$(workflow_json_to_tmpfile "$fm_open_issues")"; then
  _emit_unavailable "issue_list_failed"
  exit 0
fi
trap 'rm -f "$fm_open_file"' EXIT
if ! fm_result_json="$(printf '%s' "$fm_project_items" | jq -c --slurpfile openDocs "$fm_open_file" --arg repoSlug "$fm_repo_slug" --argjson candidateKeys "$fm_type_candidate_keys_json" "$WORKFLOW_PROJECT_ITEM_REPO_JQ_DEFS"'
  def terminal($status):
    ($status // "") as $s
    | ($s == "Done" or $s == "Merged" or $s == "Released" or $s == "Cancelled");

  def item_type($item):
    ( [ $candidateKeys[] as $k | ($item[$k] // "") ] | map(select(. != "")) | first ) // "";

  ($openDocs[0] | issue_index) as $openByNumber
  | [ .items[]
    | . as $item
    | select(same_repo_item($item; $repoSlug))
    | ($openByNumber[($item.content.number | tostring)] // empty) as $issue
    | select(terminal($item.status) | not)
    | {
        number: $issue.number,
        title: $issue.title,
        url: $issue.url,
        createdAt: $issue.createdAt,
        status: ($item.status // ""),
        priority: ($item.priority // ""),
        type: item_type($item)
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
