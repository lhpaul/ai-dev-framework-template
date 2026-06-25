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
    printf '%s\n' '{"section":"absent","mode":"manual","backlog_start":false}'
    return 0
  fi

  _py_exit=0
  py_result="$(python3 - "$config_file" <<'PYEOF'
import sys, json
try:
    import yaml
    with open(sys.argv[1], 'r') as f:
        cfg = yaml.safe_load(f) or {}
    guardrails = cfg.get('guardrails') if isinstance(cfg, dict) else None
    if not isinstance(guardrails, dict):
        print(json.dumps({"section": "absent", "mode": "manual", "backlog_start": False}))
        sys.exit(0)
    mode = guardrails.get('mode', 'manual')
    if mode not in ('manual', 'assisted', 'delegated', 'autonomous'):
        mode = 'manual'
    backlog_start_cfg = guardrails.get('backlog_start', {})
    if isinstance(backlog_start_cfg, dict):
        allow = backlog_start_cfg.get('allow_without_confirmation', False)
    else:
        allow = False
    if not isinstance(allow, bool):
        allow = str(allow).lower() == 'true'
    print(json.dumps({"section": "present", "mode": mode, "backlog_start": allow}))
except Exception as exc:
    print(f"failed to parse guardrails from {sys.argv[1]}: {exc}", file=sys.stderr)
    sys.exit(2)
PYEOF
  )" || _py_exit=$?

  if [ "$_py_exit" -eq 2 ]; then
    error_exit "failed to read guardrails from workflow config $config_file"
  fi
  if [ "$_py_exit" -ne 0 ]; then
    py_result='{"section":"absent","mode":"manual","backlog_start":false}'
  fi

  printf '%s\n' "$py_result"
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

resolver_common=()
[ -n "$base_override" ] && resolver_common+=(--base "$base_override")
[ "$delegate_review_override" = "true" ] && resolver_common+=(--delegate-review)
[ "$may_merge_override" = "true" ] && resolver_common+=(--may-merge)
[ -n "$may_start_backlog_override" ] && resolver_common+=(--may-start-backlog "$may_start_backlog_override")
[ -n "$max_risk_override" ] && resolver_common+=(--max-risk "$max_risk_override")

case "$scope_mode" in
  epic)
  if ! "$SCRIPT_DIR/run-epic-scope-resolver.sh" --epic "$epic_number" "${resolver_common[@]}" --json > "$scope_file"; then
    error_exit "epic scope resolution failed"
  fi
    ;;
  items)
  if ! "$SCRIPT_DIR/run-epic-scope-resolver.sh" --items "$items_arg" "${resolver_common[@]}" --json > "$scope_file"; then
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
    if ! "$SCRIPT_DIR/run-item-scope-resolver.sh" "${item_args[@]}" "${resolver_common[@]}" --json > "$scope_file"; then
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

if ! "$SCRIPT_DIR/run-epic-policy-recommender.sh" "${policy_args[@]}" > "$policy_file"; then
  error_exit "policy recommendation failed"
fi

guardrails_json="$(read_guardrails_json)"

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
printf 'Requires confirmation: %s\n' "$(jq -r '.policyRecommendation.requiresConfirmation' <<<"$prelude_json")"
printf 'Reason: %s\n' "$(jq -r '.policyRecommendation.confirmationReason' <<<"$prelude_json")"
printf 'Copy-paste: %s\n' "$(jq -r '.policyRecommendation.copyPasteCommand' <<<"$prelude_json")"
printf 'Read-only: %s\n' "$(jq -r '.readOnlyGuarantee' <<<"$prelude_json")"
