#!/usr/bin/env bash
# tracker-status-for.sh — resolve (and optionally apply) the canonical tracker
# Status for a workflow event (issue #1564).
#
# The mapping itself lives in workflow-lib.sh (workflow_tracker_status_for_event)
# and is documented in docs/workflow/development-workflow/tracker-status-mapping.md.
# Runners call this instead of choosing a Status string themselves, so two
# runners given the same instruction set the same tracker state.

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  tracker-status-for.sh --event <event> (--branch <branch> | --stage <stage>) [--apply --issue <issue-id>]
  tracker-status-for.sh --list

Events (Status-changing): dispatch, ready-for-human-review, merged, released
Events (no Status change): needs-fixes, ready-for-regression, needs-setup,
                           human-checkpoint-required
Stages: spec, plan, implementation (derived from --branch when given:
        spec/*, implementation-plan/*, feature|fix|refactor|hotfix/*)

Output (key=value lines):
  TRACKER_EVENT, TRACKER_STAGE, TRACKER_STATUS (empty when no change),
  TRACKER_STATUS_ACTION=set|none, and with --apply
  TRACKER_STATUS_RESULT=applied|skipped|deferred|unresolved|failed|none

--apply runs update_tracker_status_best_effort with
WORKFLOW_TRACKER_STATUS_STRICT=true: a Status the board does not offer, or a
board with no Status field, is a failure (exit 3) instead of a silent no-op;
the output names the board's valid options.

Exit codes:
  0  resolved (and, with --apply: applied, skipped, deferred, none, or a
     best-effort 'failed' for a transient API error)
  2  usage error, unknown event/stage, or a branch that owns no item stage
  3  --apply: the board has no Status field, or its Status field has no
     option for the canonical Status
USAGE
}

fail_usage() {
  printf 'ERROR: %s\n' "$1" >&2
  usage >&2
  exit 2
}

event=""; branch=""; stage=""; issue=""; apply="false"; list="false"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --event) [ "$#" -ge 2 ] && [ -n "$2" ] || fail_usage "missing value for --event"; event="$2"; shift 2 ;;
    --branch) [ "$#" -ge 2 ] && [ -n "$2" ] || fail_usage "missing value for --branch"; branch="$2"; shift 2 ;;
    --stage) [ "$#" -ge 2 ] && [ -n "$2" ] || fail_usage "missing value for --stage"; stage="$2"; shift 2 ;;
    --issue) [ "$#" -ge 2 ] && [ -n "$2" ] || fail_usage "missing value for --issue"; issue="$2"; shift 2 ;;
    --apply) apply="true"; shift ;;
    --list) list="true"; shift ;;
    --help|-h) usage; exit 0 ;;
    *) fail_usage "unknown argument: $1" ;;
  esac
done

script_dir="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=scripts/development-workflow/workflow-lib.sh
source "$script_dir/workflow-lib.sh"

if [ "$list" = "true" ]; then
  if [ -n "$event" ] || [ -n "$branch" ] || [ -n "$stage" ] || [ "$apply" = "true" ]; then
    fail_usage "--list takes no other options"
  fi
  workflow_canonical_tracker_statuses
  exit 0
fi

[ -n "$event" ] || fail_usage "--event is required"
if [ -n "$branch" ] && [ -n "$stage" ]; then
  fail_usage "pass either --branch or --stage, not both"
fi
if [ -n "$branch" ]; then
  if ! stage="$(workflow_tracker_stage_for_branch "$branch")"; then
    printf 'ERROR: branch %s does not own an item stage; expected spec/*, implementation-plan/*, feature/*, fix/*, refactor/*, or hotfix/*.\n' "$branch" >&2
    exit 2
  fi
fi
[ -n "$stage" ] || fail_usage "--branch or --stage is required"
if [ "$apply" = "true" ]; then
  case "$issue" in
    ''|*[[:space:]]*) fail_usage "--apply requires --issue <issue-id>" ;;
  esac
elif [ -n "$issue" ]; then
  fail_usage "--issue is only valid with --apply"
fi

set +e
status="$(workflow_tracker_status_for_event "$event" "$stage")"
map_rc=$?
set -e
if [ "$map_rc" -ne 0 ]; then
  exit 2
fi

printf 'TRACKER_EVENT=%s\n' "$event"
printf 'TRACKER_STAGE=%s\n' "$stage"
printf 'TRACKER_STATUS=%s\n' "$status"
if [ -z "$status" ]; then
  printf 'TRACKER_STATUS_ACTION=none\n'
  if [ "$apply" = "true" ]; then
    printf 'TRACKER_STATUS_RESULT=none\n'
  fi
  exit 0
fi
printf 'TRACKER_STATUS_ACTION=set\n'

if [ "$apply" != "true" ]; then
  exit 0
fi

set +e
apply_output="$(WORKFLOW_TRACKER_STATUS_STRICT=true update_tracker_status_best_effort "$issue" "$status" 2>&1)"
apply_rc=$?
set -e
if [ -n "$apply_output" ]; then
  printf '%s\n' "$apply_output"
fi

# Classify on the helper's machine-readable markers only (see the
# update_tracker_status_best_effort header in workflow-lib.sh), never on its
# human-readable warnings.
case "$apply_output" in
  *"TRACKER_STATUS_UNRESOLVED "*"reason=unknown_status_option"*|*"TRACKER_STATUS_UNRESOLVED "*"reason=status_field_missing"*)
    printf 'TRACKER_STATUS_RESULT=unresolved\n'
    exit 3
    ;;
  *"TRACKER_STATUS_UNRESOLVED "*"reason=status_field_unavailable"*|*"TRACKER_STATUS_UPDATE_FAILED "*)
    printf 'TRACKER_STATUS_RESULT=failed\n'
    ;;
  *"TRACKER_STATUS_APPLIED issue=${issue} "*)
    printf 'TRACKER_STATUS_RESULT=applied\n'
    ;;
  *"TRACKER_ACTION_REQUIRED="*)
    printf 'TRACKER_STATUS_RESULT=deferred\n'
    ;;
  *)
    if [ "$apply_rc" -ne 0 ]; then
      # A non-zero return with no recognised marker is not a vocabulary
      # mismatch; report it as a best-effort failure, never as exit 3.
      printf 'TRACKER_STATUS_RESULT=failed\n'
    else
      printf 'TRACKER_STATUS_RESULT=skipped\n'
    fi
    ;;
esac
