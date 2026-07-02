#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=scripts/development-workflow/workflow-lib.sh
source "$SCRIPT_DIR/workflow-lib.sh"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/development-workflow/run-bounded-prelude.sh --original-command "<text>" [--json] \
    (--epic <issue> | --items <list> | --target <token> | --issue <n> | --branch <name> | --pr <n> | --development <path>) \
    [--base <branch>] [--delegate-review|--no-delegate-review] [--may-merge|--no-may-merge] \
    [--may-start-backlog <true|false>] [--max-risk <low|medium|high>] [--checkpoints-file <json-array>]

Read-only shared bounded prelude for /run-item and /run-epic: scope resolution,
repository guardrails snapshot, and policy/checkpoint recommendation. No tracker,
branch, PR, merge, or cleanup mutation.
EOF
}

original_command=""
json_output=0
scope_epic_set=0
scope_items_set=0
item_selector_count=0
epic_number=""
items_arg=""
item_target=""
item_issue=""
item_branch=""
item_pr=""
item_development=""
base_override=""
delegate_review_override=""
may_merge_override=""
may_start_backlog_override=""
max_risk_override=""
checkpoints_file=""

error_exit() {
  echo "ERROR: $*" >&2
  exit 1
}

emit_guardrails_unreadable_stop() {
  local detail="${1:-}"
  local affected="${original_command:-unknown scope}"
  local human_action="fix the guardrails block in .ai-dev-workflow.yaml, then rerun the bounded command"
  if [ "$json_output" -eq 1 ]; then
    jq -nc --arg detail "$detail" --arg affected "$affected" --arg humanAction "$human_action" \
      '{stopCondition: "guardrails_config_unreadable", affectedWorkItem: $affected, humanActionRequired: $humanAction, readOnlyGuarantee: "No tracker updates, branch creation, PR edits, labels, comments, merges, issue closure, or branch deletion were performed.", detail: $detail}'
    exit 1
  fi
  printf "STOP: guardrail 'guardrails_config_unreadable' halted this run\n"
  printf 'Affected work item: %s\n' "$affected"
  printf 'Human action required: %s\n' "$human_action"
  if [ -n "$detail" ]; then
    printf '%s\n' "$detail" >&2
  fi
  exit 1
}

require_value() {
  local option="$1"
  if [ "$#" -lt 2 ] || [ -z "${2:-}" ] || [ "${2#--}" != "$2" ]; then
    echo "$option requires a value." >&2
    usage >&2
    exit 64
  fi
}

read_guardrails_json() {
  local config_file py_result _py_exit
  if ! config_file="$(workflow_effective_config_file 2>/dev/null)"; then
    printf '%s\n' '{"section":"absent","mode":"manual","backlog_start":false,"stages":{"spec":{"may_open_pr":true,"may_merge_pr":false,"max_merge_risk":"low","required_evidence":[]},"plan":{"may_open_pr":true,"may_merge_pr":false,"max_merge_risk":"low","required_evidence":[]},"implementation":{"may_open_pr":true,"may_merge_pr":false,"max_merge_risk":"low","required_evidence":[]}},"stop_conditions":[],"audit":{"pr_disposition_record":"not_required","work_item_ledger_record":"not_required"}}'
    return 0
  fi

  _py_exit=0
  py_result="$(python3 - "$config_file" "$SCRIPT_DIR/workflow-config-resolver.py" <<'PYEOF'
import importlib.util
import json
from pathlib import Path
import sys


DEFAULT_STAGE = {
    "may_open_pr": True,
    "may_merge_pr": False,
    "max_merge_risk": "low",
    "required_evidence": [],
}
DEFAULT_STAGES = {
    "spec": dict(DEFAULT_STAGE),
    "plan": dict(DEFAULT_STAGE),
    "implementation": dict(DEFAULT_STAGE),
}
DEFAULT_AUDIT = {
    "pr_disposition_record": "not_required",
    "work_item_ledger_record": "not_required",
}


def as_bool(value):
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        return value.strip().lower() == "true"
    return bool(value)


def default_guardrails(section="absent"):
    return {
        "section": section,
        "mode": "manual",
        "backlog_start": False,
        "stages": DEFAULT_STAGES,
        "stop_conditions": [],
        "audit": DEFAULT_AUDIT,
    }


try:
    sys.dont_write_bytecode = True
    resolver_path = Path(sys.argv[2])
    spec = importlib.util.spec_from_file_location("workflow_config_resolver", resolver_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"could not load {resolver_path}")
    resolver = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(resolver)
    cfg = resolver.parse_yaml_subset(Path(sys.argv[1]))
    guardrails = cfg.get('guardrails') if isinstance(cfg, dict) else None
    if not isinstance(guardrails, dict):
        print(json.dumps(default_guardrails()))
        sys.exit(0)
    mode = guardrails.get('mode', 'manual')
    if mode not in ('manual', 'assisted', 'delegated', 'autonomous'):
        raise ValueError(f"guardrails.mode must be manual, assisted, delegated, or autonomous, got {mode!r}")
    backlog_start_cfg = guardrails.get('backlog_start', {})
    if isinstance(backlog_start_cfg, dict):
        allow = backlog_start_cfg.get('allow_without_confirmation', False)
    else:
        allow = False
    stages_cfg = guardrails.get("stages", {})
    stages = {}
    for stage in ("spec", "plan", "implementation"):
        cfg_stage = stages_cfg.get(stage, {}) if isinstance(stages_cfg, dict) else {}
        stage_out = dict(DEFAULT_STAGE)
        if isinstance(cfg_stage, dict):
            if "may_open_pr" in cfg_stage:
                stage_out["may_open_pr"] = as_bool(cfg_stage["may_open_pr"])
            if "may_merge_pr" in cfg_stage:
                stage_out["may_merge_pr"] = as_bool(cfg_stage["may_merge_pr"])
            if "max_merge_risk" in cfg_stage:
                risk = cfg_stage["max_merge_risk"]
                if risk not in ("low", "medium", "high"):
                    raise ValueError(
                        f"guardrails.stages.{stage}.max_merge_risk must be low, medium, or high, got {risk!r}"
                    )
                stage_out["max_merge_risk"] = risk
            evidence = cfg_stage.get("required_evidence", [])
            stage_out["required_evidence"] = evidence if isinstance(evidence, list) else []
        stages[stage] = stage_out
    stops = guardrails.get("stop_conditions", [])
    audit_cfg = guardrails.get("audit", {})
    audit = dict(DEFAULT_AUDIT)
    if isinstance(audit_cfg, dict):
        audit["pr_disposition_record"] = audit_cfg.get("pr_disposition_record", "not_required")
        audit["work_item_ledger_record"] = audit_cfg.get("work_item_ledger_record", "not_required")
    print(json.dumps({
        "section": "present",
        "mode": mode,
        "backlog_start": as_bool(allow),
        "stages": stages,
        "stop_conditions": stops if isinstance(stops, list) else [],
        "audit": audit,
    }))
except Exception as exc:
    print(f"failed to parse guardrails from {sys.argv[1]}: {exc}", file=sys.stderr)
    sys.exit(2)
PYEOF
  )" || _py_exit=$?

  if [ "$_py_exit" -eq 2 ]; then
    emit_guardrails_unreadable_stop "failed to read guardrails from workflow config $config_file"
  fi
  if [ "$_py_exit" -ne 0 ]; then
    py_result='{"section":"absent","mode":"manual","backlog_start":false,"stages":{"spec":{"may_open_pr":true,"may_merge_pr":false,"max_merge_risk":"low","required_evidence":[]},"plan":{"may_open_pr":true,"may_merge_pr":false,"max_merge_risk":"low","required_evidence":[]},"implementation":{"may_open_pr":true,"may_merge_pr":false,"max_merge_risk":"low","required_evidence":[]}},"stop_conditions":[],"audit":{"pr_disposition_record":"not_required","work_item_ledger_record":"not_required"}}'
  fi

  printf '%s\n' "$py_result"
}

json_get() {
  local json="$1" filter="$2"
  printf '%s\n' "$json" | jq -r "$filter"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --original-command)
      require_value "$@"
      original_command="$2"
      shift 2
      ;;
    --epic)
      require_value "$@"
      epic_number="$2"
      scope_epic_set=1
      shift 2
      ;;
    --items)
      require_value "$@"
      items_arg="$2"
      scope_items_set=1
      shift 2
      ;;
    --target)
      require_value "$@"
      item_target="$2"
      item_selector_count=$((item_selector_count + 1))
      shift 2
      ;;
    --issue)
      require_value "$@"
      item_issue="$2"
      item_selector_count=$((item_selector_count + 1))
      shift 2
      ;;
    --branch)
      require_value "$@"
      item_branch="$2"
      item_selector_count=$((item_selector_count + 1))
      shift 2
      ;;
    --pr)
      require_value "$@"
      item_pr="$2"
      item_selector_count=$((item_selector_count + 1))
      shift 2
      ;;
    --development)
      require_value "$@"
      item_development="$2"
      item_selector_count=$((item_selector_count + 1))
      shift 2
      ;;
    --base)
      require_value "$@"
      base_override="$2"
      shift 2
      ;;
    --delegate-review)
      delegate_review_override="true"
      shift
      ;;
    --delegate-review=*)
      delegate_review_override="${1#*=}"
      shift
      ;;
    --no-delegate-review)
      delegate_review_override="false"
      shift
      ;;
    --may-merge)
      may_merge_override="true"
      shift
      ;;
    --may-merge=*)
      may_merge_override="${1#*=}"
      shift
      ;;
    --no-may-merge)
      may_merge_override="false"
      shift
      ;;
    --may-start-backlog)
      require_value "$@"
      may_start_backlog_override="$2"
      shift 2
      ;;
    --max-risk)
      require_value "$@"
      max_risk_override="$2"
      shift 2
      ;;
    --checkpoints-file)
      require_value "$@"
      checkpoints_file="$2"
      shift 2
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
      echo "Unknown option: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

[ -n "$original_command" ] || error_exit "--original-command is required"

if [ "$scope_epic_set" -eq 1 ] && [ "$scope_items_set" -eq 1 ]; then
  error_exit "pass exactly one of --epic or --items, not both"
fi
if [ "$scope_epic_set" -eq 1 ] && [ "$item_selector_count" -gt 0 ]; then
  error_exit "pass exactly one scope selector group (--epic, --items, or one item target flag), not --epic with item flags"
fi
if [ "$scope_items_set" -eq 1 ] && [ "$item_selector_count" -gt 0 ]; then
  error_exit "pass exactly one scope selector group (--epic, --items, or one item target flag), not --items with item flags"
fi

scope_group_count=0
[ "$scope_epic_set" -eq 1 ] && scope_group_count=$((scope_group_count + 1))
[ "$scope_items_set" -eq 1 ] && scope_group_count=$((scope_group_count + 1))
[ "$item_selector_count" -gt 0 ] && scope_group_count=$((scope_group_count + 1))

if [ "$scope_group_count" -ne 1 ]; then
  error_exit "pass exactly one scope selector group (--epic, --items, or one item target flag)"
fi
if [ "$item_selector_count" -gt 1 ]; then
  error_exit "pass exactly one item target flag (--target, --issue, --branch, --pr, or --development)"
fi

if [ -z "${AI_DEV_WORKFLOW_CONFIG_FILE:-}" ]; then
  _resolved_config="$(workflow_effective_config_file 2>/dev/null)" || _resolved_config=""
  if [ -n "$_resolved_config" ]; then
    export AI_DEV_WORKFLOW_CONFIG_FILE="$_resolved_config"
  fi
fi

scope_mode=""
if [ "$scope_epic_set" -eq 1 ]; then
  scope_mode="epic"
elif [ "$scope_items_set" -eq 1 ]; then
  scope_mode="items"
else
  scope_mode="item"
fi

tmp_dir="$(mktemp -d)"
scope_file="$tmp_dir/scope.json"
policy_file="$tmp_dir/policy.json"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

guardrails_json="$(read_guardrails_json)"
if [ -z "$may_start_backlog_override" ]; then
  may_start_backlog_override="$(json_get "$guardrails_json" '.backlog_start | tostring')"
fi
if [ -z "$delegate_review_override" ]; then
  case "$(json_get "$guardrails_json" '.mode')" in
    assisted|delegated|autonomous) delegate_review_override="true" ;;
    *) delegate_review_override="false" ;;
  esac
fi
if [ -z "$may_merge_override" ]; then
  if [ "$(json_get "$guardrails_json" '[.stages.spec.may_merge_pr, .stages.plan.may_merge_pr, .stages.implementation.may_merge_pr] | any')" = "true" ]; then
    may_merge_override="true"
  else
    may_merge_override="false"
  fi
fi
if [ -z "$max_risk_override" ]; then
  max_risk_override="$(json_get "$guardrails_json" '
    def rank: {"low":1,"medium":2,"high":3}[.] // 0;
    [.stages.spec.max_merge_risk, .stages.plan.max_merge_risk, .stages.implementation.max_merge_risk]
    | max_by(rank)
  ')"
fi

resolver_common=()
[ -n "$base_override" ] && resolver_common+=(--base "$base_override")
[ "$delegate_review_override" = "true" ] && resolver_common+=(--delegate-review)
[ "$may_merge_override" = "true" ] && resolver_common+=(--may-merge)
[ -n "$may_start_backlog_override" ] && resolver_common+=(--may-start-backlog "$may_start_backlog_override")
[ -n "$max_risk_override" ] && resolver_common+=(--max-risk "$max_risk_override")

case "$scope_mode" in
  epic)
  if ! "$SCRIPT_DIR/run-epic-scope-resolver.sh" --epic "$epic_number" "${resolver_common[@]+"${resolver_common[@]}"}" --json > "$scope_file"; then
    error_exit "epic scope resolution failed"
  fi
    ;;
  items)
  if ! "$SCRIPT_DIR/run-epic-scope-resolver.sh" --items "$items_arg" "${resolver_common[@]+"${resolver_common[@]}"}" --json > "$scope_file"; then
    error_exit "items scope resolution failed"
  fi
    ;;
  item)
    item_args=()
    [ -n "$item_target" ] && item_args+=(--target "$item_target")
    [ -n "$item_issue" ] && item_args+=(--issue "$item_issue")
    [ -n "$item_branch" ] && item_args+=(--branch "$item_branch")
    [ -n "$item_pr" ] && item_args+=(--pr "$item_pr")
    [ -n "$item_development" ] && item_args+=(--development "$item_development")
    if ! "$SCRIPT_DIR/run-item-scope-resolver.sh" "${item_args[@]+"${item_args[@]}"}" "${resolver_common[@]+"${resolver_common[@]}"}" --json > "$scope_file"; then
      error_exit "item scope resolution failed"
    fi
    ;;
esac

policy_args=(
  --scope "$scope_file"
  --original-command "$original_command"
)
[ -n "$base_override" ] && policy_args+=(--base "$base_override")
[ -n "$delegate_review_override" ] && policy_args+=(--delegate-review="$delegate_review_override")
[ -n "$may_merge_override" ] && policy_args+=(--may-merge="$may_merge_override")
[ -n "$may_start_backlog_override" ] && policy_args+=(--may-start-backlog "$may_start_backlog_override")
[ -n "$max_risk_override" ] && policy_args+=(--max-risk "$max_risk_override")
[ -n "$checkpoints_file" ] && policy_args+=(--checkpoints-file "$checkpoints_file")
policy_args+=(--json)

if ! "$SCRIPT_DIR/run-epic-policy-recommender.sh" "${policy_args[@]+"${policy_args[@]}"}" > "$policy_file"; then
  error_exit "policy recommendation failed"
fi

prelude_json="$(jq -nc \
  --slurpfile scope "$scope_file" \
  --slurpfile policy "$policy_file" \
  --argjson guardrails "$guardrails_json" \
  '{
    preludeVersion: 1,
    scope: $scope[0],
    guardrails: $guardrails,
    policyRecommendation: $policy[0],
    readOnlyGuarantee: "No tracker updates, branch creation, PR edits, labels, comments, merges, issue closure, or branch deletion were performed."
  }')"

if [ "$json_output" -eq 1 ]; then
  printf '%s\n' "$prelude_json"
  exit 0
fi

printf 'Bounded Run Prelude\n'
printf 'Scope source: %s\n' "$(jq -r '.scope.scopeSource' <<<"$prelude_json")"
printf 'Guardrails: section=%s mode=%s backlog_start=%s\n' \
  "$(jq -r '.guardrails.section' <<<"$prelude_json")" \
  "$(jq -r '.guardrails.mode' <<<"$prelude_json")" \
  "$(jq -r '.guardrails.backlog_start' <<<"$prelude_json")"
if [ "$(jq -r '.guardrails.section' <<<"$prelude_json")" = "absent" ]; then
  printf 'no `guardrails` section found; conservative defaults are in effect\n'
  printf 'Default guardrails: mode=manual; stages.*.may_open_pr=true; stages.*.may_merge_pr=false; stages.*.max_merge_risk=low; backlog_start.allow_without_confirmation=false; audit records not required\n'
fi
printf 'Requires confirmation: %s\n' "$(jq -r '.policyRecommendation.requiresConfirmation' <<<"$prelude_json")"
printf 'Reason: %s\n' "$(jq -r '.policyRecommendation.confirmationReason' <<<"$prelude_json")"
printf 'Copy-paste: %s\n' "$(jq -r '.policyRecommendation.copyPasteCommand' <<<"$prelude_json")"
printf 'Read-only: %s\n' "$(jq -r '.readOnlyGuarantee' <<<"$prelude_json")"
