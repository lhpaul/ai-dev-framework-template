#!/usr/bin/env bash
# framework-mode-backlog-type-gate.sh — Backlog routing gate for Type
# Workflow in framework-mode repositories (#1583). Pinned name: smoke tests
# and the two callers below (run-bounded-prelude.sh, workflow-batch-plan.sh)
# call this exact path.
#
# Stops (single-item caller) or holds (scan caller) exactly when: framework
# mode, Type reads as Workflow, reconciled tracker status is Backlog, the
# artifact stage is empty (no development-folder spec/plan), and there is no
# branch/PR evidence of implementation work already started. Every other
# combination is RESULT=pass — this gate never re-decides an item already on
# a pipeline, and it fails OPEN on every unreadable input, never closed.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=scripts/development-workflow/workflow-lib.sh
source "$SCRIPT_DIR/workflow-lib.sh"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/development-workflow/framework-mode-backlog-type-gate.sh \
    --issue <n> --status <tracker-status> --artifact-stage <stage-or-empty> \
    --branch-pr-evidence <none|present|unavailable> --caller <single|scan> \
    [--type <value>] [--repo-root <path>]

All five of --issue, --status, --artifact-stage, --branch-pr-evidence, and
--caller are REQUIRED, even when the value is the empty string (--status ''
and --artifact-stage '' are accepted values, not missing arguments).

--type is optional: when omitted the gate reads Type itself via
get_tracker_type_for_issue. Pass it only when the caller already holds the
value (avoids a second tracker read).

Usage errors (missing/invalid flag) print this message to stderr and exit
64, with NO "RESULT=" line printed. Routing outcomes (pass/hold/stop)
always exit 0; callers under `set -e` branch on RESULT, not exit status.
EOF
}

usage_error() {
  echo "$1" >&2
  usage >&2
  exit 64
}

issue=""
issue_set=0
status_value=""
status_set=0
artifact_stage=""
artifact_stage_set=0
branch_pr_evidence=""
branch_pr_evidence_set=0
caller=""
caller_set=0
type_value=""
type_set=0
repo_root_override=""

while [ $# -gt 0 ]; do
  case "$1" in
    --issue)
      [ $# -lt 2 ] && usage_error "Missing value for --issue"
      issue="${2#\#}"
      issue_set=1
      shift 2
      ;;
    --status)
      [ $# -lt 2 ] && usage_error "Missing value for --status"
      status_value="$2"
      status_set=1
      shift 2
      ;;
    --artifact-stage)
      [ $# -lt 2 ] && usage_error "Missing value for --artifact-stage"
      artifact_stage="$2"
      artifact_stage_set=1
      shift 2
      ;;
    --branch-pr-evidence)
      [ $# -lt 2 ] && usage_error "Missing value for --branch-pr-evidence"
      branch_pr_evidence="$2"
      branch_pr_evidence_set=1
      shift 2
      ;;
    --caller)
      [ $# -lt 2 ] && usage_error "Missing value for --caller"
      caller="$2"
      caller_set=1
      shift 2
      ;;
    --type)
      [ $# -lt 2 ] && usage_error "Missing value for --type"
      type_value="$2"
      type_set=1
      shift 2
      ;;
    --repo-root)
      [ $# -lt 2 ] || [ -z "${2:-}" ] && usage_error "Missing value for --repo-root"
      repo_root_override="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage_error "Unknown argument: $1"
      ;;
  esac
done

[ "$issue_set" -eq 1 ] || usage_error "--issue is required"
[ "$status_set" -eq 1 ] || usage_error "--status is required"
[ "$artifact_stage_set" -eq 1 ] || usage_error "--artifact-stage is required"
[ "$branch_pr_evidence_set" -eq 1 ] || usage_error "--branch-pr-evidence is required"
[ "$caller_set" -eq 1 ] || usage_error "--caller is required"

case "$issue" in
  ''|*[!0-9]*) usage_error "--issue must be a positive integer (with or without a leading #): '$issue'" ;;
esac

case "$caller" in
  single|scan) ;;
  *) usage_error "--caller must be 'single' or 'scan': '$caller'" ;;
esac

case "$artifact_stage" in
  ''|'Spec Ready'|'Plan Ready'|'In Development'|Done|Unknown) ;;
  *) usage_error "--artifact-stage must be one of: '', 'Spec Ready', 'Plan Ready', 'In Development', 'Done', 'Unknown': '$artifact_stage'" ;;
esac

case "$branch_pr_evidence" in
  none|present|unavailable) ;;
  *) usage_error "--branch-pr-evidence must be one of: none, present, unavailable: '$branch_pr_evidence'" ;;
esac

if [ -n "$repo_root_override" ]; then
  cd -- "$repo_root_override"
else
  cd_workflow_repo_root
fi

emit_pass() {
  print_kv RESULT "pass"
  print_kv REASON "$1"
  [ -n "${2:-}" ] && print_kv MISCLASSIFIED_TYPE_CHECK "$2"
  exit 0
}

is_template="$(workflow_template_is_template)"
if [ "$is_template" != "true" ]; then
  emit_pass "consumer_mode"
fi

# Resolve Type: use the caller-supplied value when given, else read it.
type_readable=1
if [ "$type_set" -eq 0 ]; then
  if ! type_value="$(get_tracker_type_for_issue "$issue" 2>/dev/null)"; then
    type_readable=0
  fi
fi

if [ "$type_readable" -eq 0 ]; then
  # Parse failure. The single-item caller never reaches this gate in that
  # state (run-epic-scope-resolver.sh already error_exits during scope
  # resolution), but handled uniformly and safely here regardless of caller.
  emit_pass "type_unreadable" "deferred"
fi

if [ -z "$type_value" ]; then
  emit_pass "type_absent"
fi

if [ "$type_value" != "Workflow" ]; then
  emit_pass "type_routes_today"
fi

status_order="$(workflow_status_order "$status_value")"
case "$status_order" in
  0) ;; # Backlog — continue evaluating below
  -1) emit_pass "status_unreconciled" ;;
  *) emit_pass "pipeline_already_chosen" ;;
esac

if [ -n "$artifact_stage" ]; then
  emit_pass "stale_backlog_reconciled"
fi

case "$branch_pr_evidence" in
  present) emit_pass "branch_or_pr_in_flight" ;;
  unavailable) emit_pass "branch_evidence_unavailable" "deferred" ;;
esac

# branch_pr_evidence == none, artifact_stage empty, status Backlog, Type
# Workflow, framework mode: the item genuinely has not been started.
reason_text="Issue #${issue} is Type Workflow at Backlog with no development-folder artifacts and no implementation branch/PR — framework-mode repositories do not route Workflow-typed items to a pipeline. Re-classify the item as Feature, Bug, or Refactor to unblock it."

if [ "$caller" = "single" ]; then
  print_kv RESULT "stop"
  print_kv STOP_CONDITION "missing_tracker_context"
  print_kv ITEM "#${issue}"
  print_kv REASON "misclassified_type"
  print_kv REASON_TEXT "$reason_text"
else
  print_kv RESULT "hold"
  print_kv ITEM "#${issue}"
  print_kv REASON "misclassified_type"
  print_kv REASON_TEXT "$reason_text"
fi
exit 0
