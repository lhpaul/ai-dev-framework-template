#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

# shellcheck source=scripts/development-workflow/workflow-lib.sh
source "$SCRIPT_DIR/workflow-lib.sh"

usage() {
  cat <<'EOF'
Usage:
  add-backlog-item.sh resolve
  add-backlog-item.sh create --title <title> (--body <text> | --body-file <path>) [--label <name>] ...

resolve
  Prints machine-readable lines:
    ISSUE_TRACKER_PROVIDER=<raw or empty>
    DESTINATION_KIND=github|linear|other|none
    CREATE_VIA=<hint for agents>

create
  When DESTINATION_KIND is github, creates one GitHub issue via gh (requires gh auth).
  For linear, other, or none, exits non-zero with guidance (agents follow 00-add-backlog-item-protocol.md).
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
  local title="" body="" body_file="" labels=()

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
        [ $# -lt 2 ] && { echo "Missing value for --body-file" >&2; usage >&2; exit 2; }
        body_file="$2"
        shift 2
        ;;
      --label)
        [ $# -lt 2 ] && { echo "Missing value for --label" >&2; usage >&2; exit 2; }
        labels+=("$2")
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
    gh "${gh_args[@]}"
    return 0
  fi

  if [ "$kind" = "linear" ]; then
    echo "add-backlog-item: Linear backlog creation is not performed by this script. Use Linear MCP/API per docs/workflow/development-workflow/integrations/linear.md" >&2
    exit 2
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
