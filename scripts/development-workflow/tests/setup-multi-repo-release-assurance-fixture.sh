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

fail() {
  local code="$1"
  local message="$2"
  printf 'ERROR_CODE=%s message=%q\n' "$code" "$message" >&2
  exit 2
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --output-dir)
      [ "$#" -ge 2 ] || { usage; fail "missing_output_dir_value" "--output-dir requires a value"; }
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
      usage
      fail "unknown_argument" "unknown argument: $1"
      ;;
  esac
done

[ -n "$OUTPUT_DIR" ] || { usage; fail "missing_output_dir" "--output-dir is required"; }
if ! command -v jq >/dev/null 2>&1; then
  fail "missing_jq" "jq is required"
fi
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
          {
            name:"component_routing",
            owner:"hub",
            outcome:"pass",
            selected_product_repo_key:"mobile-app",
            canonical_repository_identity:"example/mobile-app",
            release_contract:"sha256:valid-contract"
          },
          {
            name:"configuration_validation",
            owner:"hub",
            outcome:"pass",
            hub_config:"validated",
            product_config:"validated"
          },
          {
            name:"namespaced_component_milestones",
            owner:"hub",
            outcome:"pass",
            component_evidence:"component_release_evidence.v1",
            milestone_reconciliation:"mobile-app@v1.2.3"
          },
          {
            name:"bundle_finalization",
            owner:"hub",
            outcome:"pass",
            delivery_bundle_manifest:"delivery_bundle_manifest.v1",
            component_evidence:"component_release_evidence.v1"
          },
          {name:"partial_failures", owner:"product", outcome:"pass"},
          {name:"reruns", owner:"product", outcome:"pass", run_id:"run-2", step_id:"cleanup", supersedes:"run-1", idempotency_guard:"cleanup-complete"},
          {name:"migration_no_rewrite", owner:"hub", outcome:"pass"},
          {name:"single_repo_compatibility", owner:"hub", outcome:"skipped", approved_skipped:true, rationale:"not applicable to workflow_hub adoption fixture"}
        ]
      }' > "$root/assurance.json"
      ;;
    blocked)
      write_manifest "$root" valid
      tmp="$root/assurance.json.tmp"
      jq '
        (.scenarios[] | select(.name == "configuration_validation")) |=
          (. + {owner:"product", outcome:"blocked", required_next_action:"fix product release contract owner"})
      ' "$root/assurance.json" > "$tmp"
      mv "$tmp" "$root/assurance.json"
      ;;
    retryable)
      write_manifest "$root" valid
      tmp="$root/assurance.json.tmp"
      jq '
        (.scenarios[] | select(.name == "reruns")) |=
          (. + {outcome:"retryable", stale_attempt:true, run_id:"run-1", step_id:"handoff", required_next_action:"rerun corrected handoff with current run id"})
      ' "$root/assurance.json" > "$tmp"
      mv "$tmp" "$root/assurance.json"
      ;;
    repeated-side-effect)
      write_manifest "$root" valid
      tmp="$root/assurance.json.tmp"
      jq '
        (.scenarios[] | select(.name == "reruns")) |=
          (. + {side_effect_repeated:true})
      ' "$root/assurance.json" > "$tmp"
      mv "$tmp" "$root/assurance.json"
      ;;
    missing-evidence)
      write_manifest "$root" valid
      tmp="$root/assurance.json.tmp"
      jq '
        (.scenarios[] | select(.name == "component_routing")) |=
          (del(.selected_product_repo_key, .canonical_repository_identity, .release_contract)) |
        (.scenarios[] | select(.name == "configuration_validation")) |=
          (del(.hub_config, .product_config)) |
        (.scenarios[] | select(.name == "namespaced_component_milestones")) |=
          (del(.component_evidence, .milestone_reconciliation)) |
        (.scenarios[] | select(.name == "bundle_finalization")) |=
          (del(.delivery_bundle_manifest, .component_evidence)) |
        (.scenarios[] | select(.name == "reruns")) |=
          (del(.step_id, .supersedes, .idempotency_guard))
      ' "$root/assurance.json" > "$tmp"
      mv "$tmp" "$root/assurance.json"
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
missing_evidence_dir="$OUTPUT_DIR/missing-evidence"

for dir in "$valid_dir" "$blocked_dir" "$retryable_dir" "$repeated_side_effect_dir" "$missing_evidence_dir"; do
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
write_manifest "$missing_evidence_dir" missing-evidence

fixture_json="$(jq -nS \
  --arg valid "$valid_dir" \
  --arg blocked "$blocked_dir" \
  --arg retryable "$retryable_dir" \
  --arg history_mutation "$history_mutation_dir" \
  --arg repeated_side_effect "$repeated_side_effect_dir" \
  --arg missing_evidence "$missing_evidence_dir" \
  '{
    fixtures:{
      valid:$valid,
      blocked:$blocked,
      retryable:$retryable,
      history_mutation:$history_mutation,
      repeated_side_effect:$repeated_side_effect,
      missing_evidence:$missing_evidence
    }
  }')"

if [ "$JSON_OUTPUT" = "true" ]; then
  printf '%s\n' "$fixture_json"
else
  printf 'FIXTURES=%s\n' "$fixture_json"
fi
