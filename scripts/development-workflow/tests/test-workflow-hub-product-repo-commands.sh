#!/usr/bin/env bash
# test-workflow-hub-product-repo-commands.sh - workflow-hub product command tests.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"
STATUS_CMD="$REPO_ROOT/scripts/development-workflow/hub-status.sh"
SYNC_CMD="$REPO_ROOT/scripts/development-workflow/hub-sync-product-repos.sh"
PRS_CMD="$REPO_ROOT/scripts/development-workflow/hub-list-prs.sh"
RESOLVER="$REPO_ROOT/scripts/development-workflow/workflow-config-resolver.py"

TMP_ROOT="$(mktemp -d)"
TMP_ROOT="$(CDPATH='' cd -- "$TMP_ROOT" && pwd -P)"

_harness_exit() {
  local status=$?
  rm -rf "$TMP_ROOT"
  case "$status" in
    141) exit 0 ;;
    *)   exit "$status" ;;
  esac
}
trap _harness_exit EXIT

PASS_COUNT=0
FAIL_COUNT=0

run_contains() {
  local name="$1"
  local expected="$2"
  local actual="$3"
  if grep -Fq -- "$expected" <<< "$actual"; then
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $name - expected output to contain '${expected}'"
    printf 'Actual output:\n%s\n' "$actual"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

run_not_contains() {
  local name="$1"
  local unexpected="$2"
  local actual="$3"
  if grep -Fq -- "$unexpected" <<< "$actual"; then
    echo "FAIL: $name - output unexpectedly contained '${unexpected}'"
    printf 'Actual output:\n%s\n' "$actual"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  else
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  fi
}

run_fails_contains() {
  local name="$1"
  local expected="$2"
  shift 2
  local output=""
  local status=0

  set +e
  output="$("$@" 2>&1)"
  status=$?
  set -e

  if [ "$status" -ne 0 ] && grep -Fq -- "$expected" <<< "$output"; then
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $name - expected failure containing '${expected}'"
    printf 'Status: %s\nOutput:\n%s\n' "$status" "$output"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

fixture_dir() {
  local name="$1"
  local path="$TMP_ROOT/$name"
  mkdir -p "$path"
  printf '%s\n' "$path"
}

init_repo() {
  local path="$1"
  local branch="$2"
  mkdir -p "$path"
  git -C "$path" init -q -b "$branch"
  git -C "$path" config user.email "test@example.com"
  git -C "$path" config user.name "Test User"
  printf 'initial\n' > "$path/README.md"
  git -C "$path" add README.md
  git -C "$path" commit -q -m "initial commit"
}

echo ""
echo "=== Workflow hub product repository commands ==="

for command in "$STATUS_CMD" "$SYNC_CMD" "$PRS_CMD"; do
  help_output="$(bash "$command" --help)"
  run_contains "help_${command##*/}_usage" "Usage:" "$help_output"
  run_contains "help_${command##*/}_mode" "workflow_hub" "$help_output"
done

single_repo_dir="$(fixture_dir single-repo)"
cat > "$single_repo_dir/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
mode: single_repo
YAML
run_fails_contains "status_wrong_mode" "workflow_hub mode is required" bash "$STATUS_CMD" --repo-root "$single_repo_dir" --repo mobile-app
run_fails_contains "sync_wrong_mode" "workflow_hub mode is required" bash "$SYNC_CMD" --repo-root "$single_repo_dir" --repo mobile-app
run_fails_contains "prs_wrong_mode" "workflow_hub mode is required" bash "$PRS_CMD" --repo-root "$single_repo_dir" --repo mobile-app
run_fails_contains "status_missing_repo_value" "--repo requires a value" bash "$STATUS_CMD" --repo
run_fails_contains "sync_missing_repo_value" "--repo requires a value" bash "$SYNC_CMD" --repo
run_fails_contains "prs_missing_repo_value" "--repo requires a value" bash "$PRS_CMD" --repo
run_fails_contains "status_unknown_option" "unknown argument '--bogus'" bash "$STATUS_CMD" --bogus

hub_dir="$(fixture_dir hub)"
clean_repo="$(fixture_dir clean-product)"
dirty_repo="$(fixture_dir dirty-product)"
missing_checkout="$TMP_ROOT/missing-checkout"
mkdir -p "$missing_checkout"
init_repo "$clean_repo" main
init_repo "$dirty_repo" main
clean_remote="$(fixture_dir clean-remote.git)"
updater_repo="$(fixture_dir clean-updater)"
git init --bare -q -b main "$clean_remote"
git -C "$clean_repo" remote add origin "$clean_remote"
git -C "$clean_repo" push -q -u origin main
git clone -q "$clean_remote" "$updater_repo"
git -C "$updater_repo" config user.email "test@example.com"
git -C "$updater_repo" config user.name "Test User"
printf 'remote update\n' > "$updater_repo/remote.txt"
git -C "$updater_repo" add remote.txt
git -C "$updater_repo" commit -q -m "remote update"
git -C "$updater_repo" push -q origin main
printf 'dirty\n' > "$dirty_repo/dirty.txt"

cat > "$hub_dir/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
mode: workflow_hub

workflow_hub:
  product_repos:
    - name: clean-app
      github_repo: example/clean-app
      default_branch: main
    - name: dirty-app
      github_repo: example/dirty-app
      default_branch: main
    - name: missing-path-app
      github_repo: example/missing-path-app
      default_branch: main
    - name: missing-checkout-app
      github_repo: example/missing-checkout-app
      default_branch: main
    - name: git-url-app
      git_url: git@github.com:example/git-url-app.git
      default_branch: main
    - name: internal-app
      git_url: ssh://git@example.com/internal-app.git
      default_branch: main
YAML
cat > "$hub_dir/.ai-dev-workflow.local.yaml" <<YAML
product_repos:
  - name: clean-app
    local_path: "$clean_repo"
  - name: dirty-app
    local_path: "$dirty_repo"
  - name: missing-checkout-app
    local_path: "$missing_checkout"
YAML

repo_names="$(python3 "$RESOLVER" list-product-repos --repo-root "$hub_dir")"
run_contains "resolver_lists_clean" "clean-app" "$repo_names"
run_contains "resolver_lists_internal" "internal-app" "$repo_names"

clean_status="$(bash "$STATUS_CMD" --repo-root "$hub_dir" --repo clean-app)"
run_contains "status_clean_repo_name" "REPO clean-app" "$clean_status"
run_contains "status_clean_path" "LOCAL_PATH=$clean_repo" "$clean_status"
run_contains "status_clean_branch" "BRANCH=main" "$clean_status"
run_contains "status_clean_outcome" "STATUS=clean" "$clean_status"

set +e
all_status="$(bash "$STATUS_CMD" --repo-root "$hub_dir" --all 2>&1)"
all_status_code=$?
set -e
if [ "$all_status_code" -ne 0 ]; then
  echo "PASS: status_all_mixed_exit"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  echo "FAIL: status_all_mixed_exit - expected non-zero for missing repositories"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi
run_contains "status_all_dirty" "STATUS=dirty" "$all_status"
run_contains "status_all_missing_path" "STATUS=missing_path" "$all_status"
run_contains "status_all_missing_checkout" "STATUS=missing_checkout" "$all_status"
run_contains "status_all_summary" "SUMMARY" "$all_status"

run_fails_contains "sync_dirty_refusal" "REASON=dirty_checkout" bash "$SYNC_CMD" --repo-root "$hub_dir" --repo dirty-app
run_fails_contains "sync_repo_all_conflict" "--repo and --all cannot be used together" bash "$SYNC_CMD" --repo-root "$hub_dir" --repo clean-app --all

set +e
all_sync="$(bash "$SYNC_CMD" --repo-root "$hub_dir" --all 2>&1)"
all_sync_code=$?
set -e
if [ "$all_sync_code" -ne 0 ]; then
  echo "PASS: sync_all_mixed_exit"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  echo "FAIL: sync_all_mixed_exit - expected non-zero for blocked or failed repositories"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi
run_contains "sync_all_synced_repo" "STATUS=synced" "$all_sync"
run_contains "sync_all_blocked" "blocked=" "$all_sync"
run_contains "sync_all_failed_or_missing" "missing=" "$all_sync"
run_contains "sync_all_summary" "SUMMARY" "$all_sync"

run_fails_contains "missing_path_guidance" ".ai-dev-workflow.local.yaml" bash "$SYNC_CMD" --repo-root "$hub_dir" --repo missing-path-app

bootstrap_declined_before="$(cat "$hub_dir/.ai-dev-workflow.local.yaml")"
set +e
bootstrap_declined="$(printf 'n\n' | bash "$SYNC_CMD" --repo-root "$hub_dir" --repo missing-path-app --bootstrap-local-path 2>&1)"
bootstrap_declined_code=$?
set -e
if [ "$bootstrap_declined_code" -ne 0 ]; then
  echo "PASS: bootstrap_declined_exit"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  echo "FAIL: bootstrap_declined_exit - expected non-zero when declined"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi
run_contains "bootstrap_declined_output" "BOOTSTRAP=declined" "$bootstrap_declined"
bootstrap_declined_after="$(cat "$hub_dir/.ai-dev-workflow.local.yaml")"
if [ "$bootstrap_declined_before" = "$bootstrap_declined_after" ]; then
  echo "PASS: bootstrap_declined_no_write"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  echo "FAIL: bootstrap_declined_no_write - local config changed"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

bootstrap_yes="$(bash "$SYNC_CMD" --repo-root "$hub_dir" --repo missing-path-app --bootstrap-local-path --yes)"
run_contains "bootstrap_yes_written" "BOOTSTRAP=written" "$bootstrap_yes"
local_after_bootstrap="$(cat "$hub_dir/.ai-dev-workflow.local.yaml")"
run_contains "bootstrap_wrote_repo_name" "name: missing-path-app" "$local_after_bootstrap"
run_contains "bootstrap_wrote_local_path" "local_path:" "$local_after_bootstrap"
run_not_contains "bootstrap_no_secret" "secret" "$local_after_bootstrap"

mock_bin="$(fixture_dir mock-bin)"
cat > "$mock_bin/gh" <<'MOCKGH'
#!/usr/bin/env bash
set -euo pipefail
if [ "$1" = "pr" ] && [ "$2" = "list" ]; then
  repo=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --repo)
        repo="$2"
        shift 2
        ;;
      *)
        shift
        ;;
    esac
  done
  case "$repo" in
    example/clean-app|example/git-url-app)
      printf '[{"number":7,"title":"Ready PR","headRefName":"feature/test","baseRefName":"main","isDraft":false,"labels":[{"name":"ready-for-human-review"}]}]\n'
      ;;
    *)
      printf 'mock remote failure for %s\n' "$repo" >&2
      exit 1
      ;;
  esac
  exit 0
fi
printf 'unexpected gh invocation\n' >&2
exit 1
MOCKGH
chmod +x "$mock_bin/gh"

prs_output="$(PATH="$mock_bin:$PATH" bash "$PRS_CMD" --repo-root "$hub_dir" --repo clean-app)"
run_contains "prs_lists_number" "PR #7" "$prs_output"
run_contains "prs_uses_github_repo" "GITHUB_REPO=example/clean-app" "$prs_output"

git_url_prs="$(PATH="$mock_bin:$PATH" bash "$PRS_CMD" --repo-root "$hub_dir" --repo git-url-app)"
run_contains "prs_git_url_slug" "GITHUB_REPO=example/git-url-app" "$git_url_prs"
run_fails_contains "prs_non_github_url_fails" "REASON=no_github_repo_slug" env PATH="$mock_bin:$PATH" bash "$PRS_CMD" --repo-root "$hub_dir" --repo internal-app

printf '\nPassed: %s\nFailed: %s\n' "$PASS_COUNT" "$FAIL_COUNT"
if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi
