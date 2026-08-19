#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"

# shellcheck source=scripts/development-workflow/workflow-lib.sh
source "$SCRIPT_DIR/workflow-lib.sh"

usage() {
  cat <<'EOF'
Usage:
  add-backlog-item.sh resolve
  add-backlog-item.sh create --title <title> (--body <text> | --body-file <path>) [--label <name>] ... [--type <value>] [--priority <value>] [--size <value>]

resolve
  Prints machine-readable lines:
    ISSUE_TRACKER_PROVIDER=<raw or empty>
    DESTINATION_KIND=github|linear|other|none
    CREATE_VIA=<hint for agents>

create
  When DESTINATION_KIND is github, creates one GitHub issue via gh (requires gh auth).
  For linear, other, or none, exits non-zero with guidance (agents follow 00-add-backlog-item-protocol.md).

  --priority <value>  Optional. Set the project Priority field. The value is
                      resolved against the project's actual Priority field
                      options (see docs/workflow/development-workflow/integrations/github-projects.md);
                      typical boards use Urgent, High, Medium, Low.
                      When omitted, defaults to Medium for GitHub Projects.
                      A value that cannot be resolved against the board's
                      Priority options is a hard error (non-zero exit).
  --size <value>      Optional. Set the project Size field. Valid values: XS, S, M, L, XL.
                      When omitted, the Size field is left unset.
  --type <value>      Optional. Set the project classification field. Valid values: Feature, Bug,
                      Refactor, Workflow. When omitted, the Type field is left unset.
EOF
}

resolve_cmd() {
  cd_workflow_repo_root
  local raw kind
  raw="$(workflow_issue_tracker_provider_raw)"
  kind="$(workflow_backlog_destination_kind)"
  print_kv ISSUE_TRACKER_PROVIDER "${raw:-}"
  print_kv DESTINATION_KIND "$kind"
  case "$kind" in
    github) print_kv CREATE_VIA "gh_issue_create" ;;
    linear) print_kv CREATE_VIA "linear_mcp_or_api" ;;
    other) print_kv CREATE_VIA "manual_or_tracker_specific_mcp" ;;
    none) print_kv CREATE_VIA "configure_issue_tracker_or_ask_human" ;;
  esac
}

create_cmd() {
  local caller_pwd="$PWD"
  local title="" body="" body_file="" priority="" size="" type_label="" labels=()

  while [ $# -gt 0 ]; do
    case "$1" in
      --title)
        [ $# -lt 2 ] && { echo "Missing value for --title" >&2; usage >&2; exit 2; }
        title="$2"
        shift 2
        ;;
      --body)
        [ $# -lt 2 ] && { echo "Missing value for --body" >&2; usage >&2; exit 2; }
        body="$2"
        shift 2
        ;;
      --body-file)
        [ $# -lt 2 ] || [ -z "${2:-}" ] && { echo "Missing value for --body-file" >&2; usage >&2; exit 2; }
        body_file="$2"
        shift 2
        ;;
      --label)
        [ $# -lt 2 ] || [ -z "${2:-}" ] && { echo "Missing value for --label" >&2; usage >&2; exit 2; }
        labels+=("$2")
        shift 2
        ;;
      --priority)
        [ $# -lt 2 ] || [ -z "${2:-}" ] && { echo "Missing value for --priority" >&2; usage >&2; exit 2; }
        priority="$2"
        shift 2
        ;;
      --size)
        [ $# -lt 2 ] || [ -z "${2:-}" ] && { echo "Missing value for --size" >&2; usage >&2; exit 2; }
        size="$2"
        shift 2
        ;;
      --type)
        [ $# -lt 2 ] || [ -z "${2:-}" ] && { echo "Missing value for --type" >&2; usage >&2; exit 2; }
        type_label="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "Unknown argument: $1" >&2
        usage >&2
        exit 2
        ;;
    esac
  done

  if [ -n "$body_file" ] && [ "$body_file" != "-" ] && [[ "$body_file" != /* ]]; then
    body_file="$caller_pwd/$body_file"
  fi
  cd_workflow_repo_root

  local kind
  kind="$(workflow_backlog_destination_kind)"

  if [ "$kind" = "github" ]; then
    require_gh
    if [ -z "$title" ]; then
      echo "create: --title is required" >&2
      exit 2
    fi
    if [ -n "$body_file" ]; then
      body="$(cat -- "$body_file")"
    fi
    local -a gh_args=(issue create --title "$title")
    if [ -n "$body" ]; then
      gh_args+=(--body "$body")
    fi
    local label
    for label in "${labels[@]+"${labels[@]}"}"; do
      [ -n "$label" ] || continue
      gh_args+=(--label "$label")
    done
    # Capture the issue URL. Under set -euo pipefail, a non-zero exit from
    # gh issue create aborts the script immediately — no separate exit-code
    # check is required. The URL is the only output on success.
    local issue_url issue_number
    issue_url="$(gh "${gh_args[@]}")"
    # Trim leading/trailing whitespace so extraction is robust against any
    # trailing newline or extra whitespace in the gh output.
    issue_url="${issue_url#"${issue_url%%[! ]*}"}"  # ltrim spaces
    issue_url="${issue_url%"${issue_url##*[! ]}"}"  # rtrim spaces
    printf '%s\n' "$issue_url"
    # Extract and validate the issue number from the URL (last path segment).
    # The URL is always https://github.com/<owner>/<repo>/issues/<number>.
    issue_number="${issue_url##*/}"
    # Skip project field updates when the issue number cannot be resolved to a
    # numeric value (e.g. gh output was unexpected or the URL was malformed).
    case "$issue_number" in
      ''|*[!0-9]*)
        echo "Warning: could not extract a numeric issue number from gh output '${issue_url}'; skipping project field updates." >&2
        return 0
        ;;
    esac
    # Ensure the issue is on the project board (adds it with Status=Backlog if absent).
    # The ensure_on_project_board helper is fail-open; it always returns 0.
    ensure_on_project_board "$issue_number" "Backlog"
    # Update project Type, Priority (default Medium), and Size when GitHub Projects is configured.
    # update_tracker_type_best_effort and update_tracker_size_best_effort are fail-open (always
    # return 0). update_tracker_priority_best_effort is a hard error (non-zero exit) when the
    # tracker provider/project are configured but the requested priority value cannot be resolved
    # against the board's actual Priority field options — under `set -euo pipefail` this aborts
    # the script so a bad or stale priority value is never silently dropped.
    if [ -n "$type_label" ]; then
      update_tracker_type_best_effort "$issue_number" "$type_label"
    fi
    local effective_priority="${priority:-Medium}"
    update_tracker_priority_best_effort "$issue_number" "$effective_priority"
    if [ -n "$size" ]; then
      update_tracker_size_best_effort "$issue_number" "$size"
    fi
    return 0
  fi

  if [ "$kind" = "linear" ]; then
    # Single-quote the title when it contains spaces so downstream parsers can
    # unambiguously extract the value without splitting on internal whitespace.
    case "$title" in
      *' '*)
        printf "TRACKER_ACTION_REQUIRED=create_item title='%s'\n" "$title"
        ;;
      *)
        printf 'TRACKER_ACTION_REQUIRED=create_item title=%s\n' "$title"
        ;;
    esac
    echo "add-backlog-item: Linear backlog creation requires the orchestrator. Use Linear MCP/API per docs/workflow/development-workflow/integrations/linear.md" >&2
    return 0
  fi

  if [ "$kind" = "none" ]; then
    echo "add-backlog-item: issue_tracker.provider is unset or none. Configure .ai-dev-workflow.yaml or ask the human where to create the item (see docs/workflow/development-workflow/protocols/00-add-backlog-item-protocol.md)" >&2
    exit 3
  fi

  echo "add-backlog-item: issue_tracker.provider is not supported for automatic creation by this script. Create the item in the configured tracker manually or via MCP." >&2
  exit 4
}

main() {
  case "${1:-}" in
    resolve)
      resolve_cmd
      ;;
    create)
      shift
      create_cmd "$@"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
}

main "$@"
