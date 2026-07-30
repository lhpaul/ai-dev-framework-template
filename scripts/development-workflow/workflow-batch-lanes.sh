#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=scripts/development-workflow/workflow-lib.sh
source "$SCRIPT_DIR/workflow-lib.sh"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/development-workflow/workflow-batch-lanes.sh [--repo-root <path>] [--overlap-input <json-file>] [--scan [development-path ...]]
  ./scripts/development-workflow/workflow-batch-lanes.sh [--repo-root <path>] [--overlap-input <json-file>] < batch-plan-output

Assigns stage lanes and dispatch vs held status for portfolio batch proposals.
Reads workflow-batch-plan.sh key=value blocks from stdin, or runs --scan to
generate them. Emits augmented item blocks plus lane-cap metadata for Protocol 90.

Stage lanes: spec, plan, review, implementation.
Default max concurrent: unlimited for spec/plan/review; implementation defaults to 1.
Optional guardrails.parallelism.max_concurrent_by_stage in .ai-dev-workflow.yaml.
EOF
}

stage_lane_for_next_action() {
  case "$1" in
    skip|unknown|resolve-repository-selection) printf 'none\n' ;;
    write-spec|run-spec-review-and-open-pr) printf 'spec\n' ;;
    write-plan|run-plan-review-and-open-pr) printf 'plan\n' ;;
    run-code-review-and-open-pr|resolve-pr-readiness|resume-fix-loop|wait-human-review) printf 'review\n' ;;
    implement|resolve-development-pr) printf 'implementation\n' ;;
    *) printf 'review\n' ;;
  esac
}

lowercase() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

report_label_for_category() {
  case "$1" in
    informational) printf 'INFORMATIONAL - not actionable in this proposal\n' ;;
    actionable_resume) printf 'ACTIONABLE RESUME - can advance now\n' ;;
    proposed_batch) printf 'PROPOSED BATCH - your decision\n' ;;
    held) printf 'HELD - not included in proposed batch\n' ;;
    *) printf 'INFORMATIONAL - not actionable in this proposal\n' ;;
  esac
}

report_category_for_item() {
  local dispatch="$1"
  local status="$2"
  local next_action="$3"
  local labels="$4"
  local pr_metadata_status="${5:-}"

  status="$(lowercase "$status")"
  next_action="$(lowercase "$next_action")"
  labels="$(lowercase "$labels")"
  pr_metadata_status="$(lowercase "$pr_metadata_status")"

  if [ "$dispatch" = "skip" ]; then
    printf 'informational\n'
    return 0
  fi

  case "$next_action" in
    wait-human-review)
      printf 'informational\n'
      return 0
      ;;
  esac

  case "$status" in
    "spec in review"|"plan in review"|"development in review")
      printf 'informational\n'
      return 0
      ;;
  esac

  if [ "$labels" != "${labels/ready-for-human-review/}" ]; then
    printf 'informational\n'
    return 0
  fi

  if [ "$next_action" = "resolve-development-pr" ] && [ "$pr_metadata_status" = "unavailable" ]; then
    printf 'informational\n'
    return 0
  fi

  if [ "$dispatch" = "held" ]; then
    printf 'held\n'
    return 0
  fi

  if [ "$status" = "backlog" ] || [ "$next_action" = "write-spec" ]; then
    printf 'proposed_batch\n'
    return 0
  fi

  printf 'actionable_resume\n'
}

report_reason_for_item() {
  local category="$1"
  local dispatch="$2"
  local status="$3"
  local next_action="$4"
  local hold_reason="$5"
  local skip_reason="$6"
  local labels="$7"
  local pr_metadata_status="${8:-}"
  local pr_metadata_reason="${9:-}"

  local status_lc next_action_lc labels_lc
  status_lc="$(lowercase "$status")"
  next_action_lc="$(lowercase "$next_action")"
  labels_lc="$(lowercase "$labels")"
  pr_metadata_status="$(lowercase "$pr_metadata_status")"

  case "$category" in
    held)
      if [ -n "$hold_reason" ]; then
        printf '%s\n' "$hold_reason"
      else
        printf 'Candidate evaluated but not included in the proposed batch.\n'
      fi
      ;;
    proposed_batch)
      if [ "$status_lc" = "backlog" ]; then
        printf 'Backlog start candidate included in the current proposal.\n'
      else
        printf 'Backlog start candidate included in the current proposal via %s.\n' "$next_action"
      fi
      ;;
    actionable_resume)
      printf 'Current-session resume work can advance via %s.\n' "$next_action"
      ;;
    *)
      if [ "$next_action_lc" = "wait-human-review" ] \
        || [ "$status_lc" = "spec in review" ] \
        || [ "$status_lc" = "plan in review" ] \
        || [ "$status_lc" = "development in review" ] \
        || [ "$labels_lc" != "${labels_lc/ready-for-human-review/}" ]; then
        printf 'Waiting on human review or merge outside the current run-work proposal.\n'
      elif [ "$next_action_lc" = "resolve-development-pr" ] && [ "$pr_metadata_status" = "unavailable" ]; then
        if [ -n "$pr_metadata_reason" ]; then
          printf 'Open PR metadata unavailable (%s); not actionable in this proposal.\n' "$pr_metadata_reason"
        else
          printf 'Open PR metadata unavailable; not actionable in this proposal.\n'
        fi
      elif [ -n "$skip_reason" ]; then
        printf '%s\n' "$skip_reason"
      elif [ -n "$hold_reason" ]; then
        printf '%s\n' "$hold_reason"
      elif [ -n "$next_action" ]; then
        printf 'Not dispatch-eligible in the current run-work proposal (%s).\n' "$next_action"
      else
        printf 'Not dispatch-eligible in the current run-work proposal.\n'
      fi
      ;;
  esac
}

append_alias() {
  local alias_file="$1"
  local value="$2"
  [ -n "$value" ] || return 0
  printf '%s\n' "$value" >> "$alias_file"
}

block_alias_file() {
  local block_file="$1"
  local alias_file="$2"
  local item_id="" development_path="" target="" slug_issue=""

  : > "$alias_file"
  while IFS='=' read -r key value; do
    case "$key" in
      SLUG) item_id="$value" ;;
      DEVELOPMENT_PATH) development_path="$value" ;;
      TARGET) target="$value" ;;
    esac
  done < "$block_file"

  append_alias "$alias_file" "$item_id"
  append_alias "$alias_file" "$development_path"
  append_alias "$alias_file" "$target"
  if [[ "$item_id" =~ ^([0-9]+)(-|$) ]]; then
    slug_issue="${BASH_REMATCH[1]}"
    append_alias "$alias_file" "$slug_issue"
  fi
  awk 'NF && !seen[$0]++' "$alias_file" > "$alias_file.tmp"
  mv "$alias_file.tmp" "$alias_file"
}

parallelism_config_file() {
  local repo_root="$1"
  if [ -n "${AI_DEV_WORKFLOW_CONFIG_FILE:-}" ] && [ -f "${AI_DEV_WORKFLOW_CONFIG_FILE}" ]; then
    printf '%s\n' "${AI_DEV_WORKFLOW_CONFIG_FILE}"
    return 0
  fi
  if [ -f "$repo_root/.ai-dev-workflow.yaml" ]; then
    printf '%s/.ai-dev-workflow.yaml\n' "$repo_root"
    return 0
  fi
  return 1
}

read_parallelism_caps() {
  local repo_root="$1"
  local config_file=""
  if ! config_file="$(parallelism_config_file "$repo_root")"; then
    printf '{"spec":0,"plan":0,"review":0,"implementation":1}\n'
    return 0
  fi

  python3 - "$config_file" <<'PYEOF' || printf '{"spec":0,"plan":0,"review":0,"implementation":1}\n'
import json, sys
from pathlib import Path

path = Path(sys.argv[1])
defaults = {"spec": 0, "plan": 0, "review": 0, "implementation": 1}
try:
    import yaml
except ImportError:
    print(json.dumps(defaults))
    sys.exit(0)

try:
    cfg = yaml.safe_load(path.read_text()) or {}
except Exception:
    print(json.dumps(defaults))
    sys.exit(0)

guardrails = cfg.get("guardrails") if isinstance(cfg, dict) else None
parallelism = guardrails.get("parallelism") if isinstance(guardrails, dict) else None
caps = parallelism.get("max_concurrent_by_stage") if isinstance(parallelism, dict) else None
if not isinstance(caps, dict):
    print(json.dumps(defaults))
    sys.exit(0)

out = dict(defaults)
for lane in defaults:
    val = caps.get(lane)
    if isinstance(val, int) and val >= 0:
        out[lane] = val
print(json.dumps(out))
PYEOF
}

repo_root=""
scan_mode=0
overlap_input=""
development_paths=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo-root)
      shift
      repo_root="${1:-}"
      shift
      ;;
    --scan)
      scan_mode=1
      shift
      ;;
    --overlap-input)
      shift
      overlap_input="${1:-}"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      development_paths+=("$1")
      shift
      ;;
  esac
done

if [ -z "$repo_root" ]; then
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

cd "$repo_root" || exit 1

caps_json="$(read_parallelism_caps "$repo_root")"
max_spec="$(printf '%s' "$caps_json" | jq -r '.spec')"
max_plan="$(printf '%s' "$caps_json" | jq -r '.plan')"
max_review="$(printf '%s' "$caps_json" | jq -r '.review')"
max_implementation="$(printf '%s' "$caps_json" | jq -r '.implementation')"

# Test / operator overrides (optional).
if [ -n "${WORKFLOW_MAX_CONCURRENT_SPEC:-}" ]; then max_spec="$WORKFLOW_MAX_CONCURRENT_SPEC"; fi
if [ -n "${WORKFLOW_MAX_CONCURRENT_PLAN:-}" ]; then max_plan="$WORKFLOW_MAX_CONCURRENT_PLAN"; fi
if [ -n "${WORKFLOW_MAX_CONCURRENT_REVIEW:-}" ]; then max_review="$WORKFLOW_MAX_CONCURRENT_REVIEW"; fi
if [ -n "${WORKFLOW_MAX_CONCURRENT_IMPLEMENTATION:-}" ]; then max_implementation="$WORKFLOW_MAX_CONCURRENT_IMPLEMENTATION"; fi

print_kv MAX_CONCURRENT_SPEC "$max_spec"
print_kv MAX_CONCURRENT_PLAN "$max_plan"
print_kv MAX_CONCURRENT_REVIEW "$max_review"
print_kv MAX_CONCURRENT_IMPLEMENTATION "$max_implementation"
echo

batch_input=""
if [ "$scan_mode" -eq 1 ]; then
  if [ "${#development_paths[@]}" -gt 0 ]; then
    batch_input="$("$SCRIPT_DIR/workflow-batch-plan.sh" --repo-root "$repo_root" "${development_paths[@]}")"
  else
    batch_input="$("$SCRIPT_DIR/workflow-batch-plan.sh" --repo-root "$repo_root")"
  fi
else
  batch_input="$(cat)"
fi

if [ -z "${batch_input//[[:space:]]/}" ]; then
  echo "(none)"
  exit 0
fi

TMP_BLOCKS="$(mktemp)"
TMP_META="$(mktemp)"
TMP_OVERLAP="$(mktemp)"
TMP_ALIASES="$(mktemp)"
trap 'rm -f "$TMP_BLOCKS" "$TMP_META" "$TMP_OVERLAP" "$TMP_ALIASES"' EXIT

# Parse item blocks (blank-line separated key=value groups).
block_idx=0
block_lines=()
while IFS= read -r line || [ -n "$line" ]; do
  if [ -z "${line//[[:space:]]/}" ]; then
    if [ "${#block_lines[@]}" -gt 0 ]; then
      printf '%s\n' "${block_lines[@]}" > "$TMP_BLOCKS.$block_idx"
      block_idx=$((block_idx + 1))
      block_lines=()
    fi
    continue
  fi
  block_lines+=("$line")
done <<< "$batch_input"
if [ "${#block_lines[@]}" -gt 0 ]; then
  printf '%s\n' "${block_lines[@]}" > "$TMP_BLOCKS.$block_idx"
  block_idx=$((block_idx + 1))
fi

lane_count_spec=0
lane_count_plan=0
lane_count_review=0
lane_count_implementation=0

idx=0
while [ "$idx" -lt "$block_idx" ]; do
  next_action=""
  local_runtime="none"
  slug=""
  development_path=""
  while IFS='=' read -r key value; do
    case "$key" in
      NEXT_ACTION) next_action="$value" ;;
      LOCAL_RUNTIME) local_runtime="$value" ;;
      SLUG) slug="$value" ;;
      DEVELOPMENT_PATH) development_path="$value" ;;
    esac
  done < "$TMP_BLOCKS.$idx"

  item_id="$slug"
  [ -z "$item_id" ] && item_id="$development_path"
  [ -z "$item_id" ] && item_id="unknown-item"

  stage_lane="$(stage_lane_for_next_action "$next_action")"
  dispatch="proposed"
  hold_reason=""

  if [ "$stage_lane" = "none" ]; then
    dispatch="skip"
    hold_reason="not dispatch-eligible (${next_action})"
  else
    case "$stage_lane" in
    spec)
      if [ "$max_spec" -gt 0 ] && [ "$lane_count_spec" -ge "$max_spec" ]; then
        dispatch="held"
        hold_reason="stage lane cap (max ${max_spec} for spec)"
      else
        lane_count_spec=$((lane_count_spec + 1))
      fi
      ;;
    plan)
      if [ "$max_plan" -gt 0 ] && [ "$lane_count_plan" -ge "$max_plan" ]; then
        dispatch="held"
        hold_reason="stage lane cap (max ${max_plan} for plan)"
      else
        lane_count_plan=$((lane_count_plan + 1))
      fi
      ;;
    review)
      if [ "$max_review" -gt 0 ] && [ "$lane_count_review" -ge "$max_review" ]; then
        dispatch="held"
        hold_reason="stage lane cap (max ${max_review} for review)"
      else
        lane_count_review=$((lane_count_review + 1))
      fi
      ;;
    implementation)
      if [ "$max_implementation" -gt 0 ] && [ "$lane_count_implementation" -ge "$max_implementation" ]; then
        dispatch="held"
        hold_reason="implementation lane cap (max ${max_implementation})"
      else
        lane_count_implementation=$((lane_count_implementation + 1))
      fi
      ;;
    esac
  fi

  hold_field="${hold_reason:--}"
  printf '%s\t%s\t%s\t%s\t%s\n' "$idx" "$stage_lane" "$dispatch" "$hold_field" "$local_runtime" >> "$TMP_META"
  idx=$((idx + 1))
done

# LOCAL_RUNTIME exclusivity: when any proposed implementation item is exclusive,
# only one implementation item may dispatch in this batch.
exclusive_in_batch=0
proposed_impl_count=0
while IFS=$'\t' read -r _ stage_lane dispatch hr local_runtime; do
  if [ "$stage_lane" = "implementation" ] && [ "$dispatch" = "proposed" ]; then
    proposed_impl_count=$((proposed_impl_count + 1))
    if [ "$local_runtime" = "exclusive" ]; then
      exclusive_in_batch=1
    fi
  fi
done < "$TMP_META"

if [ "$exclusive_in_batch" -eq 1 ] && [ "$proposed_impl_count" -gt 1 ]; then
  kept_impl=0
  : > "$TMP_META.new"
  while IFS=$'\t' read -r block_index stage_lane dispatch hr local_runtime; do
    hold_reason=""
    if [ "$hr" != "-" ]; then
      hold_reason="$hr"
    fi
    if [ "$stage_lane" = "implementation" ] && [ "$dispatch" = "proposed" ]; then
      if [ "$kept_impl" -eq 0 ]; then
        kept_impl=1
      else
        dispatch="held"
        hold_reason="local runtime exclusivity (another implementation item requires exclusive local runtime)"
      fi
    fi
    hold_field="${hold_reason:--}"
    printf '%s\t%s\t%s\t%s\t%s\n' "$block_index" "$stage_lane" "$dispatch" "$hold_field" "$local_runtime" >> "$TMP_META.new"
  done < "$TMP_META"
  mv "$TMP_META.new" "$TMP_META"
fi

# Planless/brief overlap dispositions: Protocol 90 may supply a provider-neutral
# item snapshot for workflow-batch-overlap.sh. Serial groups hold every member
# except the group's selected keep item before dispatch.
if [ -n "$overlap_input" ]; then
  if [ ! -f "$overlap_input" ]; then
    echo "ERROR: overlap input file not found: $overlap_input" >&2
    exit 1
  fi
  "$SCRIPT_DIR/workflow-batch-overlap.sh" --input "$overlap_input" --json > "$TMP_OVERLAP"
  : > "$TMP_META.new"
  while IFS=$'\t' read -r block_index stage_lane dispatch hr local_runtime; do
    hold_reason=""
    if [ "$hr" != "-" ]; then
      hold_reason="$hr"
    fi

    block_alias_file "$TMP_BLOCKS.$block_index" "$TMP_ALIASES"
    overlap_group=""
    while IFS= read -r alias_id; do
      [ -n "$alias_id" ] || continue
      overlap_group="$(jq -r --arg id "$alias_id" '.serialGroups[]? | select((.heldItemIds // []) | index($id)) | .groupId' "$TMP_OVERLAP" | head -1)"
      [ -n "$overlap_group" ] && break
    done < "$TMP_ALIASES"
    if [ -n "$overlap_group" ] && [ "$stage_lane" = "implementation" ] && [ "$dispatch" = "proposed" ]; then
      dispatch="held"
      hold_reason="planless overlap serialization (${overlap_group}); held until prior item merges into approved base"
    fi

    hold_field="${hold_reason:--}"
    printf '%s\t%s\t%s\t%s\t%s\n' "$block_index" "$stage_lane" "$dispatch" "$hold_field" "$local_runtime" >> "$TMP_META.new"
  done < "$TMP_META"
  mv "$TMP_META.new" "$TMP_META"
fi

idx=0
while [ "$idx" -lt "$block_idx" ]; do
  stage_lane=""
  dispatch=""
  hold_reason=""
  while IFS=$'\t' read -r block_index s d hr _; do
    if [ "$block_index" = "$idx" ]; then
      stage_lane="$s"
      dispatch="$d"
      if [ "$hr" = "-" ]; then
        hold_reason=""
      else
        hold_reason="$hr"
      fi
    fi
  done < "$TMP_META"

  item_id=""
  status=""
  next_action=""
  labels=""
  skip_reason=""
  pr_metadata_status=""
  pr_metadata_reason=""
  overlap_group=""
  while IFS='=' read -r key value; do
    case "$key" in
      SLUG) item_id="$value" ;;
      DEVELOPMENT_PATH) [ -z "$item_id" ] && item_id="$value" ;;
      STATUS) status="$value" ;;
      NEXT_ACTION) next_action="$value" ;;
      LABELS|PR_LABELS) labels="$value" ;;
      SKIP_REASON) skip_reason="$value" ;;
      PR_METADATA_STATUS) pr_metadata_status="$value" ;;
      PR_METADATA_REASON) pr_metadata_reason="$value" ;;
    esac
  done < "$TMP_BLOCKS.$idx"
  [ -z "$item_id" ] && item_id="unknown-item"

  report_category="$(report_category_for_item "$dispatch" "$status" "$next_action" "$labels" "$pr_metadata_status")"
  report_label="$(report_label_for_category "$report_category")"
  report_reason="$(report_reason_for_item "$report_category" "$dispatch" "$status" "$next_action" "$hold_reason" "$skip_reason" "$labels" "$pr_metadata_status" "$pr_metadata_reason")"
  if [ -n "$overlap_input" ]; then
    block_alias_file "$TMP_BLOCKS.$idx" "$TMP_ALIASES"
    while IFS= read -r alias_id; do
      [ -n "$alias_id" ] || continue
      overlap_group="$(jq -r --arg id "$alias_id" '.serialGroups[]? | select(((.itemIds // []) | index($id)) or ((.heldItemIds // []) | index($id)) or (.keepItemId == $id)) | .groupId' "$TMP_OVERLAP" | head -1)"
      [ -n "$overlap_group" ] && break
    done < "$TMP_ALIASES"
  fi

  cat "$TMP_BLOCKS.$idx"
  if [ -n "$overlap_group" ]; then
    print_kv OVERLAP_SERIAL_GROUP "$overlap_group"
  fi
  print_kv STAGE_LANE "$stage_lane"
  print_kv DISPATCH "$dispatch"
  print_kv REPORT_CATEGORY "$report_category"
  print_kv REPORT_LABEL "$report_label"
  print_kv REPORT_REASON "$report_reason"
  if [ "$dispatch" = "held" ] || [ "$dispatch" = "skip" ]; then
    print_kv HOLD_REASON "$hold_reason"
    if [ "$dispatch" = "held" ]; then
      print_kv HELD_SUMMARY "held — ${item_id}: ${hold_reason}"
    fi
  fi
  echo
  idx=$((idx + 1))
done
