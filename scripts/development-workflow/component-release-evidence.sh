#!/usr/bin/env bash
#
# Render and validate component release evidence against an independent target
# binding produced by component-release-target.sh.

set -euo pipefail

TARGET_FILE=""
BINDING_FILE=""
OUTPUT_FILE=""
RELEASE_BRANCH=""
COMPONENT_TAG=""
COMPONENT_VERSION=""
RELEASE_OUTCOME=""
CI_OUTCOME=""
DEPLOYMENT_OUTCOME=""
CLEANUP_OUTCOME=""
HUB_TRACKER_REF=""
JSON_OUTPUT=false

usage() {
  cat >&2 <<'EOF'
Usage: component-release-evidence.sh --target-file PATH --binding-file PATH --release-branch BRANCH --release-outcome OUTCOME --ci-outcome OUTCOME --deployment-outcome OUTCOME --cleanup-outcome OUTCOME --hub-tracker-ref REF [--component-tag TAG] [--component-version VERSION] [--output PATH] [--json]
EOF
}

require_file() {
  local label="$1"
  local path="$2"
  if [ -z "$path" ] || [ ! -f "$path" ]; then
    echo "$label file is required and must exist" >&2
    exit 2
  fi
  if ! jq -e 'type == "object"' "$path" >/dev/null 2>&1; then
    echo "$label file must contain a JSON object" >&2
    exit 2
  fi
}

validate_enum() {
  local label="$1"
  local value="$2"
  shift 2
  local candidate
  for candidate in "$@"; do
    if [ "$value" = "$candidate" ]; then
      return 0
    fi
  done
  echo "$label outcome '$value' is not allowed" >&2
  exit 2
}

compare_field() {
  local field="$1"
  local target binding
  target="$(jq -c "$field" "$TARGET_FILE")"
  binding="$(jq -c "$field" "$BINDING_FILE")"
  if [ "$target" != "$binding" ]; then
    echo "Evidence binding mismatch for $field: target=$target binding=$binding" >&2
    exit 1
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --target-file)
      [ "$#" -ge 2 ] || { usage; exit 2; }
      TARGET_FILE="$2"
      shift 2
      ;;
    --binding-file)
      [ "$#" -ge 2 ] || { usage; exit 2; }
      BINDING_FILE="$2"
      shift 2
      ;;
    --output)
      [ "$#" -ge 2 ] || { usage; exit 2; }
      OUTPUT_FILE="$2"
      shift 2
      ;;
    --release-outcome)
      [ "$#" -ge 2 ] || { usage; exit 2; }
      RELEASE_OUTCOME="$2"
      shift 2
      ;;
    --release-branch)
      [ "$#" -ge 2 ] || { usage; exit 2; }
      RELEASE_BRANCH="$2"
      shift 2
      ;;
    --component-tag)
      [ "$#" -ge 2 ] || { usage; exit 2; }
      COMPONENT_TAG="$2"
      shift 2
      ;;
    --component-version)
      [ "$#" -ge 2 ] || { usage; exit 2; }
      COMPONENT_VERSION="$2"
      shift 2
      ;;
    --ci-outcome)
      [ "$#" -ge 2 ] || { usage; exit 2; }
      CI_OUTCOME="$2"
      shift 2
      ;;
    --deployment-outcome)
      [ "$#" -ge 2 ] || { usage; exit 2; }
      DEPLOYMENT_OUTCOME="$2"
      shift 2
      ;;
    --cleanup-outcome)
      [ "$#" -ge 2 ] || { usage; exit 2; }
      CLEANUP_OUTCOME="$2"
      shift 2
      ;;
    --hub-tracker-ref)
      [ "$#" -ge 2 ] || { usage; exit 2; }
      HUB_TRACKER_REF="$2"
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

require_file "target" "$TARGET_FILE"
require_file "binding" "$BINDING_FILE"

validate_enum "release" "$RELEASE_OUTCOME" pending completed failed blocked
validate_enum "ci" "$CI_OUTCOME" pending passed failed not_applicable
validate_enum "deployment" "$DEPLOYMENT_OUTCOME" pending recorded failed not_applicable
validate_enum "cleanup" "$CLEANUP_OUTCOME" not_started partial complete blocked

if [ -z "$RELEASE_BRANCH" ]; then
  echo "--release-branch is required" >&2
  exit 2
fi
if ! git check-ref-format --branch "$RELEASE_BRANCH" >/dev/null 2>&1; then
  echo "--release-branch must be a valid branch name: $RELEASE_BRANCH" >&2
  exit 2
fi
if [ -z "$HUB_TRACKER_REF" ]; then
  echo "--hub-tracker-ref is required" >&2
  exit 2
fi

if ! jq -e '.schema_version == "component_release_target.v1"' "$TARGET_FILE" >/dev/null; then
  echo "target file must use schema_version component_release_target.v1" >&2
  exit 2
fi
if ! jq -e '.mutation_allowed == true' "$TARGET_FILE" >/dev/null; then
  echo "target binding is not mutation-allowed" >&2
  exit 1
fi

# Reject a --release-branch that is syntactically valid but does not match
# the target binding's release_branch_pattern (e.g. "totally/wrong" when the
# contract requires "{product_repo}/release/v{version}"). Without this,
# downstream reconciliation accepted evidence for a branch that could not
# possibly be the product's actual release branch.
release_branch_pattern="$(jq -r '.release_branch_pattern // ""' "$TARGET_FILE")"
selected_product_repo_key="$(jq -r '.selected_product_repo_key // ""' "$TARGET_FILE")"
if [ -n "$release_branch_pattern" ]; then
  if ! python3 - "$release_branch_pattern" "$selected_product_repo_key" "$RELEASE_BRANCH" <<'INNERPY'
import re
import sys

pattern, repo, branch = sys.argv[1], sys.argv[2], sys.argv[3]
parts = []
for token in re.split(r"(\{product_repo\}|\{version\})", pattern):
    if token == "{product_repo}":
        parts.append(re.escape(repo))
    elif token == "{version}":
        parts.append(r"[^/]+")
    else:
        parts.append(re.escape(token))
regex = "^" + "".join(parts) + "$"
sys.exit(0 if re.match(regex, branch) else 1)
INNERPY
  then
    echo "--release-branch '$RELEASE_BRANCH' does not match the target release_branch_pattern '$release_branch_pattern'" >&2
    exit 1
  fi
fi

compare_field '.routing_outcome'
compare_field '.selected_product_repo_key'
compare_field '.canonical_repository_identity'
compare_field '.artifact_owners'
compare_field '.release_correlation_key'
compare_field '.contract_revision'

# D4: refuse emission when producer_required identity fields are empty, when
# routing_outcome is unrecognized, or when selected_product_repo_key violates
# the producer_required_nullable iff with routing_outcome.
require_nonempty_identity() {
  local field="$1"
  local value
  value="$(jq -r "$field // \"\"" "$TARGET_FILE")"
  if [ -z "$value" ]; then
    echo "target binding is missing required identity field: ${field#.}" >&2
    exit 1
  fi
}

require_nonempty_identity '.canonical_repository_identity'
require_nonempty_identity '.release_correlation_key'
require_nonempty_identity '.contract_revision'
require_nonempty_identity '.routing_outcome'

routing_outcome="$(jq -r '.routing_outcome' "$TARGET_FILE")"
case "$routing_outcome" in
  component_release_routed|single_repo_release) ;;
  *)
    echo "target binding routing_outcome must be component_release_routed or single_repo_release, got: $routing_outcome" >&2
    exit 1
    ;;
esac

# artifact_owners sub-fields must each be non-empty
owner_field=""
for owner_field in release ci github_release deployment cleanup tracker; do
  owner_value="$(jq -r --arg f "$owner_field" '.artifact_owners[$f] // ""' "$TARGET_FILE")"
  if [ -z "$owner_value" ]; then
    echo "target binding is missing required identity field: artifact_owners" >&2
    exit 1
  fi
done

if [ "$routing_outcome" = "component_release_routed" ]; then
  if ! jq -e '(.selected_product_repo_key | type) == "string" and (.selected_product_repo_key | length) > 0' "$TARGET_FILE" >/dev/null; then
    echo "target binding is missing required identity field: selected_product_repo_key" >&2
    exit 1
  fi
fi

if [ "$routing_outcome" = "single_repo_release" ]; then
  if ! jq -e 'has("selected_product_repo_key") and (.selected_product_repo_key == null)' "$TARGET_FILE" >/dev/null \
    || ! jq -e 'has("selected_product_repo_key") and (.selected_product_repo_key == null)' "$BINDING_FILE" >/dev/null; then
    echo "target binding must not bind selected_product_repo_key under single_repo_release routing" >&2
    exit 1
  fi
fi

evidence="$(jq -cnS \
  --slurpfile target "$TARGET_FILE" \
  --arg release_branch "$RELEASE_BRANCH" \
  --arg release_outcome "$RELEASE_OUTCOME" \
  --arg ci_outcome "$CI_OUTCOME" \
  --arg deployment_outcome "$DEPLOYMENT_OUTCOME" \
  --arg cleanup_outcome "$CLEANUP_OUTCOME" \
  --arg hub_tracker_ref "$HUB_TRACKER_REF" \
  --arg component_tag "$COMPONENT_TAG" \
  --arg component_version "$COMPONENT_VERSION" \
  '{
    schema_version:"component_release_evidence.v1",
    target_binding:$target[0],
    routing_outcome:$target[0].routing_outcome,
    selected_product_repo_key:$target[0].selected_product_repo_key,
    canonical_repository_identity:$target[0].canonical_repository_identity,
    artifact_owners:$target[0].artifact_owners,
    release_correlation_key:$target[0].release_correlation_key,
    contract_revision:$target[0].contract_revision,
    release_branch:$release_branch,
    release_outcome:$release_outcome,
    ci_outcome:$ci_outcome,
    deployment_outcome:$deployment_outcome,
    cleanup_outcome:$cleanup_outcome,
    hub_tracker_ref:$hub_tracker_ref,
    component_tag:(if ($component_tag | length) > 0 then $component_tag else null end),
    component_version:(if ($component_version | length) > 0 then $component_version else null end)
  }')"

if [ -n "$OUTPUT_FILE" ]; then
  printf '%s\n' "$evidence" > "$OUTPUT_FILE"
fi

if [ "$JSON_OUTPUT" = "true" ] || [ -z "$OUTPUT_FILE" ]; then
  printf '%s\n' "$evidence"
else
  printf 'EVIDENCE_FILE=%s\n' "$OUTPUT_FILE"
fi
