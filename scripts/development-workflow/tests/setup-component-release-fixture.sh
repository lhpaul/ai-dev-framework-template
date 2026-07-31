#!/usr/bin/env bash
#
# Create deterministic workflow-hub and single-repo fixtures for component
# release target/evidence tests.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"
TARGET_HELPER="$REPO_ROOT/scripts/development-workflow/component-release-target.sh"

WORK_DIR=""
JSON_OUTPUT=false

usage() {
  echo "Usage: setup-component-release-fixture.sh --work-dir PATH [--json]" >&2
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --work-dir)
      [ "$#" -ge 2 ] || { usage; exit 2; }
      WORK_DIR="$2"
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

if [ -z "$WORK_DIR" ]; then
  usage
  exit 2
fi

mkdir -p "$WORK_DIR"
WORK_DIR="$(CDPATH='' cd -- "$WORK_DIR" && pwd -P)"

SINGLE_REPO="$WORK_DIR/single-repo"
HUB_REPO="$WORK_DIR/workflow-hub"
PRODUCT_REPO="$WORK_DIR/mobile-app"
ALT_PRODUCT_REPO="admin-portal"
BAD_RELEASE_REPO="$WORK_DIR/bad-release-hub"
UNKNOWN_REPO="$WORK_DIR/unknown-repo-hub"
NO_LOCAL_REPO="$WORK_DIR/no-local-hub"
MALFORMED_REPO="$WORK_DIR/malformed-hub"
MISMATCH_DIR="$WORK_DIR/evidence-mismatches"

mkdir -p "$SINGLE_REPO" "$HUB_REPO" "$PRODUCT_REPO" "$BAD_RELEASE_REPO" "$UNKNOWN_REPO" "$NO_LOCAL_REPO" "$MALFORMED_REPO" "$MISMATCH_DIR"
git -C "$SINGLE_REPO" init -q
git -C "$HUB_REPO" init -q
git -C "$PRODUCT_REPO" init -q

cat > "$SINGLE_REPO/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
mode: single_repo
default_branch: develop
release:
  branch_pattern: release/v{version}
YAML
cat > "$SINGLE_REPO/.git/config" <<'GITCONFIG'
[remote "origin"]
  url = https://github.com/example/single-repo.git
GITCONFIG

cat > "$HUB_REPO/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
mode: workflow_hub

workflow_hub:
  product_repos:
    - name: mobile-app
      github_repo: example/mobile-app
      default_branch: release-base
      release:
        base: release-base
        branch_pattern: "{product_repo}/release/v{version}"
        changelog_owner: product_repo
        tag_owner: product_repo
        github_release_owner: product_repo
        deployment_evidence_owner: product_repo
        cleanup_evidence_owner: product_repo
        tracker_reconciliation_owner: hub
    - name: admin-portal
      github_repo: example/admin-portal
      default_branch: main
YAML
cat > "$HUB_REPO/.ai-dev-workflow.local.yaml" <<YAML
product_repos:
  - name: mobile-app
    local_path: ../mobile-app
YAML

cat > "$BAD_RELEASE_REPO/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
mode: workflow_hub

workflow_hub:
  product_repos:
    - name: mobile-app
      github_repo: example/mobile-app
      release:
        tag_owner: hub
YAML
cat > "$BAD_RELEASE_REPO/.ai-dev-workflow.local.yaml" <<YAML
product_repos:
  - name: mobile-app
    local_path: ../mobile-app
YAML

cat > "$UNKNOWN_REPO/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
mode: workflow_hub

workflow_hub:
  product_repos:
    - name: mobile-app
      github_repo: example/mobile-app
YAML

cat > "$NO_LOCAL_REPO/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
mode: workflow_hub

workflow_hub:
  product_repos:
    - name: mobile-app
      github_repo: example/mobile-app
YAML

cat > "$MALFORMED_REPO/.ai-dev-workflow.yaml" <<'YAML'
schema_version: [
YAML

printf '{"fixture":"1356"}\n' > "$WORK_DIR/tracker-state.json"

for repo in "$SINGLE_REPO" "$HUB_REPO" "$PRODUCT_REPO"; do
  git -C "$repo" config user.email "workflow-fixture@example.invalid"
  git -C "$repo" config user.name "Workflow Fixture"
  git -C "$repo" add .
  git -C "$repo" commit --allow-empty -q -m "fixture"
done

TARGET_JSON="$WORK_DIR/component-target.json"
"$TARGET_HELPER" --repo-root "$HUB_REPO" --repo mobile-app --json > "$TARGET_JSON"
cp "$TARGET_JSON" "$MISMATCH_DIR/base.json"
jq '.selected_product_repo_key = "admin-portal"' "$TARGET_JSON" > "$MISMATCH_DIR/repository_key.json"
jq '.canonical_repository_identity = "example/other-app"' "$TARGET_JSON" > "$MISMATCH_DIR/canonical_repository_identity.json"
jq '.artifact_owners.release = "hub_repository"' "$TARGET_JSON" > "$MISMATCH_DIR/artifact_owner.json"
jq '.release_correlation_key = "sha256:mismatch"' "$TARGET_JSON" > "$MISMATCH_DIR/release_correlation_key.json"
jq '.contract_revision = "sha256:mismatch"' "$TARGET_JSON" > "$MISMATCH_DIR/contract_revision.json"
jq -nS --slurpfile target "$TARGET_JSON" \
  '{
    schema_version:"component_release_evidence.v1",
    target_binding:($target[0] | .contract_revision = "sha256:mismatch"),
    release_branch:"mobile-app/release/v9.9.9-test",
    release_outcome:"completed",
    ci_outcome:"passed",
    deployment_outcome:"recorded",
    cleanup_outcome:"not_started",
    hub_tracker_ref:"fixture:1356"
  }' > "$WORK_DIR/mismatched-cleanup-evidence.json"

if [ "$JSON_OUTPUT" = "true" ]; then
  jq -cnS \
    --arg single_repo "$SINGLE_REPO" \
    --arg hub_repo "$HUB_REPO" \
    --arg product_repo "$PRODUCT_REPO" \
    --arg bad_release_repo "$BAD_RELEASE_REPO" \
    --arg alt_product_repo "$ALT_PRODUCT_REPO" \
    --arg unknown_repo "$UNKNOWN_REPO" \
    --arg no_local_repo "$NO_LOCAL_REPO" \
    --arg malformed_repo "$MALFORMED_REPO" \
    --arg mismatch_dir "$MISMATCH_DIR" \
    --arg tracker_state_file "$WORK_DIR/tracker-state.json" \
    '{
      hub_repo:$hub_repo,
      product_repo:$product_repo,
      bad_release_repo:$bad_release_repo,
      single_repo:{path:$single_repo},
      workflow_hub:{
        path:$hub_repo,
        selected_product_repo_key:"mobile-app",
        alternate_product_repo_key:$alt_product_repo,
        selected_product_repo_path:$product_repo,
        product_repos:["mobile-app",$alt_product_repo],
        local_paths:{"mobile-app":true},
        release_contract:{branch_pattern:"{product_repo}/release/v{version}"}
      },
      release:{version:"9.9.9-test"},
      tracker:{issue:"fixture:1356",state_file:$tracker_state_file},
      invalid_fixtures:{
        missing_product_selection:$hub_repo,
        multiple_product_targets:$hub_repo,
        unknown_product_repository:$unknown_repo,
        ambiguous_product_selection:$hub_repo,
        invalid_release_contract:$bad_release_repo,
        unavailable_product_repository_checkout:$no_local_repo,
        malformed:$malformed_repo
      },
      evidence_mismatch_fixtures:{
        repository_key:($mismatch_dir + "/repository_key.json"),
        canonical_repository_identity:($mismatch_dir + "/canonical_repository_identity.json"),
        artifact_owner:($mismatch_dir + "/artifact_owner.json"),
        release_correlation_key:($mismatch_dir + "/release_correlation_key.json"),
        contract_revision:($mismatch_dir + "/contract_revision.json")
      },
      cleanup:{
        seeded_branch:true,
        seeded_tag:true,
        seeded_lock:true,
        mismatched_evidence_file:($mismatch_dir + "/../mismatched-cleanup-evidence.json")
      }
    }'
else
  printf 'SINGLE_REPO=%s\n' "$SINGLE_REPO"
  printf 'HUB_REPO=%s\n' "$HUB_REPO"
  printf 'PRODUCT_REPO=%s\n' "$PRODUCT_REPO"
  printf 'BAD_RELEASE_REPO=%s\n' "$BAD_RELEASE_REPO"
fi
