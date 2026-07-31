#!/usr/bin/env bash
#
# Create deterministic workflow-hub and single-repo fixtures for component
# release target/evidence tests.

set -euo pipefail

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
BAD_RELEASE_REPO="$WORK_DIR/bad-release-hub"

mkdir -p "$SINGLE_REPO/.git" "$HUB_REPO" "$PRODUCT_REPO" "$BAD_RELEASE_REPO"

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

if [ "$JSON_OUTPUT" = "true" ]; then
  jq -cnS \
    --arg single_repo "$SINGLE_REPO" \
    --arg hub_repo "$HUB_REPO" \
    --arg product_repo "$PRODUCT_REPO" \
    --arg bad_release_repo "$BAD_RELEASE_REPO" \
    '{single_repo:$single_repo,hub_repo:$hub_repo,product_repo:$product_repo,bad_release_repo:$bad_release_repo}'
else
  printf 'SINGLE_REPO=%s\n' "$SINGLE_REPO"
  printf 'HUB_REPO=%s\n' "$HUB_REPO"
  printf 'PRODUCT_REPO=%s\n' "$PRODUCT_REPO"
  printf 'BAD_RELEASE_REPO=%s\n' "$BAD_RELEASE_REPO"
fi
