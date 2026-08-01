#!/usr/bin/env bash
# setup-component-milestone-fixture.sh - fixtures for component milestone tests.

set -euo pipefail

OUTPUT_DIR=""
JSON_OUTPUT=false

usage() {
  cat >&2 <<'EOF'
Usage: setup-component-milestone-fixture.sh --output-dir DIR [--json]
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

PRODUCT_REPO="mobile-app"
COMPONENT_TAG="mobile-v1.4.0"
PARENT_ISSUE=1352
COMPONENT_ISSUE=1358
DELIVERY_BUNDLE_ISSUE=1357

complete_evidence="$OUTPUT_DIR/mobile-evidence.json"
mismatched_evidence="$OUTPUT_DIR/mismatched-product.json"
tag_mismatch_evidence="$OUTPUT_DIR/tag-mismatch.json"
wrong_schema_evidence="$OUTPUT_DIR/wrong-schema.json"
incomplete_evidence="$OUTPUT_DIR/incomplete.json"
missing_state_evidence="$OUTPUT_DIR/missing-state.json"
pending_evidence="$OUTPUT_DIR/pending.json"
failed_evidence="$OUTPUT_DIR/failed.json"
blocked_evidence="$OUTPUT_DIR/blocked.json"
stale_evidence="$OUTPUT_DIR/stale.json"
conflicting_evidence="$OUTPUT_DIR/conflicting.json"
missing_path="$OUTPUT_DIR/missing-evidence.json"

write_evidence() {
  local path="$1"
  local product_repo="$2"
  local release_outcome="${3:-completed}"
  local ci_outcome="${4:-passed}"
  local deployment_outcome="${5:-recorded}"
  local cleanup_outcome="${6:-complete}"
  local hub_outcome="${7:-complete}"
  local child_state="${8:-released}"
  local evidence_state="${9:-verified}"
  jq -nS \
    --arg product_repo "$product_repo" \
    --arg component_tag "$COMPONENT_TAG" \
    --arg release_outcome "$release_outcome" \
    --arg ci_outcome "$ci_outcome" \
    --arg deployment_outcome "$deployment_outcome" \
    --arg cleanup_outcome "$cleanup_outcome" \
    --arg hub_outcome "$hub_outcome" \
    --arg child_state "$child_state" \
    --arg evidence_state "$evidence_state" \
    '{
      schema_version:"component_release_evidence.v1",
      target_binding:{
        selected_product_repo_key:$product_repo,
        canonical_repository_identity:("example/" + $product_repo),
        release_correlation_key:("sha256:" + $product_repo + "-release"),
        contract_revision:("sha256:" + $product_repo + "-contract")
      },
      routing_outcome:"component_release_routed",
      selected_product_repo_key:$product_repo,
      canonical_repository_identity:("example/" + $product_repo),
      release_correlation_key:("sha256:" + $product_repo + "-release"),
      contract_revision:("sha256:" + $product_repo + "-contract"),
      component_tag:$component_tag,
      release_outcome:$release_outcome,
      ci_outcome:$ci_outcome,
      deployment_outcome:$deployment_outcome,
      cleanup_outcome:$cleanup_outcome,
      hub_tracker_ref:"#1358",
      hub_tracker_reconciliation_outcome:$hub_outcome,
      child_release_state:$child_state,
      evidence_state:$evidence_state
    }' > "$path"
}

write_evidence "$complete_evidence" "$PRODUCT_REPO"
write_evidence "$mismatched_evidence" "web-app"
jq --arg tag "mobile-v1.3.0" '.component_tag = $tag' "$complete_evidence" > "$tag_mismatch_evidence"
jq -nS '{schema_version:"wrong.v1"}' > "$wrong_schema_evidence"
jq 'del(.canonical_repository_identity, .target_binding.canonical_repository_identity)' "$complete_evidence" > "$incomplete_evidence"
jq 'del(.evidence_state, .child_release_state)' "$complete_evidence" > "$missing_state_evidence"
write_evidence "$pending_evidence" "$PRODUCT_REPO" pending pending pending partial pending pending
write_evidence "$failed_evidence" "$PRODUCT_REPO" failed failed failed blocked blocked failed
write_evidence "$blocked_evidence" "$PRODUCT_REPO" blocked passed recorded blocked complete blocked
write_evidence "$stale_evidence" "$PRODUCT_REPO" completed passed recorded complete complete released stale
write_evidence "$conflicting_evidence" "$PRODUCT_REPO" completed passed recorded complete complete released conflicting

write_bundle() {
  local path="$1"
  local status="$2"
  local mobile_state="$3"
  local web_state="$4"
  jq -nS \
    --arg status "$status" \
    --arg mobile_state "$mobile_state" \
    --arg web_state "$web_state" \
    'def released_component($key):
      {
        component_key:$key,
        evidence_state:"verified",
        release_outcome:"completed",
        ci_outcome:"passed",
        deployment_outcome:"recorded",
        cleanup_outcome:"complete",
        hub_tracker_reconciliation_outcome:"complete",
        child_release_state:"released"
      };
    def pending_component($key):
      {
        component_key:$key,
        evidence_state:"partial",
        release_outcome:"pending",
        ci_outcome:"pending",
        deployment_outcome:"pending",
        cleanup_outcome:"partial",
        hub_tracker_reconciliation_outcome:"pending",
        child_release_state:"pending"
      };
    def blocked_component($key):
      {
        component_key:$key,
        evidence_state:"conflicting",
        release_outcome:"blocked",
        ci_outcome:"passed",
        deployment_outcome:"recorded",
        cleanup_outcome:"blocked",
        hub_tracker_reconciliation_outcome:"pending",
        child_release_state:"blocked",
        blockers:["conflicting_component_evidence"]
      };
    {
      schema_version:"delivery_bundle_manifest.v1",
      bundle_key:"mobile-web-july-delivery",
      title:"Mobile and Web July delivery",
      parent_ref:"#1352",
      status:$status,
      revision:5,
      components:[
        (if $mobile_state == "released" then released_component("mobile-app") elif $mobile_state == "blocked" then blocked_component("mobile-app") else pending_component("mobile-app") end),
        (if $web_state == "released" then released_component("web-app") elif $web_state == "blocked" then blocked_component("web-app") else pending_component("web-app") end)
      ],
      readiness:{
        revision:5,
        ready:($status == "finalized"),
        status:$status,
        blockers:([
          if $mobile_state == "blocked" then {component_key:"mobile-app", blocker:"conflicting_component_evidence"} else empty end,
          if $web_state == "blocked" then {component_key:"web-app", blocker:"conflicting_component_evidence"} else empty end
        ])
      },
      audit_events:[{event:"fixture_created", revision:5, created_at:"2026-08-01T00:00:00Z"}]
    }' > "$path"
}

partial_bundle="$OUTPUT_DIR/partial-bundle.json"
blocked_bundle="$OUTPUT_DIR/blocked-bundle.json"
corrected_bundle="$OUTPUT_DIR/corrected-bundle.json"
finalized_bundle="$OUTPUT_DIR/finalized-bundle.json"
finalized_incomplete_bundle="$OUTPUT_DIR/finalized-incomplete-bundle.json"
status_write_failure_bundle="$OUTPUT_DIR/status-write-failure-bundle.json"
status_write_failure_parent="$OUTPUT_DIR/status-output-parent-is-file"
status_write_failure_target="$status_write_failure_parent/status.json"

write_bundle "$partial_bundle" open released pending
write_bundle "$blocked_bundle" open released blocked
write_bundle "$corrected_bundle" finalized released released
write_bundle "$finalized_bundle" finalized released released
write_bundle "$finalized_incomplete_bundle" finalized released pending
cp "$finalized_bundle" "$status_write_failure_bundle"
printf 'not a directory\n' > "$status_write_failure_parent"

mock_bin="$OUTPUT_DIR/mock-bin"
mock_state="$OUTPUT_DIR/mock-state.json"
gh_call_log="$OUTPUT_DIR/gh-call.log"
mkdir -p "$mock_bin"
touch "$gh_call_log"
jq -nS \
  --arg title "${PRODUCT_REPO}@${COMPONENT_TAG}" \
  '{
    next_milestone:99,
    milestones:[{number:7,title:$title}],
    issues:{}
  }' > "$mock_state"

mock_gh="$mock_bin/gh"
cat > "$mock_gh" <<'MOCK_GH'
#!/usr/bin/env bash
set -euo pipefail

STATE_FILE="${COMPONENT_MILESTONE_MOCK_STATE:?missing COMPONENT_MILESTONE_MOCK_STATE}"
CALL_LOG="${COMPONENT_MILESTONE_GH_CALL_LOG:?missing COMPONENT_MILESTONE_GH_CALL_LOG}"

if [ "${1:-}" != "api" ]; then
  echo "unsupported gh command" >&2
  exit 1
fi
shift
args=("$@")
joined="${args[*]}"

if [[ "$joined" == *"milestones?state=all&per_page=100"* ]]; then
  jq -c "[.milestones]" "$STATE_FILE"
  exit 0
fi

if [ "${1:-}" = "-X" ] && [ "${2:-}" = "POST" ] && [[ "${3:-}" == repos/*/milestones ]]; then
  title=""
  for arg in "$@"; do
    case "$arg" in
      title=*) title="${arg#title=}" ;;
    esac
  done
  [ -n "$title" ] || { echo "missing title" >&2; exit 1; }
  jq --arg title "$title" \
    '.next_milestone as $n | .next_milestone = ($n + 1) | .milestones += [{number:$n,title:$title}] | {state:., created:{number:$n,title:$title}}' \
    "$STATE_FILE" > "$STATE_FILE.tmp"
  jq ".state" "$STATE_FILE.tmp" > "$STATE_FILE.next"
  mv "$STATE_FILE.next" "$STATE_FILE"
  jq -c ".created" "$STATE_FILE.tmp"
  rm -f "$STATE_FILE.tmp" "$STATE_FILE.next"
  printf "%s\n" "$joined" >> "$CALL_LOG"
  exit 0
fi

if [ "${1:-}" = "-X" ] && [ "${2:-}" = "PATCH" ] && [[ "${3:-}" == repos/*/issues/* ]]; then
  issue="${3##*/}"
  milestone=""
  for arg in "$@"; do
    case "$arg" in
      milestone=*) milestone="${arg#milestone=}" ;;
    esac
  done
  [ -n "$milestone" ] || { echo "missing milestone" >&2; exit 1; }
  jq --arg issue "$issue" --argjson milestone "$milestone" \
    '.issues[$issue].milestone = {number:$milestone}' \
    "$STATE_FILE" > "$STATE_FILE.tmp"
  mv "$STATE_FILE.tmp" "$STATE_FILE"
  printf "%s\n" "$joined" >> "$CALL_LOG"
  jq -c --arg issue "$issue" '.issues[$issue] // {}' "$STATE_FILE"
  exit 0
fi

if [[ "${1:-}" == repos/*/issues/* ]]; then
  issue="${1##*/}"
  jq -c --arg issue "$issue" '.issues[$issue] // {number:($issue|tonumber),milestone:null}' "$STATE_FILE"
  exit 0
fi

echo "unsupported gh api: $joined" >&2
exit 1
MOCK_GH
chmod +x "$mock_gh"

fixture_json="$(jq -nS \
  --arg gh_bin "$mock_bin" \
  --arg gh_log "$gh_call_log" \
  --arg gh_state "$mock_state" \
  --argjson parent "$PARENT_ISSUE" \
  --argjson component "$COMPONENT_ISSUE" \
  --argjson bundle "$DELIVERY_BUNDLE_ISSUE" \
  --arg complete "$complete_evidence" \
  --arg mismatched "$mismatched_evidence" \
  --arg missing "$missing_path" \
  --arg partial "$partial_bundle" \
  --arg finalized "$finalized_bundle" \
  --arg blocked "$blocked_bundle" \
  --arg corrected "$corrected_bundle" \
  --arg finalized_incomplete "$finalized_incomplete_bundle" \
  --arg status_failure "$status_write_failure_bundle" \
  --arg status_target "$status_write_failure_target" \
  --arg wrong_schema "$wrong_schema_evidence" \
  --arg incomplete "$incomplete_evidence" \
  --arg missing_state "$missing_state_evidence" \
  --arg tag_mismatch "$tag_mismatch_evidence" \
  --arg pending "$pending_evidence" \
  --arg failed "$failed_evidence" \
  --arg blocked_evidence "$blocked_evidence" \
  --arg stale "$stale_evidence" \
  --arg conflicting "$conflicting_evidence" \
  '{
    product_repo:"mobile-app",
    component_tag:"mobile-v1.4.0",
    mock_gh:{bin_dir:$gh_bin, call_log:$gh_log, state:$gh_state},
    issues:{parent:$parent, component_child:$component, delivery_bundle:$bundle},
    evidence:{complete:$complete, mismatched_product:$mismatched, missing_path:$missing},
    bundles:{
      partial:$partial,
      finalized:$finalized,
      finalized_incomplete:$finalized_incomplete,
      blocked:$blocked,
      corrected:$corrected,
      status_write_failure:$status_failure
    },
    status_write_failure_target:$status_target,
    evidence_cases:[
      {name:"missing-product", expected_outcome:"missing_product_selection", component_tag:"mobile-v1.4.0", evidence_file:$complete},
      {name:"missing-tag", expected_outcome:"component_tag_missing", product_repo:"mobile-app", evidence_file:$complete},
      {name:"missing-file", expected_outcome:"component_release_pending", product_repo:"mobile-app", component_tag:"mobile-v1.4.0", evidence_file:$missing},
      {name:"wrong-schema", expected_outcome:"component_release_not_ready", product_repo:"mobile-app", component_tag:"mobile-v1.4.0", evidence_file:$wrong_schema},
      {name:"incomplete", expected_outcome:"component_release_not_ready", product_repo:"mobile-app", component_tag:"mobile-v1.4.0", evidence_file:$incomplete},
      {name:"missing-state", expected_outcome:"component_release_not_ready", product_repo:"mobile-app", component_tag:"mobile-v1.4.0", evidence_file:$missing_state},
      {name:"pending", expected_outcome:"component_release_not_ready", product_repo:"mobile-app", component_tag:"mobile-v1.4.0", evidence_file:$pending},
      {name:"failed", expected_outcome:"component_release_not_ready", product_repo:"mobile-app", component_tag:"mobile-v1.4.0", evidence_file:$failed},
      {name:"blocked", expected_outcome:"component_release_not_ready", product_repo:"mobile-app", component_tag:"mobile-v1.4.0", evidence_file:$blocked_evidence},
      {name:"stale", expected_outcome:"component_release_not_ready", product_repo:"mobile-app", component_tag:"mobile-v1.4.0", evidence_file:$stale},
      {name:"conflicting", expected_outcome:"component_release_not_ready", product_repo:"mobile-app", component_tag:"mobile-v1.4.0", evidence_file:$conflicting},
      {name:"tag-mismatch", expected_outcome:"component_target_mismatch", product_repo:"mobile-app", component_tag:"mobile-v1.4.0", evidence_file:$tag_mismatch},
      {name:"mismatched", expected_outcome:"component_target_mismatch", product_repo:"mobile-app", component_tag:"mobile-v1.4.0", evidence_file:$mismatched}
    ]
  }')"

if [ "$JSON_OUTPUT" = "true" ]; then
  printf '%s\n' "$fixture_json"
else
  printf 'FIXTURES=%s\n' "$fixture_json"
fi
