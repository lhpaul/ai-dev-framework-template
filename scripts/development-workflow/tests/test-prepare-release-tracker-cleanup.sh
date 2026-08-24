#!/usr/bin/env bash
# test-prepare-release-tracker-cleanup.sh - release cleanup tracker scope tests.
#
# Covers:
#   1. Linear provider: --from-changelog extracts issues and emits action signal
#   2. Linear provider: --best-effort exits 0 but still emits action signal
#   3. Missing scope (no --issue / --from-changelog): emits no_issue_scope signal
#   4. Missing CHANGELOG version: emits changelog_scope_unavailable signal
#   5. Issue loop / TRACKER_UPDATED counting:
#      a. update_tracker_status_best_effort emits "Updating tracker status" -> UPDATED
#      b. update_tracker_status_best_effort emits TRACKER_ACTION_REQUIRED=set_status -> UPDATED
#      c. update_tracker_status_best_effort emits Warning: -> SKIPPED
#
# Usage: bash scripts/development-workflow/tests/test-prepare-release-tracker-cleanup.sh
# covers: scripts/development-workflow/prepare-release-post-merge-cleanup.sh
# covers: scripts/development-workflow/component-release-target.sh
# covers: scripts/development-workflow/workflow-config-resolver.py

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"

TMP_ROOT="$(mktemp -d)"
MOCK_BIN="$TMP_ROOT/bin"
PASS_COUNT=0
FAIL_COUNT=0

_harness_exit() {
  local status=$?
  rm -rf "$TMP_ROOT"
  case "$status" in
    141) exit 0 ;;
    *)   exit "$status" ;;
  esac
}
trap _harness_exit EXIT

mkdir -p "$MOCK_BIN"

cat > "$MOCK_BIN/gh" <<'MOCK_GH'
#!/usr/bin/env bash
case "$*" in
  "auth status")
    exit 0
    ;;
  "pr list --state merged --head release/v1.17.0 --base main --json number --jq .[0].number // empty")
    printf '331\n'
    ;;
  "pr list --state merged --head release/v1.17.0 --base develop --json number --jq .[0].number // empty")
    printf '332\n'
    ;;
  "pr list --state open --head release/v1.17.0 --base main --json number --jq .[0].number // empty")
    printf '\n'
    ;;
  "pr list --state open --head release/v1.17.0 --base develop --json number --jq .[0].number // empty")
    printf '\n'
    ;;
  "pr list --state merged --head release/v1.18.0 --base main --json number --jq .[0].number // empty")
    printf '400\n'
    ;;
  "pr list --state merged --head release/v1.18.0 --base develop --json number --jq .[0].number // empty")
    printf '401\n'
    ;;
  "pr list --state open --head release/v1.18.0 --base main --json number --jq .[0].number // empty")
    printf '\n'
    ;;
  "pr list --state open --head release/v1.18.0 --base develop --json number --jq .[0].number // empty")
    printf '\n'
    ;;
  "pr list --repo example/mobile-app --state merged --head mobile-app/release/v1.18.0 --base main --json number --jq .[0].number // empty")
    printf '500\n'
    ;;
  "pr list --repo example/mobile-app --state merged --head mobile-app/release/v1.18.0 --base release-base --json number --jq .[0].number // empty")
    printf '501\n'
    ;;
  "pr list --repo example/mobile-app --state open --head mobile-app/release/v1.18.0 --base main --json number --jq .[0].number // empty")
    printf '\n'
    ;;
  "pr list --repo example/mobile-app --state open --head mobile-app/release/v1.18.0 --base release-base --json number --jq .[0].number // empty")
    printf '\n'
    ;;
  "pr list --state merged --head mobile-app/release/v1.18.0 --base main --json number --jq .[0].number // empty")
    printf '400\n'
    ;;
  "pr list --state merged --head mobile-app/release/v1.18.0 --base release-base --json number --jq .[0].number // empty")
    printf '401\n'
    ;;
  "pr list --state open --head mobile-app/release/v1.18.0 --base main --json number --jq .[0].number // empty")
    printf '\n'
    ;;
  "pr list --state open --head mobile-app/release/v1.18.0 --base release-base --json number --jq .[0].number // empty")
    printf '\n'
    ;;
  "pr list --state merged --head release/mobile-app/v1.18.0 --base main --json number --jq .[0].number // empty")
    printf '402\n'
    ;;
  "pr list --state merged --head release/mobile-app/v1.18.0 --base release-base --json number --jq .[0].number // empty")
    printf '403\n'
    ;;
  "pr list --state open --head release/mobile-app/v1.18.0 --base main --json number --jq .[0].number // empty")
    printf '\n'
    ;;
  "pr list --state open --head release/mobile-app/v1.18.0 --base release-base --json number --jq .[0].number // empty")
    printf '\n'
    ;;
  issue\ view\ *\ --json\ state\ --jq\ .state)
    # Return OPEN for any issue view query so the issue loop proceeds to
    # update_tracker_status_best_effort (which is stubbed in the fixture lib).
    printf 'OPEN\n'
    ;;
  *)
    printf 'unexpected gh invocation: gh %s\n' "$*" >&2
    exit 64
    ;;
esac
MOCK_GH

cat > "$MOCK_BIN/git" <<'MOCK_GIT'
#!/usr/bin/env bash
case "$*" in
  "check-ref-format --branch bad branch")
    exit 1
    ;;
  check-ref-format\ --branch\ *)
    exit 0
    ;;
  "fetch origin --prune")
    exit 0
    ;;
  "ls-remote --exit-code --heads origin release/v1.17.0")
    exit 2
    ;;
  "show-ref --quiet refs/heads/release/v1.17.0")
    exit 1
    ;;
  "ls-remote --exit-code --heads origin release/v1.18.0")
    exit 2
    ;;
  "show-ref --quiet refs/heads/release/v1.18.0")
    exit 1
    ;;
  -C\ */mobile-app\ rev-parse\ --is-inside-work-tree)
    printf 'true\n'
    ;;
  -C\ */mobile-app\ rev-parse\ --git-dir)
    printf '.git\n'
    ;;
  -C\ *\ rev-parse\ --is-inside-work-tree)
    # Generic fallback for hub fixture checkouts (component-cleanup,
    # component-invalid-identity, etc.): validate_component_release_cleanup
    # now also resolves the hub checkout's own git-dir for the shared
    # cleanup lock.
    printf 'true\n'
    ;;
  -C\ *\ rev-parse\ --git-dir)
    printf '.git\n'
    ;;
  -C\ */mobile-app\ fetch\ origin\ --prune)
    exit 0
    ;;
  -C\ */mobile-app\ ls-remote\ --exit-code\ --heads\ origin\ mobile-app/release/v1.18.0)
    exit 0
    ;;
  -C\ */mobile-app\ push\ origin\ --delete\ mobile-app/release/v1.18.0)
    exit 0
    ;;
  -C\ */mobile-app\ show-ref\ --quiet\ refs/heads/mobile-app/release/v1.18.0)
    exit 0
    ;;
  -C\ */mobile-app\ branch\ --show-current)
    printf 'develop\n'
    ;;
  -C\ */mobile-app\ branch\ -D\ mobile-app/release/v1.18.0)
    exit 0
    ;;
  "ls-remote --exit-code --heads origin mobile-app/release/v1.18.0")
    exit 2
    ;;
  "show-ref --quiet refs/heads/mobile-app/release/v1.18.0")
    exit 1
    ;;
  "ls-remote --exit-code --heads origin release/mobile-app/v1.18.0")
    exit 2
    ;;
  "show-ref --quiet refs/heads/release/mobile-app/v1.18.0")
    exit 1
    ;;
  *)
    printf 'unexpected git invocation: git %s\n' "$*" >&2
    exit 64
    ;;
esac
MOCK_GIT

# Captured before the mock git below shadows PATH, so the linked-worktree
# regression test after "=== Prepare-release tracker cleanup ===" can invoke
# real git explicitly (git -C <path> ...) regardless of the mock.
REAL_GIT="$(command -v git)"

chmod +x "$MOCK_BIN/gh" "$MOCK_BIN/git"
export PATH="$MOCK_BIN:$PATH"

run_test() {
  local name="$1"
  local expected="$2"
  local actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $name - expected '${expected}', got '${actual}'"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

run_not_contains() {
  local name="$1"
  local unexpected="$2"
  local actual="$3"
  if grep -Fq -- "$unexpected" <<< "$actual"; then
    echo "FAIL: $name - expected output NOT to contain '${unexpected}'"
    printf 'Actual output:\n%s\n' "$actual"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  else
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  fi
}

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

fixture_repo() {
  local name="$1"
  local path="$TMP_ROOT/$name"
  mkdir -p "$path/scripts/development-workflow"
  cp "$REPO_ROOT/scripts/development-workflow/workflow-lib.sh" "$path/scripts/development-workflow/workflow-lib.sh"
  cp "$REPO_ROOT/scripts/development-workflow/prepare-release-post-merge-cleanup.sh" "$path/scripts/development-workflow/prepare-release-post-merge-cleanup.sh"
  chmod +x "$path/scripts/development-workflow/prepare-release-post-merge-cleanup.sh"
  cat > "$path/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
issue_tracker:
  provider: linear
YAML
  cat > "$path/CHANGELOG.md" <<'MD'
# Changelog

## [Unreleased]

## [1.17.0] - 2026-06-11

- Released bulk import work LEA-132–LEA-134 and follow-up LEA-140.
- Also shipped dashboard polish LEA-134 and internal note #914.

## [1.16.0] - 2026-06-01

- Older entry LEA-100.
MD
  printf '%s\n' "$path"
}

run_cleanup() {
  local repo="$1"
  shift
  local output=""
  local status=0

  set +e
  output="$(cd "$repo" && ./scripts/development-workflow/prepare-release-post-merge-cleanup.sh "$@" 2>&1)"
  status=$?
  set -e

  printf '%s\n%s\n' "$status" "$output"
}

echo ""
echo "=== Prepare-release tracker cleanup ==="

# Regression test for the linked-worktree checkout fix: a linked git worktree
# (as used by this workflow's per-item isolation) has a ".git" regular file,
# not a ".git" directory, pointing at the main checkout's per-worktree
# metadata directory. Exercise the exact resolution
# prepare-release-post-merge-cleanup.sh now uses (git rev-parse
# --is-inside-work-tree / --git-dir) against a real linked worktree, proving
# both that the old bare "[ -d .git ]" checkout validity test would have
# wrongly rejected it, and that the old bare
# "$target_path/.git/component-release-cleanup-locks" lock path would have
# failed to mkdir under a file. Uses $REAL_GIT (captured above, before the
# mock git took over PATH) so this is real, unmocked git.
worktree_main="$TMP_ROOT/worktree-fixture/main"
mkdir -p "$worktree_main"
# Resolve symlinks (e.g. macOS /var -> /private/var) so the path comparisons
# below match what git itself reports for --git-dir.
worktree_main="$(CDPATH='' cd -- "$worktree_main" && pwd -P)"
worktree_linked="$(dirname "$worktree_main")/linked"
"$REAL_GIT" -C "$worktree_main" init -q -b main
"$REAL_GIT" -C "$worktree_main" config user.email test@example.com
"$REAL_GIT" -C "$worktree_main" config user.name test
"$REAL_GIT" -C "$worktree_main" commit -q --allow-empty -m init
"$REAL_GIT" -C "$worktree_main" worktree add -q -b worktree-branch "$worktree_linked" >/dev/null

run_test "worktree_git_is_not_a_directory" "0" "$([ -d "$worktree_linked/.git" ] && echo 1 || echo 0)"
run_test "worktree_rev_parse_is_inside_work_tree" "true" "$("$REAL_GIT" -C "$worktree_linked" rev-parse --is-inside-work-tree)"

worktree_git_dir="$("$REAL_GIT" -C "$worktree_linked" rev-parse --git-dir)"
case "$worktree_git_dir" in
  /*) : ;;
  *) worktree_git_dir="$worktree_linked/$worktree_git_dir" ;;
esac
case "$worktree_git_dir" in
  "$worktree_main"/.git/worktrees/*) worktree_git_dir_outside_worktree=1 ;;
  *) worktree_git_dir_outside_worktree=0 ;;
esac
run_test "worktree_git_dir_resolves_outside_worktree" "1" "$worktree_git_dir_outside_worktree"

old_style_lock_parent="$worktree_linked/.git/component-release-cleanup-locks"
if mkdir -p "$old_style_lock_parent" 2>/dev/null; then
  old_style_lock_status=0
else
  old_style_lock_status=$?
fi
run_test "worktree_old_style_lock_mkdir_fails" "1" "$([ "$old_style_lock_status" -eq 0 ] && echo 0 || echo 1)"

fixed_lock_parent="$worktree_git_dir/component-release-cleanup-locks"
if mkdir -p "$fixed_lock_parent" 2>/dev/null; then
  fixed_lock_status=0
else
  fixed_lock_status=$?
fi
run_test "worktree_fixed_lock_mkdir_succeeds" "0" "$fixed_lock_status"

repo_from_changelog="$(fixture_repo from-changelog)"
result="$(run_cleanup "$repo_from_changelog" v1.17.0 --from-changelog)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_from_changelog_exits_nonzero" "1" "$status"
run_contains "linear_from_changelog_action" "TRACKER_ACTION=linear_mcp_or_api_required" "$output"
run_contains "linear_from_changelog_incomplete" "TRACKER_INCOMPLETE=1 REASON=linear_status_transition_required" "$output"
run_contains "linear_from_changelog_issues" "TRACKER_ISSUES=LEA-132,LEA-133,LEA-134,LEA-140" "$output"

repo_best_effort="$(fixture_repo best-effort)"
result="$(run_cleanup "$repo_best_effort" v1.17.0 --from-changelog --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_best_effort_exits_zero" "0" "$status"
run_contains "linear_best_effort_still_reports_action" "TRACKER_ACTION=linear_mcp_or_api_required" "$output"

repo_custom_branch="$(fixture_repo custom-branch)"
result="$(run_cleanup "$repo_custom_branch" mobile-app/release/v1.18.0 --backport-base release-base --issue LEA-200 --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "custom_release_branch_exits_zero" "0" "$status"
run_contains "custom_release_branch_preserved" "Release branch: mobile-app/release/v1.18.0" "$output"
run_contains "custom_release_version_basename" "Release version: v1.18.0" "$output"
run_contains "custom_release_backport_base" "Backport base: release-base" "$output"
run_contains "custom_release_merged_prs" "Merged PRs verified (main #400, release-base #401)." "$output"

repo_nested_release_branch="$(fixture_repo nested-release-branch)"
result="$(run_cleanup "$repo_nested_release_branch" release/mobile-app/v1.18.0 --backport-base release-base --issue LEA-201 --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "nested_release_branch_exits_zero" "0" "$status"
run_contains "nested_release_branch_preserved" "Release branch: release/mobile-app/v1.18.0" "$output"
run_contains "nested_release_version_basename" "Release version: v1.18.0" "$output"
run_contains "nested_release_merged_prs" "Merged PRs verified (main #402, release-base #403)." "$output"

fixture_component_cleanup_repo() {
  local name="$1"
  local path="$TMP_ROOT/$name"
  local product_path="$TMP_ROOT/mobile-app"
  mkdir -p "$path/scripts/development-workflow" "$product_path/.git"
  cp "$REPO_ROOT/scripts/development-workflow/workflow-lib.sh" "$path/scripts/development-workflow/workflow-lib.sh"
  cp "$REPO_ROOT/scripts/development-workflow/prepare-release-post-merge-cleanup.sh" "$path/scripts/development-workflow/prepare-release-post-merge-cleanup.sh"
  cp "$REPO_ROOT/scripts/development-workflow/component-release-target.sh" "$path/scripts/development-workflow/component-release-target.sh"
  cp "$REPO_ROOT/scripts/development-workflow/workflow-config-resolver.py" "$path/scripts/development-workflow/workflow-config-resolver.py"
  chmod +x "$path/scripts/development-workflow/"*.sh
  cat > "$path/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
mode: workflow_hub
issue_tracker:
  provider: linear

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
YAML
  cat > "$path/.ai-dev-workflow.local.yaml" <<'YAML'
product_repos:
  - name: mobile-app
    local_path: ../mobile-app
YAML
  (
    cd "$path"
    target_json="$(./scripts/development-workflow/component-release-target.sh --repo-root "$path" --repo mobile-app --release-branch mobile-app/release/v1.18.0 --json)"
    jq -nS --argjson target "$target_json" \
      '{
        schema_version:"component_release_evidence.v1",
        target_binding:$target,
        release_branch:"mobile-app/release/v1.18.0",
        release_outcome:"completed",
        ci_outcome:"passed",
        deployment_outcome:"recorded",
        cleanup_outcome:"not_started",
        hub_tracker_ref:"#1356"
      }' > "$path/component-release-evidence.json"
  )
  printf '%s\n' "$path"
}

repo_component_cleanup="$(fixture_component_cleanup_repo component-cleanup)"
result="$(run_cleanup "$repo_component_cleanup" --repo mobile-app --repo-root "$repo_component_cleanup" --evidence-file "$repo_component_cleanup/component-release-evidence.json" --issue LEA-210 --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "component_cleanup_exits_zero" "0" "$status"
run_contains "component_cleanup_target_logged" "Component release target: mobile-app (example/mobile-app)" "$output"
run_contains "component_cleanup_branch_from_evidence" "Release branch: mobile-app/release/v1.18.0" "$output"
run_contains "component_cleanup_product_prs" "Merged PRs verified (main #500, release-base #501)." "$output"
run_contains "component_cleanup_remote_delete" "Deleting remote branch 'mobile-app/release/v1.18.0'" "$output"
run_contains "component_cleanup_local_delete" "Deleting local branch 'mobile-app/release/v1.18.0'" "$output"
run_contains "component_cleanup_linear_action" "TRACKER_ACTION=linear_mcp_or_api_required" "$output"

complete_evidence="$repo_component_cleanup/component-release-evidence-complete.json"
jq '.cleanup_outcome = "complete"' \
  "$repo_component_cleanup/component-release-evidence.json" > "$complete_evidence"
result="$(run_cleanup "$repo_component_cleanup" --repo mobile-app --repo-root "$repo_component_cleanup" --evidence-file "$complete_evidence" --issue LEA-212 --best-effort --json)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "component_cleanup_complete_exits_zero" "0" "$status"
run_contains "component_cleanup_complete_idempotent" "Component release cleanup evidence is already complete" "$output"
run_contains "component_cleanup_complete_json" '"cleanup_outcome":"already_complete"' "$output"

target_json="$repo_component_cleanup/component-release-target.json"
(cd "$repo_component_cleanup" && ./scripts/development-workflow/component-release-target.sh --repo-root "$repo_component_cleanup" --repo mobile-app --release-branch mobile-app/release/v1.18.0 --json > "$target_json")
lock_key="$(printf '%s' "$(jq -r '.release_correlation_key' "$target_json")" | tr -c 'A-Za-z0-9._-' '_')"
mkdir -p "$repo_component_cleanup/.git/component-release-cleanup-locks/$lock_key.lock"
result="$(run_cleanup "$repo_component_cleanup" --repo mobile-app --repo-root "$repo_component_cleanup" --evidence-file "$repo_component_cleanup/component-release-evidence.json" --issue LEA-213 --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "component_cleanup_lock_exits_nonzero" "1" "$status"
run_contains "component_cleanup_lock_rejected" "Component release cleanup lock is already held" "$output"
rmdir "$repo_component_cleanup/.git/component-release-cleanup-locks/$lock_key.lock"

# The lock is keyed under the hub checkout's git-dir, not the product
# checkout's, so it excludes a concurrent run that resolves the product repo
# to a *different* local checkout of the same hub (e.g. a second clone or
# worktree) -- not just a second run against the identical product path.
# Build a second, distinct product checkout for the same hub and evidence
# (same release_correlation_key) and confirm the pre-held hub-scoped lock
# still blocks it.
second_product_checkout="$TMP_ROOT/mobile-app-checkout-b"
mkdir -p "$second_product_checkout/.git"
second_local_override="$repo_component_cleanup/.ai-dev-workflow.local.yaml"
cp "$second_local_override" "$second_local_override.orig"
cat > "$second_local_override" <<YAML
product_repos:
  - name: mobile-app
    local_path: $second_product_checkout
YAML
mkdir -p "$repo_component_cleanup/.git/component-release-cleanup-locks/$lock_key.lock"
result="$(run_cleanup "$repo_component_cleanup" --repo mobile-app --repo-root "$repo_component_cleanup" --evidence-file "$repo_component_cleanup/component-release-evidence.json" --issue LEA-2131 --best-effort)"
status="$(printf '%s
' "$result" | sed -n '1p')"
output="$(printf '%s
' "$result" | sed '1d')"
echo "DEBUG_OUTPUT: $output" >&2
run_test "component_cleanup_shared_lock_exits_nonzero" "1" "$status"
run_contains "component_cleanup_shared_lock_rejected" "Component release cleanup lock is already held" "$output"
rmdir "$repo_component_cleanup/.git/component-release-cleanup-locks/$lock_key.lock"
mv "$second_local_override.orig" "$second_local_override"

result="$(run_cleanup "$repo_component_cleanup" mobile-app/release/v9.9.9 --repo mobile-app --repo-root "$repo_component_cleanup" --evidence-file "$repo_component_cleanup/component-release-evidence.json" --issue LEA-214 --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "component_cleanup_branch_mismatch_exits_nonzero" "1" "$status"
run_contains "component_cleanup_branch_mismatch_rejected" "Component release evidence release_branch mismatch" "$output"

repo_invalid_identity="$(fixture_component_cleanup_repo component-invalid-identity)"
python3 - "$repo_invalid_identity/.ai-dev-workflow.yaml" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
path.write_text(text.replace("github_repo: example/mobile-app", "github_repo: bad/repo/slug"), encoding="utf-8")
PY
(
  cd "$repo_invalid_identity"
  target_json="$(./scripts/development-workflow/component-release-target.sh --repo-root "$repo_invalid_identity" --repo mobile-app --release-branch mobile-app/release/v1.18.0 --json)"
  jq -nS --argjson target "$target_json" \
    '{
      schema_version:"component_release_evidence.v1",
      target_binding:$target,
      release_branch:"mobile-app/release/v1.18.0",
      release_outcome:"completed",
      ci_outcome:"passed",
      deployment_outcome:"recorded",
      cleanup_outcome:"not_started",
      hub_tracker_ref:"#1356"
    }' > "$repo_invalid_identity/component-release-evidence.json"
)
result="$(run_cleanup "$repo_invalid_identity" --repo mobile-app --repo-root "$repo_invalid_identity" --evidence-file "$repo_invalid_identity/component-release-evidence.json" --issue LEA-215 --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "component_cleanup_invalid_identity_exits_nonzero" "1" "$status"
run_contains "component_cleanup_invalid_identity_rejected" "COMPONENT_CLEANUP_ERROR=invalid_repository_identity" "$output"

mismatch_evidence="$repo_component_cleanup/component-release-evidence-mismatch.json"
jq '.target_binding.contract_revision = "sha256:mismatch"' \
  "$repo_component_cleanup/component-release-evidence.json" > "$mismatch_evidence"
result="$(run_cleanup "$repo_component_cleanup" --repo mobile-app --repo-root "$repo_component_cleanup" --evidence-file "$mismatch_evidence" --issue LEA-211 --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "component_cleanup_mismatch_exits_nonzero" "1" "$status"
run_contains "component_cleanup_rejects_mismatch" "Component release evidence mismatch for .contract_revision" "$output"

repo_bad_backport_base="$(fixture_repo bad-backport-base)"
result="$(run_cleanup "$repo_bad_backport_base" v1.17.0 --backport-base "bad branch" --issue LEA-202)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "bad_backport_base_exits_usage" "2" "$status"
run_contains "bad_backport_base_rejected" "Invalid backport base branch name: bad branch" "$output"

repo_missing_scope="$(fixture_repo missing-scope)"
result="$(run_cleanup "$repo_missing_scope" v1.17.0)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "missing_scope_exits_nonzero" "1" "$status"
run_contains "missing_scope_signal" "TRACKER_INCOMPLETE=1 REASON=no_issue_scope" "$output"

repo_missing_version="$(fixture_repo missing-version)"
result="$(run_cleanup "$repo_missing_version" v9.9.9 --from-changelog)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "missing_changelog_version_exits_nonzero" "1" "$status"
run_contains "missing_changelog_version_signal" "TRACKER_INCOMPLETE=1 REASON=changelog_scope_unavailable" "$output"

echo ""
echo "=== Issue loop / TRACKER_UPDATED counting (stub workflow-lib.sh) ==="
#
# These tests verify how prepare-release-post-merge-cleanup.sh classifies the
# output of update_tracker_status_best_effort when processing individual issues.
# A stub workflow-lib.sh is used so the test controls exactly what
# update_tracker_status_best_effort emits without requiring live GitHub API calls.
#
# The stub uses a STUB_TRACKER_OUT environment variable to control the
# update_tracker_status_best_effort return value for each fixture run.

fixture_repo_issue_loop() {
  local name="$1"
  local path="$TMP_ROOT/$name"
  mkdir -p "$path/scripts/development-workflow"
  # The real cleanup script is used; workflow-lib.sh is a stub.
  cp "$REPO_ROOT/scripts/development-workflow/prepare-release-post-merge-cleanup.sh" \
     "$path/scripts/development-workflow/prepare-release-post-merge-cleanup.sh"
  chmod +x "$path/scripts/development-workflow/prepare-release-post-merge-cleanup.sh"
  cat > "$path/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
issue_tracker:
  provider: github_projects
  project_number: 1
YAML
  # Stub workflow-lib.sh: provides the bare-minimum functions needed for the
  # cleanup script's issue loop. update_tracker_status_best_effort returns
  # the value of STUB_TRACKER_OUT (set per test run) so each branch of the
  # pattern-matching block can be exercised independently.
  cat > "$path/scripts/development-workflow/workflow-lib.sh" <<'STUB_LIB'
#!/usr/bin/env bash
# Stub workflow-lib.sh for test-prepare-release-tracker-cleanup.sh
cd_workflow_repo_root() { return 0; }
require_gh() { return 0; }
workflow_issue_tracker_provider_raw() { printf 'github_projects\n'; }
workflow_normalize_issue_tracker_provider() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
workflow_issue_tracker_project_number() { printf '1\n'; }
record_release_for_issue_best_effort() {
  local issue="$1" version="$2"
  printf 'RELEASE_STAMP_SKIPPED issue=%s version=%s provider=github_projects reason=no_milestone\n' \
    "$issue" "$version"
}
update_tracker_status_best_effort() {
  # Return the canned output controlled by the test harness.
  printf '%s\n' "${STUB_TRACKER_OUT:-Warning: STUB_TRACKER_OUT not set; skipping.}"
}
STUB_LIB
  printf '%s\n' "$path"
}

# Helper: run cleanup on a stub-lib fixture repo and return "exit_code\noutput".
run_cleanup_stub() {
  local repo="$1"
  shift
  local output=""
  local status=0
  set +e
  output="$(cd "$repo" && ./scripts/development-workflow/prepare-release-post-merge-cleanup.sh "$@" 2>&1)"
  status=$?
  set -e
  printf '%s\n%s\n' "$status" "$output"
}

# Test A: "Updating tracker status..." -> UPDATED=1
stub_repo_updated="$(fixture_repo_issue_loop stub-updated)"
result="$(STUB_TRACKER_OUT="Updating tracker status for issue 200 to Released..." \
  run_cleanup_stub "$stub_repo_updated" v1.18.0 --issue 200 --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "stub_updated_exits_zero" "0" "$status"
run_contains "stub_updated_counter" "UPDATED=1 SKIPPED=0 FAILED=0" "$output"

# Test B: "TRACKER_ACTION_REQUIRED=set_status..." -> UPDATED=1 (deferred action
# is counted as updated so the orchestrator knows it must apply it via MCP).
stub_repo_deferred="$(fixture_repo_issue_loop stub-deferred)"
result="$(STUB_TRACKER_OUT="TRACKER_ACTION_REQUIRED=set_status issue=200 target_status=Released" \
  run_cleanup_stub "$stub_repo_deferred" v1.18.0 --issue 200 --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "stub_deferred_exits_zero" "0" "$status"
run_contains "stub_deferred_counter" "UPDATED=1 SKIPPED=0 FAILED=0" "$output"

# Test C: "Warning: ..." -> SKIPPED=1
stub_repo_skipped="$(fixture_repo_issue_loop stub-skipped)"
result="$(STUB_TRACKER_OUT="Warning: issue #200 not found in project #1; skipping tracker status update." \
  run_cleanup_stub "$stub_repo_skipped" v1.18.0 --issue 200 --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "stub_skipped_exits_zero" "0" "$status"
run_contains "stub_skipped_counter" "UPDATED=0 SKIPPED=1 FAILED=0" "$output"

echo ""
echo "=== Component cleanup --json (real end-to-end, not a fixture) ==="
#
# Reproduces the documented component-release smoke flow
# (docs/testing/workflow/1356-route-component-releases-to-selected-product-repository.smoke-test.md)
# end to end: a real product repo + real bare remote (real git branch
# create/delete, not mocked git), real component-release-target.sh /
# evidence JSON, and only gh + workflow-lib.sh's tracker calls stubbed
# (github_projects tracker mutation requires live GitHub API access this
# harness cannot provide). This is the level of fixture-avoidance the
# reported bug needed to surface: a hand-built fixture masked it before.

e2e_root="$TMP_ROOT/component-json-e2e"
mkdir -p "$e2e_root"
"$REAL_GIT" init -q --bare "$e2e_root/origin.git"
mkdir -p "$e2e_root/mobile-app"
"$REAL_GIT" -C "$e2e_root/mobile-app" init -q -b main
"$REAL_GIT" -C "$e2e_root/mobile-app" config user.email test@example.com
"$REAL_GIT" -C "$e2e_root/mobile-app" config user.name test
"$REAL_GIT" -C "$e2e_root/mobile-app" commit -q --allow-empty -m init
"$REAL_GIT" -C "$e2e_root/mobile-app" remote add origin "$e2e_root/origin.git"
"$REAL_GIT" -C "$e2e_root/mobile-app" push -q origin main
"$REAL_GIT" -C "$e2e_root/mobile-app" checkout -q -b release-base
"$REAL_GIT" -C "$e2e_root/mobile-app" push -q origin release-base
"$REAL_GIT" -C "$e2e_root/mobile-app" checkout -q -b mobile-app/release/v1.0.0
"$REAL_GIT" -C "$e2e_root/mobile-app" commit -q --allow-empty -m release
"$REAL_GIT" -C "$e2e_root/mobile-app" push -q origin mobile-app/release/v1.0.0
"$REAL_GIT" -C "$e2e_root/mobile-app" checkout -q main

mkdir -p "$e2e_root/hub/scripts/development-workflow" "$e2e_root/hub/bin"
"$REAL_GIT" init -q "$e2e_root/hub"
cp "$REPO_ROOT/scripts/development-workflow/prepare-release-post-merge-cleanup.sh"   "$e2e_root/hub/scripts/development-workflow/prepare-release-post-merge-cleanup.sh"
cp "$REPO_ROOT/scripts/development-workflow/component-release-target.sh"   "$e2e_root/hub/scripts/development-workflow/component-release-target.sh"
cp "$REPO_ROOT/scripts/development-workflow/workflow-config-resolver.py"   "$e2e_root/hub/scripts/development-workflow/workflow-config-resolver.py"
chmod +x "$e2e_root/hub/scripts/development-workflow/"*.sh

cat > "$e2e_root/hub/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
mode: workflow_hub
issue_tracker:
  provider: github_projects
  project_number: 1

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
YAML
cat > "$e2e_root/hub/.ai-dev-workflow.local.yaml" <<YAML
product_repos:
  - name: mobile-app
    local_path: ../mobile-app
YAML

cat > "$e2e_root/hub/bin/gh" <<'SH'
#!/usr/bin/env bash
case "$*" in
  "pr list --repo example/mobile-app --state merged --head mobile-app/release/v1.0.0 --base main --json number --jq .[0].number // empty")
    printf '900
' ;;
  "pr list --repo example/mobile-app --state merged --head mobile-app/release/v1.0.0 --base release-base --json number --jq .[0].number // empty")
    printf '901
' ;;
  "pr list --repo example/mobile-app --state open --head mobile-app/release/v1.0.0 --base main --json number --jq .[0].number // empty")
    printf '
' ;;
  "pr list --repo example/mobile-app --state open --head mobile-app/release/v1.0.0 --base release-base --json number --jq .[0].number // empty")
    printf '
' ;;
  "issue view 1358 --json state --jq .state")
    printf 'OPEN
' ;;
  *)
    echo "unexpected gh invocation: $*" >&2
    exit 64
    ;;
esac
SH
chmod +x "$e2e_root/hub/bin/gh"

cat > "$e2e_root/hub/scripts/development-workflow/workflow-lib.sh" <<'STUB'
#!/usr/bin/env bash
cd_workflow_repo_root() { return 0; }
require_gh() { return 0; }
workflow_issue_tracker_provider_raw() { printf 'github_projects
'; }
workflow_normalize_issue_tracker_provider() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
workflow_issue_tracker_project_number() { printf '1
'; }
workflow_is_valid_github_owner() {
  case "$1" in
    ''|-*|*-|*[!A-Za-z0-9-]*) return 1 ;;
  esac
  return 0
}
workflow_is_valid_github_repo_name() {
  case "$1" in
    ''|'.'|'..'|*[!A-Za-z0-9._-]*) return 1 ;;
  esac
  return 0
}
workflow_is_valid_github_repo_slug() {
  local repo_slug="$1"
  local owner="${repo_slug%%/*}"
  local repo_name="${repo_slug#*/}"
  [ "$owner/$repo_name" = "$repo_slug" ] || return 1
  workflow_is_valid_github_owner "$owner" || return 1
  workflow_is_valid_github_repo_name "$repo_name" || return 1
  return 0
}
record_release_for_issue_best_effort() {
  local issue="$1" version="$2"
  printf 'RELEASE_STAMP_SKIPPED issue=%s version=%s provider=github_projects reason=no_milestone\n' "$issue" "$version"
}
update_tracker_status_best_effort() {
  printf 'Updating tracker status for issue %s to Released...\n' "$1"
}
STUB

(
  cd "$e2e_root/hub"
  e2e_target_json="$(./scripts/development-workflow/component-release-target.sh --repo-root "$PWD" --repo mobile-app --release-branch mobile-app/release/v1.0.0 --json)"
  jq -nS --argjson target "$e2e_target_json"     '{schema_version:"component_release_evidence.v1",target_binding:$target,release_branch:"mobile-app/release/v1.0.0",
      release_outcome:"completed",ci_outcome:"passed",deployment_outcome:"recorded",cleanup_outcome:"not_started",
      hub_tracker_ref:"#1356",component_tag:"mobile-v1.0.0"}' > component-release-evidence.json
)

# The mock bin directory must precede the real git directory on PATH. It held
# only a mock gh, and this previously read "$(dirname "$REAL_GIT"):$PWD/bin",
# which shadows that mock wherever git and gh share a directory: false on
# macOS (Homebrew puts gh in /opt/homebrew/bin), true on GitHub's
# ubuntu-latest runners, where both are /usr/bin. There the real gh ran
# instead of the mock and the cleanup exited 4. git still resolves from the
# real git directory because only gh is mocked. Surfaced once this suite began
# running in CI (issue #1537).
e2e_output="$e2e_root/hub/cleanup-output.json"
e2e_stderr="$e2e_root/hub/cleanup-stderr.log"
e2e_status=0
(
  cd "$e2e_root/hub"
  PATH="$PWD/bin:$(dirname "$REAL_GIT"):$PATH" WORKFLOW_SKIP_FETCH=1 ./scripts/development-workflow/prepare-release-post-merge-cleanup.sh     mobile-app/release/v1.0.0 --repo mobile-app --repo-root "$PWD"     --evidence-file "$PWD/component-release-evidence.json" --issue 1358 --json
) > "$e2e_output" 2> "$e2e_stderr" || e2e_status=$?

run_test "e2e_json_exits_zero" "0" "$e2e_status"
run_test "e2e_json_stdout_is_valid_json" "0" "$(jq empty "$e2e_output" >/dev/null 2>&1; echo $?)"
run_test "e2e_json_cleanup_outcome" "complete" "$(jq -r '.cleanup_outcome' "$e2e_output")"
run_test "e2e_json_remote_branch_deleted" "true" "$(jq -r '.product_cleanup.remote_branch_deleted' "$e2e_output")"
run_test "e2e_json_local_branch_deleted" "true" "$(jq -r '.product_cleanup.local_branch_deleted' "$e2e_output")"
run_test "e2e_json_tracker_after_product_cleanup" "true" "$(jq -r '.tracker_mutation.after_product_cleanup' "$e2e_output")"
run_test "e2e_json_tracker_repository_owner" "hub_repository" "$(jq -r '.tracker_mutation.repository_owner' "$e2e_output")"
run_test "e2e_json_no_stray_stdout_text" "0" "$(grep -c '^[A-Za-z].*[^}]$' "$e2e_output" 2>/dev/null || true)"

# Rerun: no new branch action needed (already deleted), still valid JSON,
# reported as an idempotent no-op cleanup.
e2e_rerun_output="$e2e_root/hub/cleanup-rerun-output.json"
(
  cd "$e2e_root/hub"
  PATH="$PWD/bin:$(dirname "$REAL_GIT"):$PATH" WORKFLOW_SKIP_FETCH=1 ./scripts/development-workflow/prepare-release-post-merge-cleanup.sh     mobile-app/release/v1.0.0 --repo mobile-app --repo-root "$PWD"     --evidence-file "$PWD/component-release-evidence.json" --issue 1358 --json
) > "$e2e_rerun_output" 2>/dev/null || true
run_test "e2e_json_rerun_valid_json" "0" "$(jq empty "$e2e_rerun_output" >/dev/null 2>&1; echo $?)"
run_test "e2e_json_rerun_already_complete" "true" "$(jq -r '.product_cleanup.already_complete' "$e2e_rerun_output")"
run_test "e2e_json_rerun_no_new_remote_delete" "false" "$(jq -r '.product_cleanup.remote_branch_deleted' "$e2e_rerun_output")"

echo "=== Milestone stamping fix: uses API number not title ==="

# Create a separate mock bin for github_projects milestone tests.
# This bin verifies that the milestone assignment uses the REST API with the
# milestone number (not 'gh issue edit --milestone <title>'), which works for
# closed milestones.
MILESTONE_BIN="$TMP_ROOT/milestone-bin"
mkdir -p "$MILESTONE_BIN"

cat > "$MILESTONE_BIN/gh" <<'MOCK_GH_MILESTONE'
#!/usr/bin/env bash
case "$*" in
  "auth status")
    exit 0
    ;;
  # record_release_for_issue_best_effort: list milestones to get number
  "api --paginate --slurp repos/test-owner/test-repo/milestones?state=all&per_page=100")
    printf '[{"number":42,"title":"v1.17.0","state":"closed"}]\n'
    ;;
  # repo owner/name lookups
  "repo view --json owner --jq .owner.login")
    printf 'test-owner\n'
    ;;
  "repo view --json name --jq .name")
    printf 'test-repo\n'
    ;;
  # The NEW path: REST API PATCH with milestone number (not title)
  "api -X PATCH repos/test-owner/test-repo/issues/101 -F milestone=42")
    printf '{"number":101,"milestone":{"number":42}}\n'
    ;;
  "issue view 101 --json state --jq .state")
    printf 'closed\n'
    ;;
  # PR verification
  "pr list --state merged --head release/v1.17.0 --base main --json number --jq .[0].number // empty")
    printf '333\n'
    ;;
  "pr list --state merged --head release/v1.17.0 --base develop --json number --jq .[0].number // empty")
    printf '334\n'
    ;;
  "pr list --state open --head release/v1.17.0 --base main --json number --jq .[0].number // empty")
    printf '\n'
    ;;
  "pr list --state open --head release/v1.17.0 --base develop --json number --jq .[0].number // empty")
    printf '\n'
    ;;
  # detect_omitted_merged_items: project ID lookup via GraphQL (user query first, org fallback)
  *"user(login"*"projectV2"*)
    printf '{"data":{"user":{"projectV2":{"id":"PVT_test000001"}}}}\n'
    ;;
  *"organization(login"*"projectV2"*)
    printf '{"data":{"organization":{"projectV2":{"id":"PVT_test000001"}}}}\n'
    ;;
  # detect_omitted_merged_items: paginated project items (no extra Merged items)
  *"projectId"*"ProjectV2"*"items"*)
    printf '{"data":{"node":{"items":{"nodes":[],"pageInfo":{"hasNextPage":false,"endCursor":""}}}}}\n'
    ;;
  # Tracker status update for issue 101: project item lookup (skip silently)
  "api graphql"*)
    printf '{"data":{"repository":{"issue":{"projectItems":{"nodes":[],"pageInfo":{"hasNextPage":false,"endCursor":""}}}}}}\n'
    ;;
  # detect_omitted_merged_items: release tag date
  "api repos/test-owner/test-repo/releases/tags/v1.17.0 --jq .published_at // .created_at // empty")
    printf '2026-06-11T12:00:00Z\n'
    ;;
  # detect_omitted_merged_items: tag list for previous-tag resolution
  "api repos/test-owner/test-repo/tags?per_page=100 --paginate --jq [.[] | select(.name | test(\"^v?[0-9]+\\.[0-9]+\\.[0-9]+\"))] | .[].name")
    printf 'v1.17.0\nv1.16.0\n'
    ;;
  # detect_omitted_merged_items: previous release date
  "api repos/test-owner/test-repo/releases/tags/v1.16.0 --jq .published_at // .created_at // empty")
    printf '2026-06-01T12:00:00Z\n'
    ;;
  *)
    printf 'unexpected gh invocation: gh %s\n' "$*" >&2
    exit 64
    ;;
esac
MOCK_GH_MILESTONE

cat > "$MILESTONE_BIN/git" <<'MOCK_GIT_MILESTONE'
#!/usr/bin/env bash
case "$*" in
  "fetch origin --prune") exit 0 ;;
  "ls-remote --exit-code --heads origin release/v1.17.0") exit 2 ;;
  "show-ref --quiet refs/heads/release/v1.17.0") exit 1 ;;
  "remote get-url origin") printf 'https://github.com/test-owner/test-repo.git\n' ;;
  # detect_omitted_merged_items fallback: tag annotation dates (not needed when gh api succeeds)
  *) exit 0 ;;
esac
MOCK_GIT_MILESTONE

chmod +x "$MILESTONE_BIN/gh" "$MILESTONE_BIN/git"

fixture_github_projects_repo() {
  local name="$1"
  local path="$TMP_ROOT/$name"
  mkdir -p "$path/scripts/development-workflow"
  cp "$REPO_ROOT/scripts/development-workflow/workflow-lib.sh" "$path/scripts/development-workflow/workflow-lib.sh"
  cp "$REPO_ROOT/scripts/development-workflow/prepare-release-post-merge-cleanup.sh" "$path/scripts/development-workflow/prepare-release-post-merge-cleanup.sh"
  chmod +x "$path/scripts/development-workflow/prepare-release-post-merge-cleanup.sh"
  cat > "$path/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
issue_tracker:
  provider: github_projects
  project_number: 1
YAML
  cat > "$path/CHANGELOG.md" <<'MD'
# Changelog

## [Unreleased]

## [1.17.0] - 2026-06-11

### Fixed

- Fixed some bug (#101).

## [1.16.0] - 2026-06-01

- Older entry (#99).
MD
  printf '%s\n' "$path"
}

run_cleanup_with_bin() {
  local bin_dir="$1"
  local repo="$2"
  shift 2
  local output="" status=0
  set +e
  output="$(cd "$repo" && PATH="${bin_dir}:$PATH" ./scripts/development-workflow/prepare-release-post-merge-cleanup.sh "$@" 2>&1)"
  status=$?
  set -e
  printf '%s\n%s\n' "$status" "$output"
}

repo_milestone="$(fixture_github_projects_repo milestone-stamp)"
result="$(run_cleanup_with_bin "$MILESTONE_BIN" "$repo_milestone" v1.17.0 --from-changelog --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "milestone_stamp_exits_zero" "0" "$status"
run_contains "milestone_stamp_release_stamped" "RELEASE_STAMPED issue=101" "$output"

echo ""
echo "=== Omitted merged items detection ==="

# Test: --from-changelog with github_projects; no extra Merged items in project.
# Expects: no OMITTED_MERGED_ITEMS_DETECTED signal.
run_contains "no_extra_merged_items_clean" \
  "Omitted-merged-items check: no additional Merged items found" \
  "$output"

# Test: detect_omitted_merged_items when a Merged project item is NOT in changelog scope.
# Two sub-cases: item with a merged PR (regular shipped item) and item without (parent epic).

DETECT_BIN="$TMP_ROOT/detect-bin"
mkdir -p "$DETECT_BIN"

cat > "$DETECT_BIN/gh" <<'MOCK_GH_DETECT'
#!/usr/bin/env bash
case "$*" in
  "auth status") exit 0 ;;
  "repo view --json owner --jq .owner.login") printf 'test-owner\n' ;;
  "repo view --json name --jq .name") printf 'test-repo\n' ;;
  "remote get-url origin") printf 'https://github.com/test-owner/test-repo.git\n' ;;
  # PR verification for release branch
  "pr list --state merged --head release/v1.17.0 --base main --json number --jq .[0].number // empty")
    printf '333\n' ;;
  "pr list --state merged --head release/v1.17.0 --base develop --json number --jq .[0].number // empty")
    printf '334\n' ;;
  "pr list --state open --head release/v1.17.0 --base main --json number --jq .[0].number // empty")
    printf '\n' ;;
  "pr list --state open --head release/v1.17.0 --base develop --json number --jq .[0].number // empty")
    printf '\n' ;;
  # detect_omitted_merged_items: project ID lookup via GraphQL
  *"user(login"*"projectV2"*)
    printf '{"data":{"user":{"projectV2":{"id":"PVT_test000002"}}}}\n' ;;
  *"organization(login"*"projectV2"*)
    printf '{"data":{"organization":{"projectV2":{"id":"PVT_test000002"}}}}\n' ;;
  # detect_omitted_merged_items: paginated project items.
  # Returns TWO extra Merged items beyond issue #101 (which is in changelog scope):
  #   #200 — has a merged PR (regular shipped item)
  #   #201 — no merged PR (parent epic)
  *"projectId"*"ProjectV2"*"items"*)
    printf '{"data":{"node":{"items":{"nodes":[{"type":"ISSUE","content":{"__typename":"Issue","number":101},"status":{"name":"Merged"}},{"type":"ISSUE","content":{"__typename":"Issue","number":200},"status":{"name":"Merged"}},{"type":"ISSUE","content":{"__typename":"Issue","number":201},"status":{"name":"Merged"}},{"type":"ISSUE","content":{"__typename":"Issue","number":99},"status":{"name":"Released"}}],"pageInfo":{"hasNextPage":false,"endCursor":""}}}}}\n' ;;
  # detect_omitted_merged_items: issue timeline for #200 — merged PR #500 references it
  *"num=200"*"timelineItems"*|*"num = 200"*"timelineItems"*)
    printf '{"data":{"repository":{"issue":{"timelineItems":{"nodes":[{"__typename":"CrossReferencedEvent","source":{"__typename":"PullRequest","number":500,"merged":true,"baseRefName":"develop","mergeCommit":{"oid":"aaaa111shipped"}}}],"pageInfo":{"hasNextPage":false,"endCursor":""}}}}}}\n' ;;
  # detect_omitted_merged_items: issue timeline for #201 — no merged PR
  *"num=201"*"timelineItems"*|*"num = 201"*"timelineItems"*)
    printf '{"data":{"repository":{"issue":{"timelineItems":{"nodes":[],"pageInfo":{"hasNextPage":false,"endCursor":""}}}}}}\n' ;;
  # Release tag dates
  "api repos/test-owner/test-repo/releases/tags/v1.17.0 --jq .published_at // .created_at // empty")
    printf '2026-06-11T12:00:00Z\n' ;;
  "api repos/test-owner/test-repo/tags?per_page=100 --paginate --jq [.[] | select(.name | test(\"^v?[0-9]+\\.[0-9]+\\.[0-9]+\"))] | .[].name")
    printf 'v1.17.0\nv1.16.0\n' ;;
  "api repos/test-owner/test-repo/releases/tags/v1.16.0 --jq .published_at // .created_at // empty")
    printf '2026-06-01T12:00:00Z\n' ;;
  # Issue close dates (both closed in release window)
  "api repos/test-owner/test-repo/issues/200 --jq .closed_at // empty")
    printf '2026-06-10T12:00:00Z\n' ;;
  "api repos/test-owner/test-repo/issues/201 --jq .closed_at // empty")
    printf '2026-06-09T12:00:00Z\n' ;;
  # Milestone lookup for milestone stamping of #101
  "api --paginate --slurp repos/test-owner/test-repo/milestones?state=all&per_page=100")
    printf '[{"number":42,"title":"v1.17.0","state":"closed"}]\n' ;;
  # Milestone stamping for #101 (and auto-added #200)
  "api -X PATCH repos/test-owner/test-repo/issues/101 -F milestone=42")
    printf '{"number":101,"milestone":{"number":42}}\n' ;;
  "api -X PATCH repos/test-owner/test-repo/issues/200 -F milestone=42")
    printf '{"number":200,"milestone":{"number":42}}\n' ;;
  # Tracker status updates (issue view + GraphQL project item lookup)
  "issue view 101 --json state --jq .state") printf 'closed\n' ;;
  "issue view 200 --json state --jq .state") printf 'closed\n' ;;
  "api graphql"*)
    printf '{"data":{"repository":{"issue":{"projectItems":{"nodes":[],"pageInfo":{"hasNextPage":false,"endCursor":""}}}}}}\n' ;;
  *)
    printf 'unexpected gh invocation: gh %s\n' "$*" >&2
    exit 64
    ;;
esac
MOCK_GH_DETECT

cat > "$DETECT_BIN/git" <<'MOCK_GIT_DETECT'
#!/usr/bin/env bash
case "$*" in
  "fetch origin --prune") exit 0 ;;
  "ls-remote --exit-code --heads origin release/v1.17.0") exit 2 ;;
  "show-ref --quiet refs/heads/release/v1.17.0") exit 1 ;;
  "remote get-url origin") printf 'https://github.com/test-owner/test-repo.git\n' ;;
  # #1512: a merge commit that is NOT an ancestor of the release tag — the
  # shape of a PR merged into an in-flight develop-<slug> integration branch.
  "merge-base --is-ancestor bbbb222unshipped"*) exit 1 ;;
  *) exit 0 ;;
esac
MOCK_GIT_DETECT

chmod +x "$DETECT_BIN/gh" "$DETECT_BIN/git"

repo_detect="$(fixture_github_projects_repo detect-omitted)"
result="$(run_cleanup_with_bin "$DETECT_BIN" "$repo_detect" v1.17.0 --from-changelog --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"

# AC-2: Omitted items are detected and reported before closeout.
run_contains "detect_omitted_items_detected_signal" "OMITTED_MERGED_ITEMS_DETECTED" "$output"

# AC-3: Report distinguishes parent epics from regular shipped items.
run_contains "detect_shipped_item_reported" "Regular shipped items" "$output"
run_contains "detect_parent_epic_reported" "Likely parent epics" "$output"
run_contains "detect_parent_epic_label" "#201 (likely parent epic" "$output"

# AC-4: Regular shipped item #200 is auto-added; its stamp appears in output.
run_contains "detect_shipped_item_auto_added" "RELEASE_STAMPED issue=200" "$output"

# AC-4: Parent epic #201 triggers TRACKER_INCOMPLETE.
run_contains "detect_parent_epic_incomplete" "TRACKER_INCOMPLETE=1 REASON=omitted_parent_epics" "$output"

# #1512: an item whose merged PR is NOT an ancestor of the release tag is
# reported but never auto-added. "Has a merged PR" is not "shipped": a PR
# merged into an in-flight develop-<slug> integration branch is merged,
# closed, and inside the release window, yet none of its code is in the tag.
DETECT_UNSHIPPED_BIN="$(mktemp -d)"
cp "$DETECT_BIN/gh" "$DETECT_UNSHIPPED_BIN/gh"
cp "$DETECT_BIN/git" "$DETECT_UNSHIPPED_BIN/git"
# Same fixture, but #200's merged PR carries the non-ancestor merge commit.
sed -i.bak 's/aaaa111shipped/bbbb222unshipped/' "$DETECT_UNSHIPPED_BIN/gh"
rm -f "$DETECT_UNSHIPPED_BIN/gh.bak"
chmod +x "$DETECT_UNSHIPPED_BIN/gh" "$DETECT_UNSHIPPED_BIN/git"
repo_unshipped="$(fixture_github_projects_repo detect-unshipped)"
unshipped_result="$(run_cleanup_with_bin "$DETECT_UNSHIPPED_BIN" "$repo_unshipped" v1.17.0 --from-changelog --best-effort)"
unshipped_output="$(printf '%s\n' "$unshipped_result" | sed '1d')"
run_contains "unshipped_item_is_reported" "#200 [merged PR #500 into develop is not an ancestor of v1.17.0" "$unshipped_output"
run_not_contains "unshipped_item_not_auto_added" "RELEASE_STAMPED issue=200" "$unshipped_output"
run_not_contains "unshipped_item_not_in_shipped_section" "Regular shipped items" "$unshipped_output"
run_contains "unshipped_item_marks_incomplete" "TRACKER_INCOMPLETE=1 REASON=omitted_parent_epics" "$unshipped_output"
rm -rf "$DETECT_UNSHIPPED_BIN"
run_contains "detect_parent_epic_issues_list" "ISSUES=201" "$output"

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"

if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi
