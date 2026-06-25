#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=scripts/development-workflow/workflow-lib.sh
source "$SCRIPT_DIR/workflow-lib.sh"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/development-workflow/workflow-batch-lanes.sh [--repo-root <path>] [--scan [development-path ...]]
  ./scripts/development-workflow/workflow-batch-lanes.sh [--repo-root <path>] < batch-plan-output

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
    run-spec-review-and-open-pr) printf 'spec\n' ;;
    write-plan|run-plan-review-and-open-pr) printf 'plan\n' ;;
    run-code-review-and-open-pr|resolve-pr-readiness|resume-fix-loop|wait-human-review) printf 'review\n' ;;
    implement|resolve-development-pr) printf 'implementation\n' ;;
    *) printf 'review\n' ;;
  esac
}

read_parallelism_caps() {
  local config_file repo_root="$1"
  config_file="$(workflow_config_file "$repo_root")"
  if [ ! -f "$config_file" ]; then
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
  scan_args=()
  [ -n "${development_paths[*]:-}" ] && scan_args+=("${development_paths[@]}")
  batch_input="$("$SCRIPT_DIR/workflow-batch-plan.sh" "${scan_args[@]}")"
else
  batch_input="$(cat)"
fi

if [ -z "${batch_input//[[:space:]]/}" ]; then
  echo "(none)"
  exit 0
fi

TMP_BLOCKS="$(mktemp)"
TMP_META="$(mktemp)"
trap 'rm -f "$TMP_BLOCKS" "$TMP_META"' EXIT

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
  while IFS='=' read -r key value; do
    case "$key" in
      SLUG) item_id="$value" ;;
      DEVELOPMENT_PATH) [ -z "$item_id" ] && item_id="$value" ;;
    esac
  done < "$TMP_BLOCKS.$idx"
  [ -z "$item_id" ] && item_id="unknown-item"

  cat "$TMP_BLOCKS.$idx"
  print_kv STAGE_LANE "$stage_lane"
  print_kv DISPATCH "$dispatch"
  if [ "$dispatch" = "held" ]; then
    print_kv HOLD_REASON "$hold_reason"
    print_kv HELD_SUMMARY "held — ${item_id}: ${hold_reason}"
  fi
  echo
  idx=$((idx + 1))
done
