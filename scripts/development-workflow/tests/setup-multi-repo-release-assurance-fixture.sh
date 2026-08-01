#!/usr/bin/env bash
# setup-multi-repo-release-assurance-fixture.sh - fixtures for #1359 assurance tests.

set -euo pipefail

OUTPUT_DIR=""
JSON_OUTPUT=false

usage() {
  cat >&2 <<'EOF'
Usage: setup-multi-repo-release-assurance-fixture.sh --output-dir DIR [--json]
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --output-dir)
      [ "$#" -ge 2 ] || { usage; exit 2; }
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --json)
      JSON_OUTPUT=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

[ -n "$OUTPUT_DIR" ] || { usage; exit 2; }
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(CDPATH='' cd -- "$OUTPUT_DIR" && pwd -P)"

write_baselines() {
  local root="$1"
  local mutate_product="${2:-false}"
  mkdir -p "$root/historical/hub-before" "$root/historical/hub-after" \
    "$root/historical/product-before" "$root/historical/product-after"
  printf 'hub-milestone: legacy-v1\n' > "$root/historical/hub-before/milestones.txt"
  printf 'hub-delivery: legacy-delivery\n' > "$root/historical/hub-before/delivery-records.txt"
  cp "$root/historical/hub-before/milestones.txt" "$root/historical/hub-after/milestones.txt"
  cp "$root/historical/hub-before/delivery-records.txt" "$root/historical/hub-after/delivery-records.txt"

  printf 'product-tag: v1.2.3\n' > "$root/historical/product-before/tags.txt"
  printf 'product-changelog: old release\n' > "$root/historical/product-before/changelog.txt"
  cp "$root/historical/product-before/tags.txt" "$root/historical/product-after/tags.txt"
  cp "$root/historical/product-before/changelog.txt" "$root/historical/product-after/changelog.txt"
  if [ "$mutate_product" = "true" ]; then
    printf 'product-changelog: rewritten release\n' > "$root/historical/product-after/changelog.txt"
  fi
}

write_manifest() {
  local root="$1"
  local mode="$2"
  case "$mode" in
    valid)
      jq -nS '{
        scenarios:[
          {name:"component_routing", owner:"hub", outcome:"pass"},
          {name:"configuration_validation", owner:"hub", outcome:"pass"},
          {name:"namespaced_component_milestones", owner:"hub", outcome:"pass"},
          {name:"bundle_finalization", owner:"hub", outcome:"pass"},
          {name:"partial_failures", owner:"product", outcome:"pass"},
          {name:"reruns", owner:"product", outcome:"pass", run_id:"run-2", step_id:"cleanup", supersedes:"run-1", idempotency_guard:"cleanup-complete"},
          {name:"migration_no_rewrite", owner:"hub", outcome:"pass"},
          {name:"single_repo_compatibility", owner:"hub", outcome:"skipped", approved_skipped:true, rationale:"not applicable to workflow_hub adoption fixture"}
        ]
      }' > "$root/assurance.json"
      ;;
    blocked)
      jq -nS '{
        scenarios:[
          {name:"component_routing", owner:"hub", outcome:"pass"},
          {name:"configuration_validation", owner:"product", outcome:"blocked", required_next_action:"fix product release contract owner"}
        ]
      }' > "$root/assurance.json"
      ;;
    retryable)
      jq -nS '{
        scenarios:[
          {name:"reruns", owner:"product", outcome:"retryable", stale_attempt:true, run_id:"run-1", step_id:"handoff", required_next_action:"rerun corrected handoff with current run id"}
        ]
      }' > "$root/assurance.json"
      ;;
    repeated-side-effect)
      jq -nS '{
        scenarios:[
          {name:"reruns", owner:"product", outcome:"pass", run_id:"run-2", step_id:"cleanup", side_effect_repeated:true}
        ]
      }' > "$root/assurance.json"
      ;;
    *)
      echo "Unknown manifest mode: $mode" >&2
      exit 2
      ;;
  esac
}

valid_dir="$OUTPUT_DIR/valid"
blocked_dir="$OUTPUT_DIR/blocked"
retryable_dir="$OUTPUT_DIR/retryable"
history_mutation_dir="$OUTPUT_DIR/history-mutation"
repeated_side_effect_dir="$OUTPUT_DIR/repeated-side-effect"

for dir in "$valid_dir" "$blocked_dir" "$retryable_dir" "$repeated_side_effect_dir"; do
  mkdir -p "$dir"
  write_baselines "$dir"
done
mkdir -p "$history_mutation_dir"
write_baselines "$history_mutation_dir" true

write_manifest "$valid_dir" valid
write_manifest "$blocked_dir" blocked
write_manifest "$retryable_dir" retryable
write_manifest "$history_mutation_dir" valid
write_manifest "$repeated_side_effect_dir" repeated-side-effect

fixture_json="$(jq -nS \
  --arg valid "$valid_dir" \
  --arg blocked "$blocked_dir" \
  --arg retryable "$retryable_dir" \
  --arg history_mutation "$history_mutation_dir" \
  --arg repeated_side_effect "$repeated_side_effect_dir" \
  '{
    fixtures:{
      valid:$valid,
      blocked:$blocked,
      retryable:$retryable,
      history_mutation:$history_mutation,
      repeated_side_effect:$repeated_side_effect
    }
  }')"

if [ "$JSON_OUTPUT" = "true" ]; then
  printf '%s\n' "$fixture_json"
else
  printf 'FIXTURES=%s\n' "$fixture_json"
fi
