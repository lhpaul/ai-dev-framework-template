#!/usr/bin/env bash
# test-prepare-release-tracker-cleanup.sh - release cleanup tracker scope tests.
#
# Covers:
#   1. Linear provider: --from-changelog without merged-PR evidence skips changelog IDs
#   2. Linear provider: --best-effort with no merged-PR-backed scope exits 0 (no_issue_scope)
#   3. Missing scope (no --issue / --from-changelog): emits no_issue_scope signal
#   4. Missing CHANGELOG version: GitHub providers emit changelog_scope_unavailable;
#      Linear continues with CHANGELOG_SECTION_UNAVAILABLE + merged-PR scope
#   5. Issue loop / TRACKER_UPDATED counting:
#      a. update_tracker_status_best_effort emits "Updating tracker status" -> UPDATED
#      b. update_tracker_status_best_effort emits TRACKER_ACTION_REQUIRED=set_status -> UPDATED
#      c. update_tracker_status_best_effort emits Warning: -> SKIPPED
#   6. Linear #1982: changelog-only / range-expanded IDs skipped; PR headRefName/title
#      IDs proposed (incl. PR-only, hotfix via commits/<sha>/pulls, commit-text false positive)
#   7. github_projects --from-changelog behavior unchanged
#
# Usage: bash scripts/development-workflow/tests/test-prepare-release-tracker-cleanup.sh
# covers: scripts/development-workflow/prepare-release-post-merge-cleanup.sh
# covers: scripts/development-workflow/tests/fixtures/prepare-release-post-merge-cleanup.develop-baseline
# covers: scripts/development-workflow/component-release-target.sh
# covers: scripts/development-workflow/workflow-config-resolver.py
# covers: scripts/development-workflow/workflow-merge-budget.py

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"

TMP_ROOT="$(mktemp -d)"
MOCK_BIN="$TMP_ROOT/bin"
PASS_COUNT=0
FAIL_COUNT=0

_harness_exit() {
  local status=$?
  if [ "${KEEP_TEST_TMP:-}" = "1" ]; then
    echo "KEEP_TEST_TMP=1: leaving $TMP_ROOT" >&2
  else
    rm -rf "$TMP_ROOT"
  fi
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

# Deterministic commit identity for every fixture (incl. clones that never run
# `git config user.*`). CI runners have no global user.name/email; without these
# exports, `$REAL_GIT commit` aborts the suite under `set -e` with
# "empty ident name (for <...>) not allowed".
export GIT_AUTHOR_NAME="${GIT_AUTHOR_NAME:-Workflow Test}"
export GIT_AUTHOR_EMAIL="${GIT_AUTHOR_EMAIL:-workflow-test@example.invalid}"
export GIT_COMMITTER_NAME="${GIT_COMMITTER_NAME:-Workflow Test}"
export GIT_COMMITTER_EMAIL="${GIT_COMMITTER_EMAIL:-workflow-test@example.invalid}"

# Local repo config mirrors the GIT_* exports (belt-and-suspenders for clones
# that re-init or for tooling that ignores the environment).
configure_fixture_git_identity() {
  local path="$1"
  "$REAL_GIT" -C "$path" config user.email "${GIT_AUTHOR_EMAIL}"
  "$REAL_GIT" -C "$path" config user.name "${GIT_AUTHOR_NAME}"
}

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
  if [ "$#" -ne 3 ]; then
    echo "FAIL: run_not_contains called with $# argument(s), expected 3"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    return 0
  fi
  local name="$1"
  local unexpected="$2"
  local actual="$3"
  # grep exits 0 on a match, 1 on no match, and >1 on an actual error (bad
  # pattern, unreadable input). Folding >1 into the else branch reports PASS
  # for an assertion that never ran — the same false pass that let a broken
  # guard test through in #1523. Only status 1 is a confirmed non-match.
  local grep_status=0
  grep -Fq -- "$unexpected" <<< "$actual" || grep_status=$?
  if [ "$grep_status" -eq 0 ]; then
    echo "FAIL: $name - expected output NOT to contain '${unexpected}'"
    printf 'Actual output:\n%s\n' "$actual"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  elif [ "$grep_status" -gt 1 ]; then
    echo "FAIL: $name - grep exited ${grep_status}; the assertion could not be evaluated"
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
configure_fixture_git_identity "$worktree_main"
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
# Without a verified release tag / --release-head, Linear --from-changelog fails
# closed rather than falling back to checkout HEAD (#1982 Step 7a).
run_test "linear_from_changelog_exits_nonzero" "1" "$status"
run_contains "linear_from_changelog_incomplete_without_release_ref" "RELEASE_SCOPE_INCOMPLETE reason=release_ref_unavailable" "$output"
run_contains "linear_from_changelog_scope_unavailable" "TRACKER_INCOMPLETE=1 REASON=changelog_scope_unavailable" "$output"
run_not_contains "linear_from_changelog_does_not_propose_changelog_only" "TRACKER_ISSUES=LEA-132,LEA-133,LEA-134,LEA-140" "$output"

repo_best_effort="$(fixture_repo best-effort)"
result="$(run_cleanup "$repo_best_effort" v1.17.0 --from-changelog --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_best_effort_exits_zero" "0" "$status"
run_contains "linear_best_effort_incomplete_ref" "RELEASE_SCOPE_INCOMPLETE reason=release_ref_unavailable" "$output"
run_contains "linear_best_effort_scope_unavailable" "TRACKER_INCOMPLETE=1 REASON=changelog_scope_unavailable" "$output"
run_not_contains "linear_best_effort_no_false_released_handoff" "TRACKER_ACTION=linear_mcp_or_api_required" "$output"

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
configure_fixture_git_identity "$e2e_root/mobile-app"
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

# --- #1529 trust-boundary cleanup cases (T19-T20g) ---
# Use a fresh branch-bound fixture for empty-identity mutations.
repo_t19="$(fixture_component_cleanup_repo component-cleanup-t19)"
base_evidence="$repo_t19/component-release-evidence.json"
issue_counter=152900

run_empty_identity_case() {
  local name="$1"
  local jq_edit="$2"
  local expected_msg="$3"
  local ev="$repo_t19/evidence-${name}.json"
  local issue_num
  issue_counter=$((issue_counter + 1))
  issue_num="$issue_counter"
  jq "$jq_edit" "$base_evidence" > "$ev"
  local result status output
  result="$(run_cleanup "$repo_t19" --repo mobile-app --repo-root "$repo_t19" --evidence-file "$ev" --issue "$issue_num" --best-effort)"
  status="$(printf '%s\n' "$result" | sed -n '1p')"
  output="$(printf '%s\n' "$result" | sed '1d')"
  run_test "${name}_exits_nonzero" "1" "$status"
  run_contains "${name}_message" "$expected_msg" "$output"
  run_not_contains "${name}_no_branch_delete" "Deleting remote branch" "$output"
}

run_empty_identity_case T19 \
  '.target_binding.contract_revision = ""' \
  "Component release evidence is missing required identity field: contract_revision"

run_empty_identity_case T20 \
  '.target_binding.canonical_repository_identity = ""' \
  "Component release evidence is missing required identity field: canonical_repository_identity"

run_empty_identity_case T20b \
  '.target_binding.release_correlation_key = ""' \
  "Component release evidence is missing required identity field: release_correlation_key"

run_empty_identity_case T20d \
  '.target_binding.routing_outcome = ""' \
  "Component release evidence is missing required identity field: routing_outcome"

run_empty_identity_case T20e \
  '.target_binding.selected_product_repo_key = ""' \
  "Component release evidence is missing required identity field: selected_product_repo_key"

for owner_field in release ci github_release deployment cleanup tracker; do
  run_empty_identity_case "T20f_${owner_field}" \
    ".target_binding.artifact_owners.${owner_field} = \"\"" \
    "Component release evidence is missing required identity field: artifact_owners"
done

# T20c: empty top-level release_branch must reject before correlation mismatch
t20c_ev="$repo_t19/evidence-T20c.json"
jq '.release_branch = ""' "$base_evidence" > "$t20c_ev"
result="$(run_cleanup "$repo_t19" mobile-app/release/v9.9.9 --repo mobile-app --repo-root "$repo_t19" --evidence-file "$t20c_ev" --issue 152920 --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "T20c_exits_nonzero" "1" "$status"
run_contains "T20c_missing_release_branch" "missing required field: release_branch" "$output"
run_not_contains "T20c_not_correlation_mismatch" "release_correlation_key" "$output"
run_not_contains "T20c_no_branch_delete" "Deleting remote branch" "$output"

# T20g: empty / absent cleanup_outcome
t20g_empty="$repo_t19/evidence-T20g-empty.json"
jq '.cleanup_outcome = ""' "$base_evidence" > "$t20g_empty"
result="$(run_cleanup "$repo_t19" --repo mobile-app --repo-root "$repo_t19" --evidence-file "$t20g_empty" --issue 152921 --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "T20g_empty_exits_nonzero" "1" "$status"
run_contains "T20g_empty_message" "missing required field: cleanup_outcome" "$output"
run_not_contains "T20g_empty_no_delete" "Deleting remote branch" "$output"

t20g_absent="$repo_t19/evidence-T20g-absent.json"
jq 'del(.cleanup_outcome)' "$base_evidence" > "$t20g_absent"
result="$(run_cleanup "$repo_t19" --repo mobile-app --repo-root "$repo_t19" --evidence-file "$t20g_absent" --issue 152922 --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "T20g_absent_exits_nonzero" "1" "$status"
run_contains "T20g_absent_message" "missing required field: cleanup_outcome" "$output"
run_not_contains "T20g_absent_no_delete" "Deleting remote branch" "$output"

echo ""
# A legacy complete component attestation cannot bypass an unreadable owning
# journal, even when best-effort was requested. Exercise the actual CLI boundary.
cp "$REPO_ROOT/scripts/development-workflow/workflow-merge-budget.py" \
  "$repo_component_cleanup/scripts/development-workflow/workflow-merge-budget.py"
result="$(run_cleanup "$repo_component_cleanup" --repo mobile-app --repo-root "$repo_component_cleanup" \
  --evidence-file "$complete_evidence" --merge-session "$TMP_ROOT/missing-session/state.json" --best-effort --json)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "session_missing_exits_nonzero_despite_best_effort" "2" "$status"
run_not_contains "session_complete_attestation_cannot_bypass_journal" "exiting idempotently" "$output"
run_not_contains "session_missing_no_branch_delete" "Deleting remote branch" "$output"
run_not_contains "session_missing_no_stamp_mutation" "RELEASE_STAMPED " "$output"

# An explicitly requested but empty session must never fall back to legacy
# cleanup, including a complete attestation and best-effort invocation.
for session_value in "" "--best-effort"; do
  result="$(run_cleanup "$repo_component_cleanup" --repo mobile-app --repo-root "$repo_component_cleanup" \
    --evidence-file "$complete_evidence" --merge-session "$session_value" --best-effort --json)"
  status="$(printf '%s\n' "$result" | sed -n '1p')"
  output="$(printf '%s\n' "$result" | sed '1d')"
  run_test "session_invalid_${session_value}_exits_before_cleanup" "2" "$status"
  run_contains "session_invalid_${session_value}_message" "--merge-session requires a nonempty session path." "$output"
  run_not_contains "session_invalid_${session_value}_no_legacy_shortcut" "exiting idempotently" "$output"
  run_not_contains "session_invalid_${session_value}_no_branch_delete" "Deleting remote branch" "$output"
  run_not_contains "session_invalid_${session_value}_no_stamp_mutation" "RELEASE_STAMPED " "$output"
done

echo ""
echo "=== Linear #1982 release-scope filter (merged PR range) ==="

# Fixture setup still runs under suite-level `set -e`. A hard git failure would
# abort the harness before run_test; GIT_* exports + configure_fixture_git_identity
# keep commits from dying on empty global identity (the CI failure mode).

# Shared Linear fixture helpers: real git for tag/range inspection; stubbed gh
# that resolves PR numbers / commit→PR pulls to headRefName+title only.
LINEAR_SCOPE_BIN="$TMP_ROOT/linear-scope-bin"
LINEAR_SCOPE_MAP="$TMP_ROOT/linear-scope-pr-map"
LINEAR_SCOPE_MAP_FILE="$LINEAR_SCOPE_MAP/current.map"
mkdir -p "$LINEAR_SCOPE_BIN" "$LINEAR_SCOPE_MAP"
# Fixed path so fixtures invoked via $(...) subshells still share the map.
export LINEAR_SCOPE_MAP_FILE

write_linear_scope_gh() {
  # Args: "pr_number|headRefName|title" and optional "commit:<sha>|pr_number".
  # Optional leading "format:rest" makes commits/<sha>/pulls return REST-shaped
  # JSON (head.ref / base.ref / merged_at) so branch-only IDs are exercised.
  : > "$LINEAR_SCOPE_MAP_FILE"
  local entry
  for entry in "$@"; do
    printf '%s\n' "$entry" >> "$LINEAR_SCOPE_MAP_FILE"
  done
  cat > "$LINEAR_SCOPE_BIN/gh" <<'MOCK_GH_LINEAR_SCOPE'
#!/usr/bin/env bash
MAP_FILE="${LINEAR_SCOPE_MAP_FILE:?}"
map_uses_rest_format() {
  grep -qx 'format:rest' "$MAP_FILE" 2>/dev/null
}
# Map line: pr_number|headRefName|title[|baseRefName]
parse_pr_map_line() {
  local rest="$1"
  MAP_HEAD="${rest%%|*}"
  rest="${rest#*|}"
  case "$rest" in
    *\|*)
      MAP_TITLE="${rest%%|*}"
      MAP_BASE="${rest#*|}"
      ;;
    *)
      MAP_TITLE="$rest"
      MAP_BASE="develop"
      ;;
  esac
}
lookup_pr() {
  local num="$1" line rest
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      commit:*|format:*) continue ;;
    esac
    case "$line" in
      "${num}|"*)
        parse_pr_map_line "${line#*|}"
        printf '{"number":%s,"headRefName":"%s","title":"%s","mergedAt":"2026-10-14T12:00:00Z","baseRefName":"%s"}\n' \
          "$num" "$MAP_HEAD" "$MAP_TITLE" "$MAP_BASE"
        return 0
        ;;
    esac
  done < "$MAP_FILE"
  return 1
}
lookup_pr_rest() {
  local num="$1" merge_sha="${2:-}" line rest
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      commit:*|format:*) continue ;;
    esac
    case "$line" in
      "${num}|"*)
        parse_pr_map_line "${line#*|}"
        if [ -n "$merge_sha" ]; then
          printf '{"number":%s,"head":{"ref":"%s","sha":"%s"},"title":"%s","merged_at":"2026-10-14T12:00:00Z","base":{"ref":"%s"},"merge_commit_sha":"%s"}\n' \
            "$num" "$MAP_HEAD" "$merge_sha" "$MAP_TITLE" "$MAP_BASE" "$merge_sha"
        else
          printf '{"number":%s,"head":{"ref":"%s"},"title":"%s","merged_at":"2026-10-14T12:00:00Z","base":{"ref":"%s"}}\n' \
            "$num" "$MAP_HEAD" "$MAP_TITLE" "$MAP_BASE"
        fi
        return 0
        ;;
    esac
  done < "$MAP_FILE"
  return 1
}
lookup_commit_pulls() {
  local sha="$1" line pr_num json parts
  parts="["
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      "commit:${sha}|"*)
        pr_num="${line##*|}"
        case "$pr_num" in
          malformed:empty)
            # Empty HTTP body (distinct from well-formed []).
            printf '\n'
            return 0
            ;;
          malformed:null)
            printf '[null]\n'
            return 0
            ;;
          malformed:empty_object)
            printf '[{}]\n'
            return 0
            ;;
          malformed:no_number)
            printf '[{"merged_at":"2026-10-14T12:00:00Z","title":"fix","headRefName":"fix/LEA-302"}]\n'
            return 0
            ;;
          malformed:no_merged)
            printf '[{"number":88,"title":"fix(billing): LEA-302","headRefName":"fix/LEA-302-billing-fix"}]\n'
            return 0
            ;;
          empty:array)
            # Caller wraps with --slurp → [[]]
            printf '[]\n'
            return 0
            ;;
          paginate:error_page2|paginate:page2_shipping:*)
            # Handled by the api dispatcher (multi-page slurp / hard failure).
            return 1
            ;;
        esac
        if map_uses_rest_format; then
          json="$(lookup_pr_rest "$pr_num" "$sha")" || return 1
        else
          json="$(lookup_pr "$pr_num")" || return 1
        fi
        if [ "$parts" = "[" ]; then
          parts="${parts}${json}"
        else
          parts="${parts},${json}"
        fi
        ;;
    esac
  done < "$MAP_FILE"
  # Empty association list is success (no PRs for this commit) — not an API failure.
  printf '%s]\n' "$parts"
  return 0
}

# Build a two-page commits/<sha>/pulls payload (slurp shape): page 1 has 30
# filler PRs, page 2 has the shipping PR (number|head|title from map).
emit_paginated_commit_pulls_page2_shipping() {
  local shipping_pr="$1"
  local sha="$2"
  local i filler shipping_json
  if map_uses_rest_format; then
    shipping_json="$(lookup_pr_rest "$shipping_pr" "$sha")" || return 1
  else
    shipping_json="$(lookup_pr "$shipping_pr")" || return 1
  fi
  printf '['
  printf '['
  i=1
  while [ "$i" -le 30 ]; do
    [ "$i" -gt 1 ] && printf ','
    printf '{"number":%s,"headRefName":"chore/filler-%s","title":"chore: filler %s","mergedAt":"2026-10-14T12:00:00Z","baseRefName":"develop"}' \
      "$((9000 + i))" "$i" "$i"
    i=$((i + 1))
  done
  printf '],'
  printf '[%s]' "$shipping_json"
  printf ']\n'
}

if [ "$#" -ge 2 ] && [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  exit 0
fi
if [ "$#" -ge 2 ] && [ "$1" = "repo" ] && [ "$2" = "view" ]; then
  # Mimic real gh: GH_REPO overrides cwd. Production unsets GH_REPO before
  # resolve_repo_slug so component cleanups do not query the hub.
  if [ -n "${GH_REPO:-}" ]; then
    printf '%s\n' "$GH_REPO"
    exit 0
  fi
  printf 'example/repo\n'
  exit 0
fi
if [ "$#" -ge 2 ] && [ "$1" = "pr" ] && [ "$2" = "list" ]; then
  case "$*" in
    *" --state merged "*|*"--state merged"*)
      if [[ "$*" == *" --base main"* ]] || [[ "$*" == *"--base main"* ]]; then
        printf '881\n'
      else
        printf '882\n'
      fi
      ;;
    *)
      printf '\n'
      ;;
  esac
  exit 0
fi
if [ "$#" -ge 3 ] && [ "$1" = "pr" ] && [ "$2" = "view" ]; then
  lookup_pr "$3" || { printf 'pr view failed for %s\n' "$3" >&2; exit 1; }
  exit 0
fi
if [ "$#" -ge 2 ] && [ "$1" = "api" ]; then
  # Support: gh api [--paginate] [--slurp] repos/.../commits/<sha>/pulls[?per_page=N]
  endpoint=""
  use_slurp=false
  for arg in "$@"; do
    case "$arg" in
      --paginate) ;;
      --slurp) use_slurp=true ;;
      repos/*) endpoint="$arg" ;;
    esac
  done
  case "$endpoint" in
    repos/example/repo/commits/*/pulls*)
      sha="${endpoint#repos/example/repo/commits/}"
      sha="${sha%%/*}"
      # Special pagination fixtures (multi-page slurp body or hard failure).
      page2_pr=""
      while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
          "commit:${sha}|paginate:error_page2")
            printf 'paginate page 2 failed for %s\n' "$sha" >&2
            exit 1
            ;;
          "commit:${sha}|paginate:page2_shipping:"*)
            page2_pr="${line##*paginate:page2_shipping:}"
            ;;
        esac
      done < "$MAP_FILE"
      if [ -n "$page2_pr" ]; then
        emit_paginated_commit_pulls_page2_shipping "$page2_pr" "$sha" \
          || { printf 'commit pulls paginate failed for %s\n' "$sha" >&2; exit 1; }
        exit 0
      fi
      body="$(lookup_commit_pulls "$sha")" || { printf 'commit pulls failed for %s\n' "$sha" >&2; exit 1; }
      if [ "$use_slurp" = true ]; then
        # --slurp wraps each page; single-page responses become [[...]].
        # Empty body stays malformed (not wrapped).
        if [ -z "$(printf '%s' "$body" | tr -d '[:space:]')" ]; then
          printf '\n'
          exit 0
        fi
        printf '[%s]\n' "$body"
      else
        printf '%s\n' "$body"
      fi
      exit 0
      ;;
  esac
fi
printf 'unexpected gh invocation: gh %s\n' "$*" >&2
exit 64
MOCK_GH_LINEAR_SCOPE
  chmod +x "$LINEAR_SCOPE_BIN/gh"
}

init_linear_git_repo() {
  local path="$1"
  mkdir -p "$path/scripts/development-workflow"
  cp "$REPO_ROOT/scripts/development-workflow/workflow-lib.sh" "$path/scripts/development-workflow/workflow-lib.sh"
  cp "$REPO_ROOT/scripts/development-workflow/prepare-release-post-merge-cleanup.sh" "$path/scripts/development-workflow/prepare-release-post-merge-cleanup.sh"
  chmod +x "$path/scripts/development-workflow/prepare-release-post-merge-cleanup.sh"
  cat > "$path/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
issue_tracker:
  provider: linear
YAML
  "$REAL_GIT" -C "$path" init -q -b main
  configure_fixture_git_identity "$path"
  "$REAL_GIT" -C "$path" remote add origin "$path"
}

run_linear_scope_cleanup() {
  local repo="$1"
  shift
  local output="" rc=0
  set +e
  output="$(
    cd "$repo" && PATH="$LINEAR_SCOPE_BIN:$(dirname "$REAL_GIT"):$PATH" \
      LINEAR_SCOPE_MAP_FILE="$LINEAR_SCOPE_MAP_FILE" \
      WORKFLOW_SKIP_FETCH=1 \
      ./scripts/development-workflow/prepare-release-post-merge-cleanup.sh "$@" 2>&1
  )"
  rc=$?
  set -e
  printf '%s\n%s\n' "$rc" "$output"
}

# --inspect-targets + --release-head (requires stub merge-budget in the fixture).
ensure_inspect_merge_budget_stub() {
  local repo="$1"
  cat > "$repo/scripts/development-workflow/workflow-merge-budget.py" <<'PY'
#!/usr/bin/env python3
import sys
print("INSPECT_STUB_OK")
sys.exit(0)
PY
  chmod +x "$repo/scripts/development-workflow/workflow-merge-budget.py"
}

run_linear_scope_inspect() {
  local repo="$1"
  local version="$2"
  local release_head="$3"
  shift 3
  ensure_inspect_merge_budget_stub "$repo"
  run_linear_scope_cleanup "$repo" "$version" --from-changelog --inspect-targets \
    --release-head "$release_head" "$@"
}

# --- Original three cases + explicit --issue control ---
fixture_linear_scope_repo() {
  local name="$1"
  local path="$TMP_ROOT/$name"
  init_linear_git_repo "$path"
  cat > "$path/CHANGELOG.md" <<'MD'
# Changelog

## [Unreleased]

## [1.29.0] - 2026-10-15

- Shipped LEA-302 billing fix. Did not ship LEA-298 or LEA-301 (still Spec Ready).
- Mentioned expanded range LEA-298–LEA-301 and alternate LEA-298..LEA-301 for context only.

## [1.28.0] - 2026-10-01

- Older entry LEA-200.
MD
  local merge_sha=""
  "$REAL_GIT" -C "$path" add CHANGELOG.md .ai-dev-workflow.yaml scripts
  "$REAL_GIT" -C "$path" commit -q -m "chore: baseline before v1.28.0"
  "$REAL_GIT" -C "$path" tag v1.28.0
  "$REAL_GIT" -C "$path" commit -q --allow-empty \
    -m "Merge pull request #88 from example/fix/LEA-302-billing-fix"
  merge_sha="$("$REAL_GIT" -C "$path" rev-parse HEAD)"
  "$REAL_GIT" -C "$path" tag v1.29.0
  write_linear_scope_gh \
    "88|fix/LEA-302-billing-fix|fix(billing): LEA-302" \
    "commit:${merge_sha}|88"
  printf '%s\n' "$path"
}

repo_linear_scope="$(fixture_linear_scope_repo linear-1982-scope)"
result="$(run_linear_scope_cleanup "$repo_linear_scope" v1.29.0 --from-changelog --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"

run_test "linear_1982_exits_zero_best_effort" "0" "$status"
run_contains "linear_1982_skip_298" "RELEASE_SCOPE_SKIPPED issue=LEA-298 reason=changelog_mention_without_merged_pr" "$output"
run_contains "linear_1982_skip_301" "RELEASE_SCOPE_SKIPPED issue=LEA-301 reason=changelog_mention_without_merged_pr" "$output"
run_contains "linear_1982_skip_299_from_range" "RELEASE_SCOPE_SKIPPED issue=LEA-299 reason=changelog_mention_without_merged_pr" "$output"
run_contains "linear_1982_skip_300_from_range" "RELEASE_SCOPE_SKIPPED issue=LEA-300 reason=changelog_mention_without_merged_pr" "$output"
run_contains "linear_1982_proposes_merged_302" "TRACKER_ISSUES=LEA-302" "$output"
run_contains "linear_1982_action_for_merged" "TRACKER_ACTION=linear_mcp_or_api_required" "$output"
run_not_contains "linear_1982_does_not_list_298" "TRACKER_ISSUES=LEA-298" "$output"
run_not_contains "linear_1982_does_not_list_301_in_issues" "LEA-301," "$output"

repo_linear_explicit="$(fixture_linear_scope_repo linear-1982-explicit)"
result="$(run_linear_scope_cleanup "$repo_linear_explicit" v1.29.0 --issue LEA-298 --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_explicit_issue_exits_zero" "0" "$status"
run_contains "linear_explicit_issue_still_proposed" "TRACKER_ISSUES=LEA-298" "$output"
run_not_contains "linear_explicit_issue_not_filtered" "RELEASE_SCOPE_SKIPPED issue=LEA-298" "$output"

# Combined --from-changelog --issue: explicit override is unioned, never filtered.
repo_linear_combined="$(fixture_linear_scope_repo linear-1982-combined)"
result="$(run_linear_scope_cleanup "$repo_linear_combined" v1.29.0 --from-changelog --issue LEA-298 --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_1982_combined_exits_zero" "0" "$status"
run_contains "linear_1982_combined_keeps_explicit_298" "LEA-298" "$output"
run_contains "linear_1982_combined_keeps_merged_302" "LEA-302" "$output"
run_contains "linear_1982_combined_tracker_issues" "TRACKER_ISSUES=" "$output"
run_not_contains "linear_1982_combined_no_skip_explicit" "RELEASE_SCOPE_SKIPPED issue=LEA-298" "$output"

# --- (a) Leasity false negatives: PR-only IDs with no CHANGELOG entry ---
repo_pr_only="$TMP_ROOT/linear-1982-pr-only"
init_linear_git_repo "$repo_pr_only"
cat > "$repo_pr_only/CHANGELOG.md" <<'MD'
# Changelog

## [Unreleased]

## [1.29.0] - 2026-10-15

- Routine release notes with no Linear IDs for the shipped items below.

## [1.28.0] - 2026-10-01

- Older entry.
MD
"$REAL_GIT" -C "$repo_pr_only" add CHANGELOG.md .ai-dev-workflow.yaml scripts
"$REAL_GIT" -C "$repo_pr_only" commit -q -m "chore: baseline before v1.28.0"
"$REAL_GIT" -C "$repo_pr_only" tag v1.28.0
"$REAL_GIT" -C "$repo_pr_only" commit -q --allow-empty -m "Merge pull request #201 from example/feature/LEA-219-import"
sha_201="$("$REAL_GIT" -C "$repo_pr_only" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_pr_only" commit -q --allow-empty -m "Merge pull request #202 from example/feature/LEA-225-dashboard"
sha_202="$("$REAL_GIT" -C "$repo_pr_only" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_pr_only" commit -q --allow-empty -m "Merge pull request #203 from example/fix/LEA-254-billing"
sha_203="$("$REAL_GIT" -C "$repo_pr_only" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_pr_only" commit -q --allow-empty -m "Merge pull request #204 from example/feature/LEA-295-reports"
sha_204="$("$REAL_GIT" -C "$repo_pr_only" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_pr_only" tag v1.29.0
write_linear_scope_gh \
  "201|feature/LEA-219-import|feat: LEA-219 import" \
  "202|feature/LEA-225-dashboard|feat: LEA-225 dashboard" \
  "203|fix/LEA-254-billing|fix: LEA-254 billing" \
  "204|feature/LEA-295-reports|feat: LEA-295 reports" \
  "commit:${sha_201}|201" \
  "commit:${sha_202}|202" \
  "commit:${sha_203}|203" \
  "commit:${sha_204}|204"
result="$(run_linear_scope_cleanup "$repo_pr_only" v1.29.0 --from-changelog --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_1982a_pr_only_exits_zero" "0" "$status"
run_contains "linear_1982a_proposes_219" "LEA-219" "$output"
run_contains "linear_1982a_proposes_225" "LEA-225" "$output"
run_contains "linear_1982a_proposes_254" "LEA-254" "$output"
run_contains "linear_1982a_proposes_295" "LEA-295" "$output"
run_contains "linear_1982a_tracker_issues" "TRACKER_ISSUES=" "$output"
run_contains "linear_1982a_action" "TRACKER_ACTION=linear_mcp_or_api_required" "$output"

# --- (b) Hotfix: commit text omits ID and PR number; commit→PR lookup finds LEA-346 ---
repo_hotfix="$TMP_ROOT/linear-1982-hotfix"
init_linear_git_repo "$repo_hotfix"
cat > "$repo_hotfix/CHANGELOG.md" <<'MD'
# Changelog

## [Unreleased]

## [1.29.1] - 2026-10-16

- Hotfix release notes (no Linear ID for the ship).

## [1.29.0] - 2026-10-15

- Prior release.
MD
"$REAL_GIT" -C "$repo_hotfix" add CHANGELOG.md .ai-dev-workflow.yaml scripts
"$REAL_GIT" -C "$repo_hotfix" commit -q -m "chore: baseline v1.29.0"
"$REAL_GIT" -C "$repo_hotfix" tag v1.29.0
"$REAL_GIT" -C "$repo_hotfix" commit -q --allow-empty \
  -m "hotfix: stabilize billing calculator under empty invoice lines"
hotfix_sha="$("$REAL_GIT" -C "$repo_hotfix" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_hotfix" tag v1.29.1
write_linear_scope_gh \
  "782|hotfix/LEA-346-billing-calculator|hotfix: LEA-346 billing calculator" \
  "commit:${hotfix_sha}|782"
result="$(run_linear_scope_cleanup "$repo_hotfix" v1.29.1 --from-changelog --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_1982b_hotfix_exits_zero" "0" "$status"
run_contains "linear_1982b_proposes_346" "TRACKER_ISSUES=LEA-346" "$output"
run_contains "linear_1982b_action" "TRACKER_ACTION=linear_mcp_or_api_required" "$output"

# --- REST-shaped commits/<sha>/pulls: ID only in head.ref, title has no ID ---
repo_rest_hotfix="$TMP_ROOT/linear-1982-rest-head-ref"
init_linear_git_repo "$repo_rest_hotfix"
cat > "$repo_rest_hotfix/CHANGELOG.md" <<'MD'
# Changelog

## [Unreleased]

## [1.29.1] - 2026-10-16

- Hotfix release notes (no Linear ID for the ship).

## [1.29.0] - 2026-10-15

- Prior release.
MD
"$REAL_GIT" -C "$repo_rest_hotfix" add CHANGELOG.md .ai-dev-workflow.yaml scripts
"$REAL_GIT" -C "$repo_rest_hotfix" commit -q -m "chore: baseline v1.29.0"
"$REAL_GIT" -C "$repo_rest_hotfix" tag v1.29.0
"$REAL_GIT" -C "$repo_rest_hotfix" commit -q --allow-empty \
  -m "hotfix: stabilize billing calculator under empty invoice lines"
rest_hotfix_sha="$("$REAL_GIT" -C "$repo_rest_hotfix" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_rest_hotfix" tag v1.29.1
write_linear_scope_gh \
  "format:rest" \
  "782|hotfix/LEA-346-billing-calculator|hotfix: stabilize billing calculator" \
  "commit:${rest_hotfix_sha}|782"
result="$(run_linear_scope_cleanup "$repo_rest_hotfix" v1.29.1 --from-changelog --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_1982_rest_head_ref_exits_zero" "0" "$status"
run_contains "linear_1982_rest_head_ref_proposes_346" "TRACKER_ISSUES=LEA-346" "$output"
run_contains "linear_1982_rest_head_ref_action" "TRACKER_ACTION=linear_mcp_or_api_required" "$output"

# --- Missing release tag: never fall back to HEAD (later develop PR not proposed) ---
repo_missing_tag="$TMP_ROOT/linear-1982-missing-tag"
init_linear_git_repo "$repo_missing_tag"
cat > "$repo_missing_tag/CHANGELOG.md" <<'MD'
# Changelog

## [Unreleased]

## [1.29.0] - 2026-10-15

- Changelog names LEA-302 but the release tag is absent from this checkout.

## [1.28.0] - 2026-10-01

- Older.
MD
"$REAL_GIT" -C "$repo_missing_tag" add CHANGELOG.md .ai-dev-workflow.yaml scripts
"$REAL_GIT" -C "$repo_missing_tag" commit -q -m "chore: baseline before v1.28.0"
"$REAL_GIT" -C "$repo_missing_tag" tag v1.28.0
"$REAL_GIT" -C "$repo_missing_tag" commit -q --allow-empty \
  -m "Merge pull request #88 from example/fix/LEA-302-billing-fix"
"$REAL_GIT" -C "$repo_missing_tag" commit -q --allow-empty \
  -m "Merge pull request #99 from example/feature/LEA-999-later-develop"
# Deliberately omit v1.29.0 so a HEAD fallback would see LEA-999.
write_linear_scope_gh \
  "88|fix/LEA-302-billing-fix|fix(billing): LEA-302" \
  "99|feature/LEA-999-later-develop|feat: LEA-999 later develop"
result="$(run_linear_scope_cleanup "$repo_missing_tag" v1.29.0 --from-changelog --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_1982_missing_tag_best_effort_exits_zero" "0" "$status"
run_contains "linear_1982_missing_tag_incomplete" "RELEASE_SCOPE_INCOMPLETE reason=release_ref_unavailable" "$output"
run_not_contains "linear_1982_missing_tag_no_999" "LEA-999" "$output"
run_not_contains "linear_1982_missing_tag_no_302_issues" "TRACKER_ISSUES=LEA-302" "$output"
run_not_contains "linear_1982_missing_tag_no_tracker_action" "TRACKER_ACTION=linear_mcp_or_api_required" "$output"

# --- Branch named like the release version must not satisfy release-ref ---
repo_branch_named="$TMP_ROOT/linear-1982-branch-named-version"
init_linear_git_repo "$repo_branch_named"
cat > "$repo_branch_named/CHANGELOG.md" <<'MD'
# Changelog

## [Unreleased]

## [1.29.0] - 2026-10-15

- Branch v1.29.0 must not stand in for the missing release tag.
MD
"$REAL_GIT" -C "$repo_branch_named" add CHANGELOG.md .ai-dev-workflow.yaml scripts
"$REAL_GIT" -C "$repo_branch_named" commit -q -m "chore: baseline before v1.28.0"
"$REAL_GIT" -C "$repo_branch_named" tag v1.28.0
"$REAL_GIT" -C "$repo_branch_named" commit -q --allow-empty \
  -m "Merge pull request #88 from example/fix/LEA-302-billing-fix"
sha_branch_named="$("$REAL_GIT" -C "$repo_branch_named" rev-parse HEAD)"
# Same-named branch only — no refs/tags/v1.29.0.
"$REAL_GIT" -C "$repo_branch_named" branch v1.29.0 HEAD
write_linear_scope_gh \
  "88|fix/LEA-302-billing-fix|fix(billing): LEA-302" \
  "commit:${sha_branch_named}|88"
result="$(run_linear_scope_cleanup "$repo_branch_named" v1.29.0 --from-changelog --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_1982_branch_named_version_exits_zero" "0" "$status"
run_contains "linear_1982_branch_named_version_incomplete" \
  "RELEASE_SCOPE_INCOMPLETE reason=release_ref_unavailable" "$output"
run_not_contains "linear_1982_branch_named_version_no_302" "TRACKER_ISSUES=LEA-302" "$output"
run_not_contains "linear_1982_branch_named_version_no_action" \
  "TRACKER_ACTION=linear_mcp_or_api_required" "$output"

# --- (c) Commit mentions LEA-298 but PR branch/title do not → not proposed ---
repo_commit_mentions="$TMP_ROOT/linear-1982-commit-mention"
init_linear_git_repo "$repo_commit_mentions"
cat > "$repo_commit_mentions/CHANGELOG.md" <<'MD'
# Changelog

## [Unreleased]

## [1.29.0] - 2026-10-15

- Shipped LEA-302. Mentions LEA-298 only as context.

## [1.28.0] - 2026-10-01

- Older.
MD
"$REAL_GIT" -C "$repo_commit_mentions" add CHANGELOG.md .ai-dev-workflow.yaml scripts
"$REAL_GIT" -C "$repo_commit_mentions" commit -q -m "chore: baseline before v1.28.0"
"$REAL_GIT" -C "$repo_commit_mentions" tag v1.28.0
"$REAL_GIT" -C "$repo_commit_mentions" commit -q --allow-empty \
  -m "Merge pull request #90 from example/fix/LEA-302-ship

Also notes LEA-298 did not ship in this change."
sha_90="$("$REAL_GIT" -C "$repo_commit_mentions" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_commit_mentions" tag v1.29.0
write_linear_scope_gh \
  "90|fix/LEA-302-ship|fix: ship LEA-302 only" \
  "commit:${sha_90}|90"
result="$(run_linear_scope_cleanup "$repo_commit_mentions" v1.29.0 --from-changelog --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_1982c_exits_zero" "0" "$status"
run_contains "linear_1982c_proposes_302" "TRACKER_ISSUES=LEA-302" "$output"
run_contains "linear_1982c_skips_298" "RELEASE_SCOPE_SKIPPED issue=LEA-298 reason=changelog_mention_without_merged_pr" "$output"
run_not_contains "linear_1982c_no_298_in_issues" "LEA-298," "$output"

# --- Subject (#999) is not PR evidence; historical PR must not enlarge scope ---
repo_subject_pr="$TMP_ROOT/linear-1982-subject-pr-ref"
init_linear_git_repo "$repo_subject_pr"
cat > "$repo_subject_pr/CHANGELOG.md" <<'MD'
# Changelog

## [Unreleased]

## [1.29.0] - 2026-10-15

- Shipped LEA-302. Docs note refers to an older PR by number only.

## [1.28.0] - 2026-10-01

- Older.
MD
"$REAL_GIT" -C "$repo_subject_pr" add CHANGELOG.md .ai-dev-workflow.yaml scripts
"$REAL_GIT" -C "$repo_subject_pr" commit -q -m "chore: baseline before v1.28.0"
"$REAL_GIT" -C "$repo_subject_pr" tag v1.28.0
"$REAL_GIT" -C "$repo_subject_pr" commit -q --allow-empty \
  -m "Merge pull request #88 from example/fix/LEA-302-billing-fix"
sha_88="$("$REAL_GIT" -C "$repo_subject_pr" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_subject_pr" commit -q --allow-empty \
  -m "docs: refer to earlier change (#999)"
# No commit→PR map for the docs SHA. PR #999 exists historically but is not
# associated with any commit in this release range.
write_linear_scope_gh \
  "88|fix/LEA-302-billing-fix|fix(billing): LEA-302" \
  "999|feature/LEA-999-historical|feat: LEA-999 historical" \
  "commit:${sha_88}|88"
"$REAL_GIT" -C "$repo_subject_pr" tag v1.29.0
result="$(run_linear_scope_cleanup "$repo_subject_pr" v1.29.0 --from-changelog --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_1982_subject_pr_ref_exits_zero" "0" "$status"
run_contains "linear_1982_subject_pr_ref_proposes_302" "TRACKER_ISSUES=LEA-302" "$output"
run_not_contains "linear_1982_subject_pr_ref_no_999" "LEA-999" "$output"
run_not_contains "linear_1982_subject_pr_ref_no_incomplete" "RELEASE_SCOPE_INCOMPLETE" "$output"

# --- Fully resolved release with zero Linear IDs → empty scope, not incomplete ---
repo_zero_ids="$TMP_ROOT/linear-1982-zero-linear-ids"
init_linear_git_repo "$repo_zero_ids"
cat > "$repo_zero_ids/CHANGELOG.md" <<'MD'
# Changelog

## [Unreleased]

## [1.29.0] - 2026-10-15

- Routine docs release with no Linear identifiers.

## [1.28.0] - 2026-10-01

- Older.
MD
"$REAL_GIT" -C "$repo_zero_ids" add CHANGELOG.md .ai-dev-workflow.yaml scripts
"$REAL_GIT" -C "$repo_zero_ids" commit -q -m "chore: baseline before v1.28.0"
"$REAL_GIT" -C "$repo_zero_ids" tag v1.28.0
"$REAL_GIT" -C "$repo_zero_ids" commit -q --allow-empty \
  -m "Merge pull request #50 from example/chore/docs-typo"
sha_50="$("$REAL_GIT" -C "$repo_zero_ids" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_zero_ids" tag v1.29.0
write_linear_scope_gh \
  "50|chore/docs-typo|chore: fix typo" \
  "commit:${sha_50}|50"
# Without --best-effort: filter succeeds (empty scope); outer script reports no_issue_scope.
result="$(run_linear_scope_cleanup "$repo_zero_ids" v1.29.0 --from-changelog)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_1982_zero_ids_exits_nonzero_no_scope" "1" "$status"
run_contains "linear_1982_zero_ids_no_issue_scope" "TRACKER_INCOMPLETE=1 REASON=no_issue_scope" "$output"
run_not_contains "linear_1982_zero_ids_no_incomplete" "RELEASE_SCOPE_INCOMPLETE" "$output"
run_not_contains "linear_1982_zero_ids_no_tracker_action" "TRACKER_ACTION=linear_mcp_or_api_required" "$output"
result="$(run_linear_scope_cleanup "$repo_zero_ids" v1.29.0 --from-changelog --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_1982_zero_ids_best_effort_exits_zero" "0" "$status"
run_not_contains "linear_1982_zero_ids_best_effort_no_incomplete" "RELEASE_SCOPE_INCOMPLETE" "$output"

# --- Nested feature-base PR: base is not develop/main but merge is in range ---
repo_feature_base="$TMP_ROOT/linear-1982-feature-base"
init_linear_git_repo "$repo_feature_base"
cat > "$repo_feature_base/CHANGELOG.md" <<'MD'
# Changelog

## [Unreleased]

## [1.29.0] - 2026-10-15

- Nested feature work shipped via parent feature branch.

## [1.28.0] - 2026-10-01

- Older.
MD
"$REAL_GIT" -C "$repo_feature_base" add CHANGELOG.md .ai-dev-workflow.yaml scripts
"$REAL_GIT" -C "$repo_feature_base" commit -q -m "chore: baseline before v1.28.0"
"$REAL_GIT" -C "$repo_feature_base" tag v1.28.0
"$REAL_GIT" -C "$repo_feature_base" commit -q --allow-empty \
  -m "Merge pull request #301 from example/fix/LEA-301-nested"
sha_301="$("$REAL_GIT" -C "$repo_feature_base" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_feature_base" commit -q --allow-empty \
  -m "Merge pull request #400 from example/feature/billing"
sha_400="$("$REAL_GIT" -C "$repo_feature_base" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_feature_base" tag v1.29.0
write_linear_scope_gh \
  "301|fix/LEA-301-nested|fix: LEA-301 nested|feature/billing" \
  "400|feature/billing|feat: billing parent|develop" \
  "commit:${sha_301}|301" \
  "commit:${sha_400}|400"
result="$(run_linear_scope_cleanup "$repo_feature_base" v1.29.0 --from-changelog --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_1982_feature_base_exits_zero" "0" "$status"
run_contains "linear_1982_feature_base_proposes_301" "LEA-301" "$output"
run_contains "linear_1982_feature_base_tracker_issues" "TRACKER_ISSUES=" "$output"
run_contains "linear_1982_feature_base_action" "TRACKER_ACTION=linear_mcp_or_api_required" "$output"

# --- Documentation-stage PRs are not shipping evidence; fix/feature are ---
repo_doc_stage="$TMP_ROOT/linear-1982-doc-stage"
init_linear_git_repo "$repo_doc_stage"
cat > "$repo_doc_stage/CHANGELOG.md" <<'MD'
# Changelog

## [Unreleased]

## [1.29.0] - 2026-10-15

- Mentions LEA-298 from docs-stage merges; also ships LEA-302 via fix PR.

## [1.28.0] - 2026-10-01

- Older.
MD
"$REAL_GIT" -C "$repo_doc_stage" add CHANGELOG.md .ai-dev-workflow.yaml scripts
"$REAL_GIT" -C "$repo_doc_stage" commit -q -m "chore: baseline before v1.28.0"
"$REAL_GIT" -C "$repo_doc_stage" tag v1.28.0
"$REAL_GIT" -C "$repo_doc_stage" commit -q --allow-empty \
  -m "Merge pull request #501 from example/spec/LEA-298-new-feature"
sha_spec="$("$REAL_GIT" -C "$repo_doc_stage" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_doc_stage" commit -q --allow-empty \
  -m "Merge pull request #502 from example/implementation-plan/LEA-298-new-feature"
sha_plan="$("$REAL_GIT" -C "$repo_doc_stage" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_doc_stage" commit -q --allow-empty \
  -m "Merge pull request #503 from example/fix/LEA-302-billing"
sha_fix="$("$REAL_GIT" -C "$repo_doc_stage" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_doc_stage" tag v1.29.0
write_linear_scope_gh \
  "501|spec/LEA-298-new-feature|spec: LEA-298 new feature" \
  "502|implementation-plan/LEA-298-new-feature|plan: LEA-298 new feature" \
  "503|fix/LEA-302-billing|fix: LEA-302 billing" \
  "commit:${sha_spec}|501" \
  "commit:${sha_plan}|502" \
  "commit:${sha_fix}|503"
result="$(run_linear_scope_cleanup "$repo_doc_stage" v1.29.0 --from-changelog --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_1982_doc_stage_exits_zero" "0" "$status"
run_contains "linear_1982_doc_stage_skip_298" "RELEASE_SCOPE_SKIPPED issue=LEA-298 reason=documentation_stage_pr_only" "$output"
run_contains "linear_1982_doc_stage_proposes_302" "TRACKER_ISSUES=LEA-302" "$output"
run_not_contains "linear_1982_doc_stage_no_298_in_issues" "LEA-298," "$output"
run_not_contains "linear_1982_doc_stage_no_298_alone" "TRACKER_ISSUES=LEA-298" "$output"

# Same ID with an implementation PR → proposed even if docs-stage PRs also exist.
repo_doc_and_impl="$TMP_ROOT/linear-1982-doc-and-impl"
init_linear_git_repo "$repo_doc_and_impl"
cat > "$repo_doc_and_impl/CHANGELOG.md" <<'MD'
# Changelog

## [Unreleased]

## [1.29.0] - 2026-10-15

- LEA-298 shipped after docs-stage then feature PR.

## [1.28.0] - 2026-10-01

- Older.
MD
"$REAL_GIT" -C "$repo_doc_and_impl" add CHANGELOG.md .ai-dev-workflow.yaml scripts
"$REAL_GIT" -C "$repo_doc_and_impl" commit -q -m "chore: baseline before v1.28.0"
"$REAL_GIT" -C "$repo_doc_and_impl" tag v1.28.0
"$REAL_GIT" -C "$repo_doc_and_impl" commit -q --allow-empty \
  -m "Merge pull request #511 from example/spec/LEA-298-new-feature"
sha_spec2="$("$REAL_GIT" -C "$repo_doc_and_impl" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_doc_and_impl" commit -q --allow-empty \
  -m "Merge pull request #512 from example/feature/LEA-298-new-feature"
sha_feat="$("$REAL_GIT" -C "$repo_doc_and_impl" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_doc_and_impl" tag v1.29.0
write_linear_scope_gh \
  "511|spec/LEA-298-new-feature|spec: LEA-298 new feature" \
  "512|feature/LEA-298-new-feature|feat: LEA-298 new feature" \
  "commit:${sha_spec2}|511" \
  "commit:${sha_feat}|512"
result="$(run_linear_scope_cleanup "$repo_doc_and_impl" v1.29.0 --from-changelog --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_1982_doc_plus_impl_exits_zero" "0" "$status"
run_contains "linear_1982_doc_plus_impl_proposes_298" "TRACKER_ISSUES=LEA-298" "$output"
run_not_contains "linear_1982_doc_plus_impl_no_doc_skip" "RELEASE_SCOPE_SKIPPED issue=LEA-298 reason=documentation_stage_pr_only" "$output"

# Explicit --issue overrides documentation-stage-only evidence: proposed once,
# never RELEASE_SCOPE_SKIPPED (same array feeds component release_scope_skipped).
repo_explicit_doc="$TMP_ROOT/linear-1982-explicit-doc-stage"
init_linear_git_repo "$repo_explicit_doc"
cat > "$repo_explicit_doc/CHANGELOG.md" <<'MD'
# Changelog

## [Unreleased]

## [1.29.0] - 2026-10-15

- Mentions LEA-298 (docs-stage only in this release).
MD
"$REAL_GIT" -C "$repo_explicit_doc" add CHANGELOG.md .ai-dev-workflow.yaml scripts
"$REAL_GIT" -C "$repo_explicit_doc" commit -q -m "chore: baseline before v1.28.0"
"$REAL_GIT" -C "$repo_explicit_doc" tag v1.28.0
"$REAL_GIT" -C "$repo_explicit_doc" commit -q --allow-empty \
  -m "Merge pull request #521 from example/spec/LEA-298-new-feature"
sha_explicit_spec="$("$REAL_GIT" -C "$repo_explicit_doc" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_explicit_doc" commit -q --allow-empty \
  -m "Merge pull request #522 from example/implementation-plan/LEA-298-new-feature"
sha_explicit_plan="$("$REAL_GIT" -C "$repo_explicit_doc" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_explicit_doc" tag v1.29.0
write_linear_scope_gh \
  "521|spec/LEA-298-new-feature|spec: LEA-298 new feature" \
  "522|implementation-plan/LEA-298-new-feature|plan: LEA-298 new feature" \
  "commit:${sha_explicit_spec}|521" \
  "commit:${sha_explicit_plan}|522"
result="$(run_linear_scope_cleanup "$repo_explicit_doc" v1.29.0 \
  --from-changelog --issue LEA-298 --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_1982_explicit_doc_exits_zero" "0" "$status"
run_contains "linear_1982_explicit_doc_proposes_298" "TRACKER_ISSUES=LEA-298" "$output"
run_not_contains "linear_1982_explicit_doc_no_skip_line" \
  "RELEASE_SCOPE_SKIPPED issue=LEA-298" "$output"
# Proposed exactly once in TRACKER_ISSUES (no duplicate from filter KEEP + union).
tracker_count="$(printf '%s\n' "$output" | grep -oE 'TRACKER_ISSUES=[^[:space:]]+' | \
  tr ',' '\n' | grep -c 'LEA-298' || true)"
run_test "linear_1982_explicit_doc_proposed_once" "1" "$tracker_count"

# Explicit --issue overrides release/backport-only evidence the same way.
repo_explicit_rel="$TMP_ROOT/linear-1982-explicit-release-branch"
init_linear_git_repo "$repo_explicit_rel"
cat > "$repo_explicit_rel/CHANGELOG.md" <<'MD'
# Changelog

## [Unreleased]

## [1.29.0] - 2026-10-15

- Mentions LEA-999 from a release-branch merge only.
MD
"$REAL_GIT" -C "$repo_explicit_rel" add CHANGELOG.md .ai-dev-workflow.yaml scripts
"$REAL_GIT" -C "$repo_explicit_rel" commit -q -m "chore: baseline before v1.28.0"
"$REAL_GIT" -C "$repo_explicit_rel" tag v1.28.0
"$REAL_GIT" -C "$repo_explicit_rel" commit -q --allow-empty \
  -m "Merge pull request #531 from example/release/v1.29.0"
sha_explicit_rel="$("$REAL_GIT" -C "$repo_explicit_rel" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_explicit_rel" tag v1.29.0
write_linear_scope_gh \
  "531|release/v1.29.0|Release v1.29.0 LEA-999" \
  "commit:${sha_explicit_rel}|531"
result="$(run_linear_scope_cleanup "$repo_explicit_rel" v1.29.0 \
  --from-changelog --issue LEA-999 --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_1982_explicit_rel_exits_zero" "0" "$status"
run_contains "linear_1982_explicit_rel_proposes_999" "TRACKER_ISSUES=LEA-999" "$output"
run_not_contains "linear_1982_explicit_rel_no_skip_line" \
  "RELEASE_SCOPE_SKIPPED issue=LEA-999" "$output"
tracker_count="$(printf '%s\n' "$output" | grep -oE 'TRACKER_ISSUES=[^[:space:]]+' | \
  tr ',' '\n' | grep -c 'LEA-999' || true)"
run_test "linear_1982_explicit_rel_proposed_once" "1" "$tracker_count"

# --- First release (no preceding semver tag) may scan tip history ---
repo_first="$TMP_ROOT/linear-1982-first-release"
init_linear_git_repo "$repo_first"
cat > "$repo_first/CHANGELOG.md" <<'MD'
# Changelog

## [Unreleased]

## [1.0.0] - 2026-10-15

- First release ships LEA-100.
MD
"$REAL_GIT" -C "$repo_first" add CHANGELOG.md .ai-dev-workflow.yaml scripts
"$REAL_GIT" -C "$repo_first" commit -q -m "chore: initial"
"$REAL_GIT" -C "$repo_first" commit -q --allow-empty \
  -m "Merge pull request #10 from example/feature/LEA-100-first"
sha_first="$("$REAL_GIT" -C "$repo_first" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_first" tag v1.0.0
write_linear_scope_gh \
  "10|feature/LEA-100-first|feat: LEA-100 first" \
  "commit:${sha_first}|10"
result="$(run_linear_scope_cleanup "$repo_first" v1.0.0 --from-changelog --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_1982_first_release_exits_zero" "0" "$status"
run_contains "linear_1982_first_release_proposes_100" "TRACKER_ISSUES=LEA-100" "$output"
run_not_contains "linear_1982_first_release_no_boundary_incomplete" "previous_release_boundary_unavailable" "$output"

# --- (a) --no-tags clone with only release tag locally; remote has previous ---
repo_notags_src="$TMP_ROOT/linear-1982-notags-src"
repo_notags_bare="$TMP_ROOT/linear-1982-notags-bare.git"
repo_notags="$TMP_ROOT/linear-1982-notags"
init_linear_git_repo "$repo_notags_src"
cat > "$repo_notags_src/CHANGELOG.md" <<'MD'
# Changelog

## [Unreleased]

## [1.29.0] - 2026-10-15

- Current release ships LEA-302.

## [1.28.0] - 2026-10-01

- Historical LEA-200.
MD
"$REAL_GIT" -C "$repo_notags_src" add CHANGELOG.md .ai-dev-workflow.yaml scripts
"$REAL_GIT" -C "$repo_notags_src" commit -q -m "chore: baseline before historical"
"$REAL_GIT" -C "$repo_notags_src" commit -q --allow-empty \
  -m "Merge pull request #77 from example/fix/LEA-200-historical"
sha_200="$("$REAL_GIT" -C "$repo_notags_src" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_notags_src" tag v1.28.0
"$REAL_GIT" -C "$repo_notags_src" commit -q --allow-empty \
  -m "Merge pull request #88 from example/fix/LEA-302-billing-fix"
sha_302="$("$REAL_GIT" -C "$repo_notags_src" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_notags_src" tag v1.29.0
"$REAL_GIT" clone -q --bare "file://${repo_notags_src}" "$repo_notags_bare"
"$REAL_GIT" clone -q --no-tags "file://${repo_notags_bare}" "$repo_notags"
"$REAL_GIT" -C "$repo_notags" fetch -q origin refs/tags/v1.29.0:refs/tags/v1.29.0
mkdir -p "$repo_notags/scripts/development-workflow"
cp "$REPO_ROOT/scripts/development-workflow/workflow-lib.sh" \
  "$repo_notags/scripts/development-workflow/workflow-lib.sh"
cp "$REPO_ROOT/scripts/development-workflow/prepare-release-post-merge-cleanup.sh" \
  "$repo_notags/scripts/development-workflow/prepare-release-post-merge-cleanup.sh"
chmod +x "$repo_notags/scripts/development-workflow/prepare-release-post-merge-cleanup.sh"
cat > "$repo_notags/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
issue_tracker:
  provider: linear
YAML
write_linear_scope_gh \
  "77|fix/LEA-200-historical|fix: LEA-200 historical" \
  "88|fix/LEA-302-billing-fix|fix(billing): LEA-302" \
  "commit:${sha_200}|77" \
  "commit:${sha_302}|88"
result="$(run_linear_scope_cleanup "$repo_notags" v1.29.0 --from-changelog --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_1982_notags_exits_zero" "0" "$status"
run_contains "linear_1982_notags_proposes_302" "TRACKER_ISSUES=LEA-302" "$output"
run_not_contains "linear_1982_notags_no_200" "LEA-200" "$output"
run_not_contains "linear_1982_notags_no_boundary_incomplete" "previous_release_boundary_unavailable" "$output"

# --- (b) Remote tag listing unavailable → previous_release_boundary_unavailable ---
repo_tag_fail="$TMP_ROOT/linear-1982-tag-list-fail"
init_linear_git_repo "$repo_tag_fail"
cat > "$repo_tag_fail/CHANGELOG.md" <<'MD'
# Changelog

## [Unreleased]

## [1.29.0] - 2026-10-15

- Would ship LEA-302 if boundary were available.
MD
"$REAL_GIT" -C "$repo_tag_fail" add CHANGELOG.md .ai-dev-workflow.yaml scripts
"$REAL_GIT" -C "$repo_tag_fail" commit -q -m "chore: baseline before v1.28.0"
"$REAL_GIT" -C "$repo_tag_fail" tag v1.28.0
"$REAL_GIT" -C "$repo_tag_fail" commit -q --allow-empty \
  -m "Merge pull request #88 from example/fix/LEA-302-billing-fix"
sha_tag_fail="$("$REAL_GIT" -C "$repo_tag_fail" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_tag_fail" tag v1.29.0
write_linear_scope_gh \
  "88|fix/LEA-302-billing-fix|fix(billing): LEA-302" \
  "commit:${sha_tag_fail}|88"
TAG_FAIL_BIN="$TMP_ROOT/tag-fail-bin"
mkdir -p "$TAG_FAIL_BIN"
cat > "$TAG_FAIL_BIN/git" <<GITWRAP
#!/usr/bin/env bash
# Fail only the remote tag listing used for previous-boundary discovery.
case " \$* " in
  *" ls-remote --tags "*|*" ls-remote "*"--tags"*) exit 1 ;;
esac
exec "$REAL_GIT" "\$@"
GITWRAP
chmod +x "$TAG_FAIL_BIN/git"
result="$(
  set +e
  output="$(
    cd "$repo_tag_fail" && PATH="$TAG_FAIL_BIN:$LINEAR_SCOPE_BIN:$(dirname "$REAL_GIT"):$PATH" \
      LINEAR_SCOPE_MAP_FILE="$LINEAR_SCOPE_MAP_FILE" \
      WORKFLOW_SKIP_FETCH=1 \
      ./scripts/development-workflow/prepare-release-post-merge-cleanup.sh \
      v1.29.0 --from-changelog --best-effort 2>&1
  )"
  rc=$?
  set -e
  printf '%s\n%s\n' "$rc" "$output"
)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_1982_tag_list_fail_best_effort_exits_zero" "0" "$status"
run_contains "linear_1982_tag_list_fail_incomplete" "RELEASE_SCOPE_INCOMPLETE reason=previous_release_boundary_unavailable" "$output"
run_not_contains "linear_1982_tag_list_fail_no_302" "TRACKER_ISSUES=LEA-302" "$output"

# --- Shallow clone → previous_release_boundary_unavailable ---
repo_shallow_src="$TMP_ROOT/linear-1982-shallow-src"
repo_shallow="$TMP_ROOT/linear-1982-shallow"
init_linear_git_repo "$repo_shallow_src"
cat > "$repo_shallow_src/CHANGELOG.md" <<'MD'
# Changelog

## [Unreleased]

## [1.29.0] - 2026-10-15

- Shallow tip must not invent historical scope.
MD
"$REAL_GIT" -C "$repo_shallow_src" add CHANGELOG.md .ai-dev-workflow.yaml scripts
"$REAL_GIT" -C "$repo_shallow_src" commit -q -m "chore: baseline before v1.28.0"
"$REAL_GIT" -C "$repo_shallow_src" tag v1.28.0
"$REAL_GIT" -C "$repo_shallow_src" commit -q --allow-empty \
  -m "Merge pull request #88 from example/fix/LEA-302-billing-fix"
sha_shallow="$("$REAL_GIT" -C "$repo_shallow_src" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_shallow_src" tag v1.29.0
write_linear_scope_gh \
  "88|fix/LEA-302-billing-fix|fix(billing): LEA-302" \
  "commit:${sha_shallow}|88"
"$REAL_GIT" clone -q --depth 1 "file://${repo_shallow_src}" "$repo_shallow"
# Ensure cleanup script + config exist in the shallow checkout.
mkdir -p "$repo_shallow/scripts/development-workflow"
cp "$REPO_ROOT/scripts/development-workflow/workflow-lib.sh" \
  "$repo_shallow/scripts/development-workflow/workflow-lib.sh"
cp "$REPO_ROOT/scripts/development-workflow/prepare-release-post-merge-cleanup.sh" \
  "$repo_shallow/scripts/development-workflow/prepare-release-post-merge-cleanup.sh"
chmod +x "$repo_shallow/scripts/development-workflow/prepare-release-post-merge-cleanup.sh"
cat > "$repo_shallow/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
issue_tracker:
  provider: linear
YAML
result="$(run_linear_scope_cleanup "$repo_shallow" v1.29.0 --from-changelog --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_1982_shallow_best_effort_exits_zero" "0" "$status"
run_contains "linear_1982_shallow_incomplete" "RELEASE_SCOPE_INCOMPLETE reason=previous_release_boundary_unavailable" "$output"
run_contains "linear_1982_shallow_fetch_instruction" "git fetch --tags origin" "$output"
run_not_contains "linear_1982_shallow_no_302" "TRACKER_ISSUES=LEA-302" "$output"

# --- Local preceding tag disagrees with remote peeled SHA → incomplete ---
repo_tag_mismatch_src="$TMP_ROOT/linear-1982-tag-mismatch-src"
repo_tag_mismatch_bare="$TMP_ROOT/linear-1982-tag-mismatch-bare.git"
repo_tag_mismatch="$TMP_ROOT/linear-1982-tag-mismatch"
init_linear_git_repo "$repo_tag_mismatch_src"
cat > "$repo_tag_mismatch_src/CHANGELOG.md" <<'MD'
# Changelog

## [Unreleased]

## [1.29.0] - 2026-10-15

- Ships LEA-302.
MD
"$REAL_GIT" -C "$repo_tag_mismatch_src" add CHANGELOG.md .ai-dev-workflow.yaml scripts
"$REAL_GIT" -C "$repo_tag_mismatch_src" commit -q -m "chore: baseline"
"$REAL_GIT" -C "$repo_tag_mismatch_src" commit -q --allow-empty -m "historical before v1.28.0"
"$REAL_GIT" -C "$repo_tag_mismatch_src" tag v1.28.0
"$REAL_GIT" -C "$repo_tag_mismatch_src" commit -q --allow-empty \
  -m "Merge pull request #88 from example/fix/LEA-302-billing-fix"
sha_mismatch_302="$("$REAL_GIT" -C "$repo_tag_mismatch_src" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_tag_mismatch_src" tag v1.29.0
"$REAL_GIT" clone -q --bare "file://${repo_tag_mismatch_src}" "$repo_tag_mismatch_bare"
"$REAL_GIT" clone -q "file://${repo_tag_mismatch_bare}" "$repo_tag_mismatch"
# Point local v1.28.0 at the release tip (disagrees with remote peeled SHA).
"$REAL_GIT" -C "$repo_tag_mismatch" tag -d v1.28.0 >/dev/null
"$REAL_GIT" -C "$repo_tag_mismatch" tag v1.28.0 "$sha_mismatch_302"
mkdir -p "$repo_tag_mismatch/scripts/development-workflow"
cp "$REPO_ROOT/scripts/development-workflow/workflow-lib.sh" \
  "$repo_tag_mismatch/scripts/development-workflow/workflow-lib.sh"
cp "$REPO_ROOT/scripts/development-workflow/prepare-release-post-merge-cleanup.sh" \
  "$repo_tag_mismatch/scripts/development-workflow/prepare-release-post-merge-cleanup.sh"
chmod +x "$repo_tag_mismatch/scripts/development-workflow/prepare-release-post-merge-cleanup.sh"
cat > "$repo_tag_mismatch/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
issue_tracker:
  provider: linear
YAML
write_linear_scope_gh \
  "88|fix/LEA-302-billing-fix|fix(billing): LEA-302" \
  "commit:${sha_mismatch_302}|88"
result="$(run_linear_scope_cleanup "$repo_tag_mismatch" v1.29.0 --from-changelog --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_1982_tag_mismatch_exits_zero" "0" "$status"
run_contains "linear_1982_tag_mismatch_incomplete" \
  "RELEASE_SCOPE_INCOMPLETE reason=previous_release_boundary_unavailable" "$output"
run_contains "linear_1982_tag_mismatch_fetch_instruction" "git fetch --tags origin" "$output"
run_not_contains "linear_1982_tag_mismatch_no_302" "TRACKER_ISSUES=LEA-302" "$output"

# --- Preceding commit missing locally (non-shallow) → incomplete + fetch instruction ---
repo_missing_prev_src="$TMP_ROOT/linear-1982-missing-prev-src"
repo_missing_prev_bare="$TMP_ROOT/linear-1982-missing-prev-bare.git"
repo_missing_prev="$TMP_ROOT/linear-1982-missing-prev"
init_linear_git_repo "$repo_missing_prev_src"
cat > "$repo_missing_prev_src/CHANGELOG.md" <<'MD'
# Changelog

## [Unreleased]

## [1.29.0] - 2026-10-15

- Ships LEA-302.
MD
"$REAL_GIT" -C "$repo_missing_prev_src" add CHANGELOG.md .ai-dev-workflow.yaml scripts
"$REAL_GIT" -C "$repo_missing_prev_src" commit -q -m "chore: baseline"
"$REAL_GIT" -C "$repo_missing_prev_src" commit -q --allow-empty \
  -m "Merge pull request #77 from example/fix/LEA-200-historical"
"$REAL_GIT" -C "$repo_missing_prev_src" tag v1.28.0
"$REAL_GIT" -C "$repo_missing_prev_src" commit -q --allow-empty \
  -m "Merge pull request #88 from example/fix/LEA-302-billing-fix"
sha_missing_prev_302="$("$REAL_GIT" -C "$repo_missing_prev_src" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_missing_prev_src" tag v1.29.0
"$REAL_GIT" clone -q --bare "file://${repo_missing_prev_src}" "$repo_missing_prev_bare"
# Local checkout: orphan tip tagged v1.29.0 at a different SHA than remote.
# Namespace identity now fails closed on that local/remote tip disagreement
# (ambiguous_release_tag_namespace) before the previous-commit probe.
"$REAL_GIT" init -q -b main "$repo_missing_prev"
configure_fixture_git_identity "$repo_missing_prev"
"$REAL_GIT" -C "$repo_missing_prev" remote add origin "$repo_missing_prev_bare"
"$REAL_GIT" -C "$repo_missing_prev" commit -q --allow-empty -m "orphan release tip"
"$REAL_GIT" -C "$repo_missing_prev" tag v1.29.0
mkdir -p "$repo_missing_prev/scripts/development-workflow"
cp "$REPO_ROOT/scripts/development-workflow/workflow-lib.sh" \
  "$repo_missing_prev/scripts/development-workflow/workflow-lib.sh"
cp "$REPO_ROOT/scripts/development-workflow/prepare-release-post-merge-cleanup.sh" \
  "$repo_missing_prev/scripts/development-workflow/prepare-release-post-merge-cleanup.sh"
chmod +x "$repo_missing_prev/scripts/development-workflow/prepare-release-post-merge-cleanup.sh"
cat > "$repo_missing_prev/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
issue_tracker:
  provider: linear
YAML
cat > "$repo_missing_prev/CHANGELOG.md" <<'MD'
# Changelog

## [Unreleased]

## [1.29.0] - 2026-10-15

- Ships LEA-302.
MD
write_linear_scope_gh \
  "88|fix/LEA-302-billing-fix|fix(billing): LEA-302" \
  "commit:${sha_missing_prev_302}|88"
result="$(run_linear_scope_cleanup "$repo_missing_prev" v1.29.0 --from-changelog --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_1982_missing_prev_commit_exits_zero" "0" "$status"
run_contains "linear_1982_missing_prev_commit_incomplete" \
  "RELEASE_SCOPE_INCOMPLETE reason=ambiguous_release_tag_namespace" "$output"
run_contains "linear_1982_missing_prev_commit_ambiguous_diag" \
  "ambiguous_release_tag_namespace version=v1.29.0" "$output"
run_not_contains "linear_1982_missing_prev_commit_no_302" "TRACKER_ISSUES=LEA-302" "$output"

# --- --inspect-targets must not mutate refs / create FETCH_HEAD ---
repo_inspect_src="$TMP_ROOT/linear-1982-inspect-src"
repo_inspect_bare="$TMP_ROOT/linear-1982-inspect-bare.git"
repo_inspect="$TMP_ROOT/linear-1982-inspect"
init_linear_git_repo "$repo_inspect_src"
cat > "$repo_inspect_src/CHANGELOG.md" <<'MD'
# Changelog

## [Unreleased]

## [1.29.0] - 2026-10-15

- Ships LEA-302.
MD
"$REAL_GIT" -C "$repo_inspect_src" add CHANGELOG.md .ai-dev-workflow.yaml scripts
"$REAL_GIT" -C "$repo_inspect_src" commit -q -m "chore: baseline before v1.28.0"
"$REAL_GIT" -C "$repo_inspect_src" tag v1.28.0
"$REAL_GIT" -C "$repo_inspect_src" commit -q --allow-empty \
  -m "Merge pull request #88 from example/fix/LEA-302-billing-fix"
sha_inspect="$("$REAL_GIT" -C "$repo_inspect_src" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_inspect_src" tag v1.29.0
"$REAL_GIT" clone -q --bare "file://${repo_inspect_src}" "$repo_inspect_bare"
"$REAL_GIT" clone -q "file://${repo_inspect_bare}" "$repo_inspect"
mkdir -p "$repo_inspect/scripts/development-workflow"
cp "$REPO_ROOT/scripts/development-workflow/workflow-lib.sh" \
  "$repo_inspect/scripts/development-workflow/workflow-lib.sh"
cp "$REPO_ROOT/scripts/development-workflow/prepare-release-post-merge-cleanup.sh" \
  "$repo_inspect/scripts/development-workflow/prepare-release-post-merge-cleanup.sh"
chmod +x "$repo_inspect/scripts/development-workflow/prepare-release-post-merge-cleanup.sh"
# Stub merge-budget so inspect exits after Linear scope resolution without
# requiring a live Project/Linear projection.
cat > "$repo_inspect/scripts/development-workflow/workflow-merge-budget.py" <<'PY'
#!/usr/bin/env python3
import sys
print("INSPECT_STUB_OK")
sys.exit(0)
PY
chmod +x "$repo_inspect/scripts/development-workflow/workflow-merge-budget.py"
cat > "$repo_inspect/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
issue_tracker:
  provider: linear
YAML
write_linear_scope_gh \
  "88|fix/LEA-302-billing-fix|fix(billing): LEA-302" \
  "commit:${sha_inspect}|88"
rm -f "$repo_inspect/.git/FETCH_HEAD"
inspect_refs_before="$("$REAL_GIT" -C "$repo_inspect" for-each-ref --format='%(refname) %(objectname)' | LC_ALL=C sort)"
result="$(
  set +e
  output="$(
    cd "$repo_inspect" && PATH="$LINEAR_SCOPE_BIN:$(dirname "$REAL_GIT"):$PATH" \
      LINEAR_SCOPE_MAP_FILE="$LINEAR_SCOPE_MAP_FILE" \
      WORKFLOW_SKIP_FETCH=1 \
      ./scripts/development-workflow/prepare-release-post-merge-cleanup.sh \
      v1.29.0 --from-changelog --inspect-targets --release-head "$sha_inspect" 2>&1
  )"
  rc=$?
  set -e
  printf '%s\n%s\n' "$rc" "$output"
)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
inspect_refs_after="$("$REAL_GIT" -C "$repo_inspect" for-each-ref --format='%(refname) %(objectname)' | LC_ALL=C sort)"
run_test "linear_1982_inspect_exits_zero" "0" "$status"
run_contains "linear_1982_inspect_stub_ok" "INSPECT_STUB_OK" "$output"
run_test "linear_1982_inspect_refs_unchanged" "$inspect_refs_before" "$inspect_refs_after"
run_test "linear_1982_inspect_no_fetch_head" "0" \
  "$([ -e "$repo_inspect/.git/FETCH_HEAD" ] && echo 1 || echo 0)"

# --- Component tag prefix: mobile-v1.0.0 → mobile-v1.1.0; bare v2.0.0 ignored ---
repo_mobile="$TMP_ROOT/linear-1982-mobile-prefix"
init_linear_git_repo "$repo_mobile"
cat > "$repo_mobile/CHANGELOG.md" <<'MD'
# Changelog

## [Unreleased]

## [mobile-v1.1.0] - 2026-10-15

- Component release ships LEA-410.
MD
"$REAL_GIT" -C "$repo_mobile" add CHANGELOG.md .ai-dev-workflow.yaml scripts
"$REAL_GIT" -C "$repo_mobile" commit -q -m "chore: mobile baseline"
"$REAL_GIT" -C "$repo_mobile" commit -q --allow-empty \
  -m "Merge pull request #70 from example/fix/LEA-200-unrelated-v2"
sha_v2="$("$REAL_GIT" -C "$repo_mobile" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_mobile" tag v2.0.0
"$REAL_GIT" -C "$repo_mobile" commit -q --allow-empty \
  -m "Merge pull request #71 from example/fix/LEA-400-mobile-prior"
sha_mobile_400="$("$REAL_GIT" -C "$repo_mobile" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_mobile" tag mobile-v1.0.0
"$REAL_GIT" -C "$repo_mobile" commit -q --allow-empty \
  -m "Merge pull request #72 from example/fix/LEA-410-mobile-current"
sha_mobile_410="$("$REAL_GIT" -C "$repo_mobile" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_mobile" tag mobile-v1.1.0
write_linear_scope_gh \
  "70|fix/LEA-200-unrelated-v2|fix: LEA-200 v2" \
  "71|fix/LEA-400-mobile-prior|fix: LEA-400 mobile" \
  "72|fix/LEA-410-mobile-current|fix: LEA-410 mobile" \
  "commit:${sha_v2}|70" \
  "commit:${sha_mobile_400}|71" \
  "commit:${sha_mobile_410}|72"
result="$(run_linear_scope_cleanup "$repo_mobile" mobile-v1.1.0 --from-changelog --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_1982_mobile_prefix_exits_zero" "0" "$status"
run_contains "linear_1982_mobile_prefix_proposes_410" "TRACKER_ISSUES=LEA-410" "$output"
run_not_contains "linear_1982_mobile_prefix_no_400" "LEA-400" "$output"
run_not_contains "linear_1982_mobile_prefix_no_200" "LEA-200" "$output"
run_not_contains "linear_1982_mobile_prefix_no_boundary_incomplete" \
  "previous_release_boundary_unavailable" "$output"

# --- Leading-v must not strip a component prefix (vclient-v… ≠ client-v…) ---
# Only client-v1.2.0 exists. Requesting vclient-v1.2.0 must not resolve client-v
# and emit KEEP/OK from unrelated shipping evidence.
repo_vclient="$TMP_ROOT/linear-1982-vclient-prefix-strip"
init_linear_git_repo "$repo_vclient"
cat > "$repo_vclient/CHANGELOG.md" <<'MD'
# Changelog

## [Unreleased]

## [client-v1.2.0] - 2026-10-15

- Client component ships LEA-999.
MD
"$REAL_GIT" -C "$repo_vclient" add CHANGELOG.md .ai-dev-workflow.yaml scripts
"$REAL_GIT" -C "$repo_vclient" commit -q -m "chore: client baseline"
"$REAL_GIT" -C "$repo_vclient" commit -q --allow-empty \
  -m "Merge pull request #73 from example/fix/LEA-998-client-prior"
sha_client_998="$("$REAL_GIT" -C "$repo_vclient" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_vclient" tag client-v1.1.0
"$REAL_GIT" -C "$repo_vclient" commit -q --allow-empty \
  -m "Merge pull request #74 from example/fix/LEA-999-client-current"
sha_client_999="$("$REAL_GIT" -C "$repo_vclient" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_vclient" tag client-v1.2.0
write_linear_scope_gh \
  "73|fix/LEA-998-client-prior|fix: LEA-998 client" \
  "74|fix/LEA-999-client-current|fix: LEA-999 client" \
  "commit:${sha_client_998}|73" \
  "commit:${sha_client_999}|74"
result="$(run_linear_scope_cleanup "$repo_vclient" vclient-v1.2.0 --from-changelog --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_1982_vclient_wrong_prefix_best_effort_exits_zero" "0" "$status"
run_contains "linear_1982_vclient_wrong_prefix_incomplete" \
  "RELEASE_SCOPE_INCOMPLETE reason=release_ref_unavailable" "$output"
run_not_contains "linear_1982_vclient_wrong_prefix_no_tracker" "TRACKER_ISSUES=" "$output"
run_not_contains "linear_1982_vclient_wrong_prefix_no_keep" "KEEP LEA-999" "$output"
run_not_contains "linear_1982_vclient_wrong_prefix_no_999" "LEA-999" "$output"
result="$(run_linear_scope_cleanup "$repo_vclient" client-v1.2.0 --from-changelog --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_1982_client_exact_prefix_exits_zero" "0" "$status"
run_contains "linear_1982_client_exact_prefix_proposes_999" \
  "TRACKER_ISSUES=LEA-999" "$output"
run_not_contains "linear_1982_client_exact_prefix_no_998" "LEA-998" "$output"

# --- Prerelease SemVer: rc.1 → rc.2 → stable ---
repo_pre="$TMP_ROOT/linear-1982-prerelease-semver"
init_linear_git_repo "$repo_pre"
cat > "$repo_pre/CHANGELOG.md" <<'MD'
# Changelog

## [Unreleased]

## [1.29.0] - 2026-10-20

- Stable ships LEA-303.
MD
"$REAL_GIT" -C "$repo_pre" add CHANGELOG.md .ai-dev-workflow.yaml scripts
"$REAL_GIT" -C "$repo_pre" commit -q -m "chore: baseline before rc"
"$REAL_GIT" -C "$repo_pre" tag v1.28.0
"$REAL_GIT" -C "$repo_pre" commit -q --allow-empty \
  -m "Merge pull request #80 from example/fix/LEA-301-rc1"
sha_rc1="$("$REAL_GIT" -C "$repo_pre" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_pre" tag v1.29.0-rc.1
"$REAL_GIT" -C "$repo_pre" commit -q --allow-empty \
  -m "Merge pull request #81 from example/fix/LEA-302-rc2"
sha_rc2="$("$REAL_GIT" -C "$repo_pre" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_pre" tag v1.29.0-rc.2
"$REAL_GIT" -C "$repo_pre" commit -q --allow-empty \
  -m "Merge pull request #82 from example/fix/LEA-303-stable"
sha_stable="$("$REAL_GIT" -C "$repo_pre" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_pre" tag v1.29.0
write_linear_scope_gh \
  "80|fix/LEA-301-rc1|fix: LEA-301 rc1" \
  "81|fix/LEA-302-rc2|fix: LEA-302 rc2" \
  "82|fix/LEA-303-stable|fix: LEA-303 stable" \
  "commit:${sha_rc1}|80" \
  "commit:${sha_rc2}|81" \
  "commit:${sha_stable}|82"
result="$(run_linear_scope_cleanup "$repo_pre" v1.29.0-rc.2 --from-changelog --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_1982_prerelease_rc2_exits_zero" "0" "$status"
run_contains "linear_1982_prerelease_rc2_proposes_302" "TRACKER_ISSUES=LEA-302" "$output"
run_not_contains "linear_1982_prerelease_rc2_no_301" "LEA-301" "$output"
run_not_contains "linear_1982_prerelease_rc2_no_stable" "LEA-303" "$output"
result="$(run_linear_scope_cleanup "$repo_pre" v1.29.0 --from-changelog --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_1982_prerelease_to_stable_exits_zero" "0" "$status"
run_contains "linear_1982_prerelease_to_stable_proposes_303" "TRACKER_ISSUES=LEA-303" "$output"
run_not_contains "linear_1982_prerelease_to_stable_no_rc1" "LEA-301" "$output"
run_not_contains "linear_1982_prerelease_to_stable_no_rc2" "LEA-302" "$output"

# --- Build metadata ignored for SemVer precedence ---
repo_build="$TMP_ROOT/linear-1982-build-metadata"
init_linear_git_repo "$repo_build"
cat > "$repo_build/CHANGELOG.md" <<'MD'
# Changelog

## [Unreleased]

## [1.29.0] - 2026-10-15

- Build metadata must not invent a prior boundary.
MD
"$REAL_GIT" -C "$repo_build" add CHANGELOG.md .ai-dev-workflow.yaml scripts
"$REAL_GIT" -C "$repo_build" commit -q -m "chore: baseline"
"$REAL_GIT" -C "$repo_build" commit -q --allow-empty \
  -m "Merge pull request #85 from example/fix/LEA-280-prior"
sha_build_280="$("$REAL_GIT" -C "$repo_build" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_build" tag v1.28.0
"$REAL_GIT" -C "$repo_build" commit -q --allow-empty \
  -m "Merge pull request #86 from example/fix/LEA-290-buildmeta"
sha_build_290="$("$REAL_GIT" -C "$repo_build" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_build" tag v1.29.0+build.1
"$REAL_GIT" -C "$repo_build" commit -q --allow-empty \
  -m "Merge pull request #87 from example/fix/LEA-302-release"
sha_build_302="$("$REAL_GIT" -C "$repo_build" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_build" tag v1.29.0+build.5
write_linear_scope_gh \
  "85|fix/LEA-280-prior|fix: LEA-280" \
  "86|fix/LEA-290-buildmeta|fix: LEA-290" \
  "87|fix/LEA-302-release|fix: LEA-302" \
  "commit:${sha_build_280}|85" \
  "commit:${sha_build_290}|86" \
  "commit:${sha_build_302}|87"
result="$(run_linear_scope_cleanup "$repo_build" v1.29.0+build.5 --from-changelog --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_1982_build_meta_exits_zero" "0" "$status"
run_contains "linear_1982_build_meta_proposes_302" "LEA-302" "$output"
run_contains "linear_1982_build_meta_tracker_issues" "TRACKER_ISSUES=" "$output"
# Equal-precedence build.1 must not bound the range; prior stable is v1.28.0.
run_contains "linear_1982_build_meta_includes_290_in_range" "LEA-290" "$output"
run_not_contains "linear_1982_build_meta_no_280" "LEA-280" "$output"

# --- Equal-precedence predecessors: co-pointing build tags → boundary OK ---
repo_build_same="$TMP_ROOT/linear-1982-build-meta-copoint"
init_linear_git_repo "$repo_build_same"
cat > "$repo_build_same/CHANGELOG.md" <<'MD'
# Changelog

## [Unreleased]

## [1.3.0] - 2026-10-15

- Co-pointing v1.2.0+aaa / v1.2.0+bbb at one commit.
MD
"$REAL_GIT" -C "$repo_build_same" add CHANGELOG.md .ai-dev-workflow.yaml scripts
"$REAL_GIT" -C "$repo_build_same" commit -q -m "chore: baseline"
"$REAL_GIT" -C "$repo_build_same" commit -q --allow-empty \
  -m "Merge pull request #170 from example/fix/LEA-700-prior"
sha_build_same_a="$("$REAL_GIT" -C "$repo_build_same" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_build_same" tag 'v1.2.0+aaa'
"$REAL_GIT" -C "$repo_build_same" tag 'v1.2.0+bbb'
"$REAL_GIT" -C "$repo_build_same" commit -q --allow-empty \
  -m "Merge pull request #171 from example/fix/LEA-710-current"
sha_build_same_c="$("$REAL_GIT" -C "$repo_build_same" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_build_same" tag v1.3.0
write_linear_scope_gh \
  "170|fix/LEA-700-prior|fix: LEA-700" \
  "171|fix/LEA-710-current|fix: LEA-710" \
  "commit:${sha_build_same_a}|170" \
  "commit:${sha_build_same_c}|171"
result="$(run_linear_scope_cleanup "$repo_build_same" v1.3.0 --from-changelog --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_1982_build_meta_copoint_exits_zero" "0" "$status"
run_contains "linear_1982_build_meta_copoint_proposes_710" "TRACKER_ISSUES=LEA-710" "$output"
run_not_contains "linear_1982_build_meta_copoint_no_700" "LEA-700" "$output"
run_not_contains "linear_1982_build_meta_copoint_no_ambiguous" \
  "ambiguous_previous_release_boundary" "$output"

# --- Equal-precedence predecessors at different SHAs → fail closed (order 1) ---
# ls-remote lists v1.2.0+aaa before v1.2.0+bbb; A earlier than B.
repo_build_ord1="$TMP_ROOT/linear-1982-build-meta-ambig-ord1"
init_linear_git_repo "$repo_build_ord1"
cat > "$repo_build_ord1/CHANGELOG.md" <<'MD'
# Changelog

## [Unreleased]

## [1.3.0] - 2026-10-15

- Equal-precedence v1.2.0+aaa@A and v1.2.0+bbb@B must fail closed.
MD
"$REAL_GIT" -C "$repo_build_ord1" add CHANGELOG.md .ai-dev-workflow.yaml scripts
"$REAL_GIT" -C "$repo_build_ord1" commit -q -m "chore: baseline"
"$REAL_GIT" -C "$repo_build_ord1" commit -q --allow-empty \
  -m "Merge pull request #172 from example/fix/LEA-800-at-a"
sha_build_ord1_a="$("$REAL_GIT" -C "$repo_build_ord1" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_build_ord1" tag 'v1.2.0+aaa'
"$REAL_GIT" -C "$repo_build_ord1" commit -q --allow-empty \
  -m "Merge pull request #173 from example/fix/LEA-810-at-b"
sha_build_ord1_b="$("$REAL_GIT" -C "$repo_build_ord1" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_build_ord1" tag 'v1.2.0+bbb'
"$REAL_GIT" -C "$repo_build_ord1" commit -q --allow-empty \
  -m "Merge pull request #174 from example/fix/LEA-820-at-c"
sha_build_ord1_c="$("$REAL_GIT" -C "$repo_build_ord1" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_build_ord1" tag v1.3.0
write_linear_scope_gh \
  "172|fix/LEA-800-at-a|fix: LEA-800" \
  "173|fix/LEA-810-at-b|fix: LEA-810" \
  "174|fix/LEA-820-at-c|fix: LEA-820" \
  "commit:${sha_build_ord1_a}|172" \
  "commit:${sha_build_ord1_b}|173" \
  "commit:${sha_build_ord1_c}|174"
result="$(run_linear_scope_cleanup "$repo_build_ord1" v1.3.0 --from-changelog --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_1982_build_meta_ambig_ord1_best_effort_exits_zero" "0" "$status"
run_contains "linear_1982_build_meta_ambig_ord1_incomplete" \
  "RELEASE_SCOPE_INCOMPLETE reason=ambiguous_previous_release_boundary" "$output"
run_not_contains "linear_1982_build_meta_ambig_ord1_no_tracker" "TRACKER_ISSUES=" "$output"
run_not_contains "linear_1982_build_meta_ambig_ord1_no_820" "LEA-820" "$output"

# --- Equal-precedence predecessors at different SHAs → fail closed (order 2) ---
# Reverse listing vs ord1: v1.2.0+aaa@B lists before v1.2.0+zzz@A alphabetically.
repo_build_ord2="$TMP_ROOT/linear-1982-build-meta-ambig-ord2"
init_linear_git_repo "$repo_build_ord2"
cat > "$repo_build_ord2/CHANGELOG.md" <<'MD'
# Changelog

## [Unreleased]

## [1.3.0] - 2026-10-15

- Listing order must not pick a predecessor when equal-precedence SHAs differ.
MD
"$REAL_GIT" -C "$repo_build_ord2" add CHANGELOG.md .ai-dev-workflow.yaml scripts
"$REAL_GIT" -C "$repo_build_ord2" commit -q -m "chore: baseline"
"$REAL_GIT" -C "$repo_build_ord2" commit -q --allow-empty \
  -m "Merge pull request #175 from example/fix/LEA-830-at-a"
sha_build_ord2_a="$("$REAL_GIT" -C "$repo_build_ord2" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_build_ord2" tag 'v1.2.0+zzz'
"$REAL_GIT" -C "$repo_build_ord2" commit -q --allow-empty \
  -m "Merge pull request #176 from example/fix/LEA-840-at-b"
sha_build_ord2_b="$("$REAL_GIT" -C "$repo_build_ord2" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_build_ord2" tag 'v1.2.0+aaa'
"$REAL_GIT" -C "$repo_build_ord2" commit -q --allow-empty \
  -m "Merge pull request #177 from example/fix/LEA-850-at-c"
sha_build_ord2_c="$("$REAL_GIT" -C "$repo_build_ord2" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_build_ord2" tag v1.3.0
write_linear_scope_gh \
  "175|fix/LEA-830-at-a|fix: LEA-830" \
  "176|fix/LEA-840-at-b|fix: LEA-840" \
  "177|fix/LEA-850-at-c|fix: LEA-850" \
  "commit:${sha_build_ord2_a}|175" \
  "commit:${sha_build_ord2_b}|176" \
  "commit:${sha_build_ord2_c}|177"
result="$(run_linear_scope_cleanup "$repo_build_ord2" v1.3.0 --from-changelog --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_1982_build_meta_ambig_ord2_best_effort_exits_zero" "0" "$status"
run_contains "linear_1982_build_meta_ambig_ord2_incomplete" \
  "RELEASE_SCOPE_INCOMPLETE reason=ambiguous_previous_release_boundary" "$output"
run_not_contains "linear_1982_build_meta_ambig_ord2_no_tracker" "TRACKER_ISSUES=" "$output"
run_not_contains "linear_1982_build_meta_ambig_ord2_no_850" "LEA-850" "$output"

# --- Linear component: tip/previous from evidence.component_tag, not branch suffix ---
# Branch product/release/v1.2.3 with tags product-v1.1.0 / product-v1.2.3 must bound
# at product-v1.1.0 (± --release-head / --inspect-targets). Missing component_tag fails closed.
repo_comp_tag_hub="$TMP_ROOT/linear-1982-comp-tag-hub"
repo_comp_tag_product="$TMP_ROOT/linear-1982-comp-tag-product"
mkdir -p "$repo_comp_tag_hub/scripts/development-workflow" "$repo_comp_tag_product"
cp "$REPO_ROOT/scripts/development-workflow/workflow-lib.sh" \
  "$repo_comp_tag_hub/scripts/development-workflow/workflow-lib.sh"
cp "$REPO_ROOT/scripts/development-workflow/prepare-release-post-merge-cleanup.sh" \
  "$repo_comp_tag_hub/scripts/development-workflow/prepare-release-post-merge-cleanup.sh"
cp "$REPO_ROOT/scripts/development-workflow/component-release-target.sh" \
  "$repo_comp_tag_hub/scripts/development-workflow/component-release-target.sh"
cp "$REPO_ROOT/scripts/development-workflow/workflow-config-resolver.py" \
  "$repo_comp_tag_hub/scripts/development-workflow/workflow-config-resolver.py"
chmod +x "$repo_comp_tag_hub/scripts/development-workflow/"*.sh
cat > "$repo_comp_tag_hub/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
mode: workflow_hub
issue_tracker:
  provider: linear

workflow_hub:
  product_repos:
    - name: product
      github_repo: example/product
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
cat > "$repo_comp_tag_hub/.ai-dev-workflow.local.yaml" <<YAML
product_repos:
  - name: product
    local_path: $repo_comp_tag_product
YAML
"$REAL_GIT" -C "$repo_comp_tag_hub" init -q -b main
configure_fixture_git_identity "$repo_comp_tag_hub"
"$REAL_GIT" -C "$repo_comp_tag_hub" commit -q --allow-empty -m "chore: hub baseline"
# Product checkout: product-v1.1.0 (prior) → in-range LEA-910 → product-v1.2.3 tip.
"$REAL_GIT" -C "$repo_comp_tag_product" init -q -b main
configure_fixture_git_identity "$repo_comp_tag_product"
"$REAL_GIT" -C "$repo_comp_tag_product" remote add origin "$repo_comp_tag_product"
mkdir -p "$repo_comp_tag_product/scripts/development-workflow"
cat > "$repo_comp_tag_product/CHANGELOG.md" <<'MD'
# Changelog

## [Unreleased]

## [product-v1.2.3] - 2026-10-15

- Component release ships LEA-910.
MD
"$REAL_GIT" -C "$repo_comp_tag_product" add CHANGELOG.md
"$REAL_GIT" -C "$repo_comp_tag_product" commit -q -m "chore: product baseline"
"$REAL_GIT" -C "$repo_comp_tag_product" commit -q --allow-empty \
  -m "Merge pull request #180 from example/fix/LEA-900-prior"
sha_comp_tag_900="$("$REAL_GIT" -C "$repo_comp_tag_product" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_comp_tag_product" tag product-v1.1.0
"$REAL_GIT" -C "$repo_comp_tag_product" commit -q --allow-empty \
  -m "Merge pull request #181 from example/fix/LEA-910-current"
sha_comp_tag_910="$("$REAL_GIT" -C "$repo_comp_tag_product" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_comp_tag_product" tag product-v1.2.3
"$REAL_GIT" -C "$repo_comp_tag_product" checkout -q -b release-base
"$REAL_GIT" -C "$repo_comp_tag_product" checkout -q -b product/release/v1.2.3
"$REAL_GIT" -C "$repo_comp_tag_product" checkout -q main
(
  cd "$repo_comp_tag_hub"
  target_json="$(./scripts/development-workflow/component-release-target.sh \
    --repo-root "$repo_comp_tag_hub" --repo product \
    --release-branch product/release/v1.2.3 --json)"
  jq -nS --argjson target "$target_json" \
    '{
      schema_version:"component_release_evidence.v1",
      target_binding:$target,
      release_branch:"product/release/v1.2.3",
      release_outcome:"completed",
      ci_outcome:"passed",
      deployment_outcome:"recorded",
      cleanup_outcome:"not_started",
      hub_tracker_ref:"#1982",
      component_tag:"product-v1.2.3"
    }' > "$repo_comp_tag_hub/component-release-evidence.json"
)
write_linear_scope_gh \
  "180|fix/LEA-900-prior|fix: LEA-900" \
  "181|fix/LEA-910-current|fix: LEA-910" \
  "commit:${sha_comp_tag_900}|180" \
  "commit:${sha_comp_tag_910}|181"
# Without --release-head: tip resolves product-v1.2.3 via component_tag.
result="$(run_linear_scope_cleanup "$repo_comp_tag_hub" product/release/v1.2.3 \
  --repo product --repo-root "$repo_comp_tag_hub" \
  --evidence-file "$repo_comp_tag_hub/component-release-evidence.json" \
  --from-changelog --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_1982_component_tag_cleanup_exits_zero" "0" "$status"
run_contains "linear_1982_component_tag_cleanup_proposes_910" "TRACKER_ISSUES=LEA-910" "$output"
run_not_contains "linear_1982_component_tag_cleanup_no_900" "LEA-900" "$output"
run_not_contains "linear_1982_component_tag_cleanup_no_first_release_false" \
  "release_ref_unavailable" "$output"
run_contains "linear_1982_component_tag_cleanup_version_basename" \
  "Release version: v1.2.3" "$output"
# --inspect-targets + --release-head: same product-v boundary.
result="$(run_linear_scope_inspect "$repo_comp_tag_hub" product/release/v1.2.3 \
  "$sha_comp_tag_910" --repo product --repo-root "$repo_comp_tag_hub" \
  --evidence-file "$repo_comp_tag_hub/component-release-evidence.json")"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_1982_component_tag_inspect_exits_zero" "0" "$status"
run_contains "linear_1982_component_tag_inspect_proposes_910" \
  "Linear --from-changelog scope from merged PRs in release range: LEA-910" "$output"
run_not_contains "linear_1982_component_tag_inspect_no_900" "LEA-900" "$output"
run_contains "linear_1982_component_tag_inspect_stub" "INSPECT_STUB_OK" "$output"
# Missing component_tag → fail closed (do not fall back to branch-suffix v1.2.3).
jq 'del(.component_tag)' "$repo_comp_tag_hub/component-release-evidence.json" \
  > "$repo_comp_tag_hub/component-release-evidence-no-tag.json"
result="$(run_linear_scope_cleanup "$repo_comp_tag_hub" product/release/v1.2.3 \
  --repo product --repo-root "$repo_comp_tag_hub" \
  --evidence-file "$repo_comp_tag_hub/component-release-evidence-no-tag.json" \
  --from-changelog --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_1982_component_tag_missing_best_effort_exits_zero" "0" "$status"
run_contains "linear_1982_component_tag_missing_incomplete" \
  "RELEASE_SCOPE_INCOMPLETE reason=component_tag_unavailable" "$output"
run_not_contains "linear_1982_component_tag_missing_no_tracker" "TRACKER_ISSUES=" "$output"
result="$(run_linear_scope_inspect "$repo_comp_tag_hub" product/release/v1.2.3 \
  "$sha_comp_tag_910" --repo product --repo-root "$repo_comp_tag_hub" \
  --evidence-file "$repo_comp_tag_hub/component-release-evidence-no-tag.json")"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_1982_component_tag_missing_inspect_exits_nonzero" "1" "$status"
run_contains "linear_1982_component_tag_missing_inspect_incomplete" \
  "RELEASE_SCOPE_INCOMPLETE reason=component_tag_unavailable" "$output"

# --- chore/ merged PR is shipping evidence; release/ branch is skipped ---
repo_chore="$TMP_ROOT/linear-1982-chore-and-release"
init_linear_git_repo "$repo_chore"
cat > "$repo_chore/CHANGELOG.md" <<'MD'
# Changelog

## [Unreleased]

## [1.29.0] - 2026-10-15

- Ships chore work and a release branch merge.
MD
"$REAL_GIT" -C "$repo_chore" add CHANGELOG.md .ai-dev-workflow.yaml scripts
"$REAL_GIT" -C "$repo_chore" commit -q -m "chore: baseline before v1.28.0"
"$REAL_GIT" -C "$repo_chore" tag v1.28.0
"$REAL_GIT" -C "$repo_chore" commit -q --allow-empty \
  -m "Merge pull request #90 from example/chore/LEA-346-dependency-fix"
sha_chore="$("$REAL_GIT" -C "$repo_chore" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_chore" commit -q --allow-empty \
  -m "Merge pull request #91 from example/release/v1.29.0"
sha_rel="$("$REAL_GIT" -C "$repo_chore" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_chore" commit -q --allow-empty \
  -m "Merge pull request #92 from example/spec/LEA-298-docs"
sha_spec_chore="$("$REAL_GIT" -C "$repo_chore" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_chore" tag v1.29.0
write_linear_scope_gh \
  "90|chore/LEA-346-dependency-fix|chore: LEA-346 dependency bump" \
  "91|release/v1.29.0|Release v1.29.0 LEA-999" \
  "92|spec/LEA-298-docs|docs: LEA-298" \
  "commit:${sha_chore}|90" \
  "commit:${sha_rel}|91" \
  "commit:${sha_spec_chore}|92"
result="$(run_linear_scope_cleanup "$repo_chore" v1.29.0 --from-changelog --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_1982_chore_exits_zero" "0" "$status"
run_contains "linear_1982_chore_proposes_346" "TRACKER_ISSUES=LEA-346" "$output"
run_contains "linear_1982_release_branch_skipped" \
  "RELEASE_SCOPE_SKIPPED issue=LEA-999 reason=release_or_backport_branch_pr" "$output"
run_contains "linear_1982_spec_still_excluded" \
  "RELEASE_SCOPE_SKIPPED issue=LEA-298 reason=documentation_stage_pr_only" "$output"
run_not_contains "linear_1982_chore_no_999_in_issues" "TRACKER_ISSUES=LEA-999" "$output"
run_not_contains "linear_1982_chore_no_298_in_issues" "TRACKER_ISSUES=LEA-298" "$output"

# --- --release-head: identity from requested version, not co-pointing mobile tag ---
repo_rh_mobile="$TMP_ROOT/linear-1982-release-head-mobile"
init_linear_git_repo "$repo_rh_mobile"
cat > "$repo_rh_mobile/CHANGELOG.md" <<'MD'
# Changelog

## [Unreleased]

## [1.1.0] - 2026-10-15

- Requested v1.1.0 must not adopt co-pointing mobile-v1.1.0 identity.
MD
"$REAL_GIT" -C "$repo_rh_mobile" add CHANGELOG.md .ai-dev-workflow.yaml scripts
"$REAL_GIT" -C "$repo_rh_mobile" commit -q -m "chore: baseline"
"$REAL_GIT" -C "$repo_rh_mobile" commit -q --allow-empty \
  -m "Merge pull request #100 from example/fix/LEA-100-v10"
sha_rh_v10="$("$REAL_GIT" -C "$repo_rh_mobile" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_rh_mobile" tag v1.0.0
"$REAL_GIT" -C "$repo_rh_mobile" commit -q --allow-empty \
  -m "Merge pull request #101 from example/fix/LEA-200-between"
sha_rh_200="$("$REAL_GIT" -C "$repo_rh_mobile" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_rh_mobile" commit -q --allow-empty \
  -m "Merge pull request #102 from example/fix/LEA-400-mobile10"
sha_rh_m10="$("$REAL_GIT" -C "$repo_rh_mobile" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_rh_mobile" tag mobile-v1.0.0
"$REAL_GIT" -C "$repo_rh_mobile" commit -q --allow-empty \
  -m "Merge pull request #103 from example/fix/LEA-410-tip"
sha_rh_tip="$("$REAL_GIT" -C "$repo_rh_mobile" rev-parse HEAD)"
# Co-pointing tags at the release tip — buggy code adopted mobile-v1.1.0.
"$REAL_GIT" -C "$repo_rh_mobile" tag v1.1.0
"$REAL_GIT" -C "$repo_rh_mobile" tag mobile-v1.1.0
write_linear_scope_gh \
  "100|fix/LEA-100-v10|fix: LEA-100" \
  "101|fix/LEA-200-between|fix: LEA-200" \
  "102|fix/LEA-400-mobile10|fix: LEA-400" \
  "103|fix/LEA-410-tip|fix: LEA-410" \
  "commit:${sha_rh_v10}|100" \
  "commit:${sha_rh_200}|101" \
  "commit:${sha_rh_m10}|102" \
  "commit:${sha_rh_tip}|103"
result="$(run_linear_scope_inspect "$repo_rh_mobile" v1.1.0 "$sha_rh_tip")"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_1982_rh_mobile_exits_zero" "0" "$status"
# v-prefix previous is v1.0.0 → LEA-200 is in range (would be excluded if mobile-v1.0.0 bound).
run_contains "linear_1982_rh_mobile_proposes_200" "LEA-200" "$output"
run_contains "linear_1982_rh_mobile_proposes_410" "LEA-410" "$output"
run_not_contains "linear_1982_rh_mobile_no_incomplete" "previous_release_boundary_unavailable" "$output"

# --- --release-head: ignore co-pointing same-core tag that drops prerelease ---
repo_rh_pre="$TMP_ROOT/linear-1982-release-head-prerelease"
init_linear_git_repo "$repo_rh_pre"
cat > "$repo_rh_pre/CHANGELOG.md" <<'MD'
# Changelog

## [Unreleased]

## [1.2.3] - 2026-10-15

- Requested v1.2.3-rc.2 must not adopt co-pointing v1.2.3 identity.
MD
"$REAL_GIT" -C "$repo_rh_pre" add CHANGELOG.md .ai-dev-workflow.yaml scripts
"$REAL_GIT" -C "$repo_rh_pre" commit -q -m "chore: baseline"
"$REAL_GIT" -C "$repo_rh_pre" tag v1.2.2
"$REAL_GIT" -C "$repo_rh_pre" commit -q --allow-empty \
  -m "Merge pull request #110 from example/fix/LEA-301-rc1"
sha_rh_rc1="$("$REAL_GIT" -C "$repo_rh_pre" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_rh_pre" tag v1.2.3-rc.1
"$REAL_GIT" -C "$repo_rh_pre" commit -q --allow-empty \
  -m "Merge pull request #111 from example/fix/LEA-302-rc2"
sha_rh_rc2="$("$REAL_GIT" -C "$repo_rh_pre" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_rh_pre" tag v1.2.3-rc.2
# Same commit also has stable v1.2.3 (same MAJOR.MINOR.PATCH core) — must not win.
"$REAL_GIT" -C "$repo_rh_pre" tag v1.2.3
write_linear_scope_gh \
  "110|fix/LEA-301-rc1|fix: LEA-301" \
  "111|fix/LEA-302-rc2|fix: LEA-302" \
  "commit:${sha_rh_rc1}|110" \
  "commit:${sha_rh_rc2}|111"
result="$(run_linear_scope_inspect "$repo_rh_pre" v1.2.3-rc.2 "$sha_rh_rc2")"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_1982_rh_prerelease_exits_zero" "0" "$status"
# --inspect-targets may not emit TRACKER_ISSUES=; scope appears in merge-budget args / logs.
run_contains "linear_1982_rh_prerelease_proposes_302" "LEA-302" "$output"
run_not_contains "linear_1982_rh_prerelease_no_301" "LEA-301" "$output"
# Bare version argument (no leading v): must not adopt co-pointing v1.2.3 via
# points-at (that bound previous=rc.2 at the tip and emptied the range).
result="$(run_linear_scope_inspect "$repo_rh_pre" 1.2.3-rc.2 "$sha_rh_rc2")"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_1982_rh_bare_rc_exits_zero" "0" "$status"
run_contains "linear_1982_rh_bare_rc_still_proposes_302" "LEA-302" "$output"

# --- Bare-tag namespace (1.0.0 / 1.1.0): identical boundary with and without --release-head ---
# Regression: shell may normalize the version arg to v1.1.0; --release-head must
# still adopt the repo's bare tag namespace so previous=1.0.0 (not first_release).
repo_bare="$TMP_ROOT/linear-1982-bare-tag-namespace"
init_linear_git_repo "$repo_bare"
cat > "$repo_bare/CHANGELOG.md" <<'MD'
# Changelog

## [Unreleased]

## [1.1.0] - 2026-10-15

- Bare tags 1.0.0 → 1.1.0; LEA-500 prior, LEA-510 in range.
MD
"$REAL_GIT" -C "$repo_bare" add CHANGELOG.md .ai-dev-workflow.yaml scripts
"$REAL_GIT" -C "$repo_bare" commit -q -m "chore: bare baseline"
"$REAL_GIT" -C "$repo_bare" commit -q --allow-empty \
  -m "Merge pull request #130 from example/fix/LEA-500-bare-prior"
sha_bare_500="$("$REAL_GIT" -C "$repo_bare" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_bare" tag 1.0.0
"$REAL_GIT" -C "$repo_bare" commit -q --allow-empty \
  -m "Merge pull request #131 from example/fix/LEA-510-bare-current"
sha_bare_510="$("$REAL_GIT" -C "$repo_bare" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_bare" tag 1.1.0
write_linear_scope_gh \
  "130|fix/LEA-500-bare-prior|fix: LEA-500" \
  "131|fix/LEA-510-bare-current|fix: LEA-510" \
  "commit:${sha_bare_500}|130" \
  "commit:${sha_bare_510}|131"

# Cleanup without --release-head (tip = refs/tags/1.1.0 → previous 1.0.0).
result="$(run_linear_scope_cleanup "$repo_bare" 1.1.0 --from-changelog --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_1982_bare_cleanup_exits_zero" "0" "$status"
run_contains "linear_1982_bare_cleanup_proposes_510" "TRACKER_ISSUES=LEA-510" "$output"
run_not_contains "linear_1982_bare_cleanup_no_500_tracker" "TRACKER_ISSUES=LEA-500" "$output"
run_not_contains "linear_1982_bare_cleanup_no_incomplete" "previous_release_boundary_unavailable" "$output"
run_not_contains "linear_1982_bare_cleanup_no_ambiguous" "ambiguous_release_tag_namespace" "$output"

# Inspect with --release-head (same bare namespace / previous=1.0.0; not first_release).
result="$(run_linear_scope_inspect "$repo_bare" 1.1.0 "$sha_bare_510")"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_1982_bare_inspect_rh_exits_zero" "0" "$status"
run_contains "linear_1982_bare_inspect_rh_proposes_510" \
  "Linear --from-changelog scope from merged PRs in release range: LEA-510" "$output"
run_contains "linear_1982_bare_inspect_rh_skips_500" \
  "RELEASE_SCOPE_SKIPPED issue=LEA-500 reason=changelog_mention_without_merged_pr" "$output"
run_not_contains "linear_1982_bare_inspect_rh_no_incomplete" "previous_release_boundary_unavailable" "$output"

# Shell-normalized v1.1.0 spelling against bare tags must still bind previous=1.0.0.
result="$(run_linear_scope_inspect "$repo_bare" v1.1.0 "$sha_bare_510")"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_1982_bare_inspect_varg_exits_zero" "0" "$status"
run_contains "linear_1982_bare_inspect_varg_proposes_510" \
  "Linear --from-changelog scope from merged PRs in release range: LEA-510" "$output"
run_contains "linear_1982_bare_inspect_varg_skips_500" \
  "RELEASE_SCOPE_SKIPPED issue=LEA-500 reason=changelog_mention_without_merged_pr" "$output"

# --- Ambiguous bare + v tags at different SHAs → fail closed ---
repo_ambig="$TMP_ROOT/linear-1982-ambiguous-tag-namespace"
init_linear_git_repo "$repo_ambig"
cat > "$repo_ambig/CHANGELOG.md" <<'MD'
# Changelog

## [Unreleased]

## [1.1.0] - 2026-10-15

- Both 1.1.0 and v1.1.0 exist on different commits.
MD
"$REAL_GIT" -C "$repo_ambig" add CHANGELOG.md .ai-dev-workflow.yaml scripts
"$REAL_GIT" -C "$repo_ambig" commit -q -m "chore: ambig baseline"
"$REAL_GIT" -C "$repo_ambig" commit -q --allow-empty \
  -m "Merge pull request #140 from example/fix/LEA-600-ambig-a"
sha_ambig_a="$("$REAL_GIT" -C "$repo_ambig" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_ambig" tag 1.1.0
"$REAL_GIT" -C "$repo_ambig" commit -q --allow-empty \
  -m "Merge pull request #141 from example/fix/LEA-610-ambig-b"
sha_ambig_b="$("$REAL_GIT" -C "$repo_ambig" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_ambig" tag v1.1.0
write_linear_scope_gh \
  "140|fix/LEA-600-ambig-a|fix: LEA-600" \
  "141|fix/LEA-610-ambig-b|fix: LEA-610" \
  "commit:${sha_ambig_a}|140" \
  "commit:${sha_ambig_b}|141"
# Cleanup path (tip resolves a tag, then counterpart SHA disagrees).
result="$(run_linear_scope_cleanup "$repo_ambig" 1.1.0 --from-changelog --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_1982_ambiguous_cleanup_best_effort_exits_zero" "0" "$status"
run_contains "linear_1982_ambiguous_cleanup_incomplete" \
  "RELEASE_SCOPE_INCOMPLETE reason=ambiguous_release_tag_namespace" "$output"
run_not_contains "linear_1982_ambiguous_cleanup_no_tracker" "TRACKER_ISSUES=" "$output"
result="$(run_linear_scope_cleanup "$repo_ambig" 1.1.0 --from-changelog)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_1982_ambiguous_cleanup_exits_nonzero" "1" "$status"
run_contains "linear_1982_ambiguous_cleanup_hard_incomplete" \
  "RELEASE_SCOPE_INCOMPLETE reason=ambiguous_release_tag_namespace" "$output"
# Inspect + --release-head path (same fail-closed reason).
result="$(run_linear_scope_inspect "$repo_ambig" 1.1.0 "$sha_ambig_b")"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_1982_ambiguous_inspect_exits_nonzero" "1" "$status"
run_contains "linear_1982_ambiguous_inspect_incomplete" \
  "RELEASE_SCOPE_INCOMPLETE reason=ambiguous_release_tag_namespace" "$output"

# --- Local tags must not mask remote namespace disagreement ---
# local 1.1.0=A, v1.1.0=A; remote 1.1.0=A, v1.1.0=B → fail closed.
repo_mask_src="$TMP_ROOT/linear-1982-local-mask-src"
repo_mask_bare="$TMP_ROOT/linear-1982-local-mask-bare.git"
repo_mask="$TMP_ROOT/linear-1982-local-mask"
repo_mask_push="$TMP_ROOT/linear-1982-local-mask-push"
init_linear_git_repo "$repo_mask_src"
cat > "$repo_mask_src/CHANGELOG.md" <<'MD'
# Changelog

## [Unreleased]

## [1.1.0] - 2026-10-15

- Local agreement must not hide a remote v-tag on a different SHA.
MD
"$REAL_GIT" -C "$repo_mask_src" add CHANGELOG.md .ai-dev-workflow.yaml scripts
"$REAL_GIT" -C "$repo_mask_src" commit -q -m "chore: mask baseline"
"$REAL_GIT" -C "$repo_mask_src" commit -q --allow-empty \
  -m "Merge pull request #150 from example/fix/LEA-620-mask-a"
sha_mask_a="$("$REAL_GIT" -C "$repo_mask_src" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_mask_src" tag 1.1.0
"$REAL_GIT" -C "$repo_mask_src" tag v1.1.0
"$REAL_GIT" clone -q --bare "file://${repo_mask_src}" "$repo_mask_bare"
"$REAL_GIT" clone -q "file://${repo_mask_bare}" "$repo_mask"
"$REAL_GIT" clone -q "file://${repo_mask_bare}" "$repo_mask_push"
configure_fixture_git_identity "$repo_mask_push"
"$REAL_GIT" -C "$repo_mask_push" commit -q --allow-empty \
  -m "Merge pull request #151 from example/fix/LEA-630-mask-b"
sha_mask_b="$("$REAL_GIT" -C "$repo_mask_push" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_mask_push" tag -f v1.1.0
"$REAL_GIT" -C "$repo_mask_push" push -q --force origin refs/tags/v1.1.0
# Working tree still has both local tags at A; remote v1.1.0 is now B.
mkdir -p "$repo_mask/scripts/development-workflow"
cp "$REPO_ROOT/scripts/development-workflow/workflow-lib.sh" \
  "$repo_mask/scripts/development-workflow/workflow-lib.sh"
cp "$REPO_ROOT/scripts/development-workflow/prepare-release-post-merge-cleanup.sh" \
  "$repo_mask/scripts/development-workflow/prepare-release-post-merge-cleanup.sh"
chmod +x "$repo_mask/scripts/development-workflow/prepare-release-post-merge-cleanup.sh"
cat > "$repo_mask/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
issue_tracker:
  provider: linear
YAML
"$REAL_GIT" -C "$repo_mask" add CHANGELOG.md .ai-dev-workflow.yaml scripts 2>/dev/null || true
write_linear_scope_gh \
  "150|fix/LEA-620-mask-a|fix: LEA-620" \
  "151|fix/LEA-630-mask-b|fix: LEA-630" \
  "commit:${sha_mask_a}|150" \
  "commit:${sha_mask_b}|151"
result="$(run_linear_scope_cleanup "$repo_mask" 1.1.0 --from-changelog --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_1982_local_mask_remote_best_effort_exits_zero" "0" "$status"
run_contains "linear_1982_local_mask_remote_incomplete" \
  "RELEASE_SCOPE_INCOMPLETE reason=ambiguous_release_tag_namespace" "$output"
run_not_contains "linear_1982_local_mask_remote_no_tracker" "TRACKER_ISSUES=" "$output"
result="$(run_linear_scope_inspect "$repo_mask" 1.1.0 "$sha_mask_a")"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_1982_local_mask_remote_inspect_exits_nonzero" "1" "$status"
run_contains "linear_1982_local_mask_remote_inspect_incomplete" \
  "RELEASE_SCOPE_INCOMPLETE reason=ambiguous_release_tag_namespace" "$output"

# --- Missing local release tags must not bypass remote namespace conflicts ---
# remote 1.1.0=A, v1.1.0=B; no local tags → ambiguous with and without --release-head
# (not release_ref_unavailable on the cleanup path).
repo_nolt_src="$TMP_ROOT/linear-1982-no-local-tags-src"
repo_nolt_bare="$TMP_ROOT/linear-1982-no-local-tags-bare.git"
repo_nolt="$TMP_ROOT/linear-1982-no-local-tags"
init_linear_git_repo "$repo_nolt_src"
cat > "$repo_nolt_src/CHANGELOG.md" <<'MD'
# Changelog

## [Unreleased]

## [1.1.0] - 2026-10-15

- Conflicting remote bare/v tags; working tree has no release tags.
MD
"$REAL_GIT" -C "$repo_nolt_src" add CHANGELOG.md .ai-dev-workflow.yaml scripts
"$REAL_GIT" -C "$repo_nolt_src" commit -q -m "chore: no-local-tags baseline"
"$REAL_GIT" -C "$repo_nolt_src" commit -q --allow-empty \
  -m "Merge pull request #160 from example/fix/LEA-640-nolt-a"
sha_nolt_a="$("$REAL_GIT" -C "$repo_nolt_src" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_nolt_src" tag 1.1.0
"$REAL_GIT" -C "$repo_nolt_src" commit -q --allow-empty \
  -m "Merge pull request #161 from example/fix/LEA-650-nolt-b"
sha_nolt_b="$("$REAL_GIT" -C "$repo_nolt_src" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_nolt_src" tag v1.1.0
"$REAL_GIT" clone -q --bare "file://${repo_nolt_src}" "$repo_nolt_bare"
"$REAL_GIT" clone -q "file://${repo_nolt_bare}" "$repo_nolt"
# Drop local release tags so tip resolution fails; remotes still conflict.
"$REAL_GIT" -C "$repo_nolt" tag -d 1.1.0
"$REAL_GIT" -C "$repo_nolt" tag -d v1.1.0
mkdir -p "$repo_nolt/scripts/development-workflow"
cp "$REPO_ROOT/scripts/development-workflow/workflow-lib.sh" \
  "$repo_nolt/scripts/development-workflow/workflow-lib.sh"
cp "$REPO_ROOT/scripts/development-workflow/prepare-release-post-merge-cleanup.sh" \
  "$repo_nolt/scripts/development-workflow/prepare-release-post-merge-cleanup.sh"
chmod +x "$repo_nolt/scripts/development-workflow/prepare-release-post-merge-cleanup.sh"
cat > "$repo_nolt/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
issue_tracker:
  provider: linear
YAML
"$REAL_GIT" -C "$repo_nolt" add CHANGELOG.md .ai-dev-workflow.yaml scripts 2>/dev/null || true
write_linear_scope_gh \
  "160|fix/LEA-640-nolt-a|fix: LEA-640" \
  "161|fix/LEA-650-nolt-b|fix: LEA-650" \
  "commit:${sha_nolt_a}|160" \
  "commit:${sha_nolt_b}|161"
result="$(run_linear_scope_cleanup "$repo_nolt" 1.1.0 --from-changelog --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_1982_no_local_tags_remote_conflict_best_effort_exits_zero" "0" "$status"
run_contains "linear_1982_no_local_tags_remote_conflict_incomplete" \
  "RELEASE_SCOPE_INCOMPLETE reason=ambiguous_release_tag_namespace" "$output"
run_not_contains "linear_1982_no_local_tags_remote_conflict_not_unavailable" \
  "release_ref_unavailable" "$output"
run_not_contains "linear_1982_no_local_tags_remote_conflict_no_tracker" \
  "TRACKER_ISSUES=" "$output"
result="$(run_linear_scope_inspect "$repo_nolt" 1.1.0 "$sha_nolt_b")"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_1982_no_local_tags_remote_conflict_inspect_exits_nonzero" "1" "$status"
run_contains "linear_1982_no_local_tags_remote_conflict_inspect_incomplete" \
  "RELEASE_SCOPE_INCOMPLETE reason=ambiguous_release_tag_namespace" "$output"

# --- Both spellings remote (same SHA), only bare local: as-given namespace ± --release-head ---
# Distinct bare vs v predecessors: v request → previous=v1.0.0 (LEA-710 only);
# bare request → previous=1.0.0 (LEA-705 and LEA-710). Branch stays release/v1.1.0.
repo_parity_src="$TMP_ROOT/linear-1982-namespace-parity-src"
repo_parity_bare="$TMP_ROOT/linear-1982-namespace-parity-bare.git"
repo_parity="$TMP_ROOT/linear-1982-namespace-parity"
init_linear_git_repo "$repo_parity_src"
cat > "$repo_parity_src/CHANGELOG.md" <<'MD'
# Changelog

## [Unreleased]

## [1.1.0] - 2026-10-15

- Local bare-only tip; remote has both spellings at the same SHA.
MD
"$REAL_GIT" -C "$repo_parity_src" add CHANGELOG.md .ai-dev-workflow.yaml scripts
"$REAL_GIT" -C "$repo_parity_src" commit -q -m "chore: parity baseline"
"$REAL_GIT" -C "$repo_parity_src" commit -q --allow-empty \
  -m "Merge pull request #160 from example/fix/LEA-700-bare-pred"
sha_parity_700="$("$REAL_GIT" -C "$repo_parity_src" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_parity_src" tag 1.0.0
"$REAL_GIT" -C "$repo_parity_src" commit -q --allow-empty \
  -m "Merge pull request #161 from example/fix/LEA-705-v-pred"
sha_parity_705="$("$REAL_GIT" -C "$repo_parity_src" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_parity_src" tag v1.0.0
"$REAL_GIT" -C "$repo_parity_src" commit -q --allow-empty \
  -m "Merge pull request #162 from example/fix/LEA-710-tip"
sha_parity_710="$("$REAL_GIT" -C "$repo_parity_src" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_parity_src" tag 1.1.0
"$REAL_GIT" -C "$repo_parity_src" tag v1.1.0
"$REAL_GIT" clone -q --bare "file://${repo_parity_src}" "$repo_parity_bare"
"$REAL_GIT" clone -q "file://${repo_parity_bare}" "$repo_parity"
# Local keeps only bare tip/predecessor spellings; remote still has both.
"$REAL_GIT" -C "$repo_parity" tag -d v1.0.0 >/dev/null
"$REAL_GIT" -C "$repo_parity" tag -d v1.1.0 >/dev/null
mkdir -p "$repo_parity/scripts/development-workflow"
cp "$REPO_ROOT/scripts/development-workflow/workflow-lib.sh" \
  "$repo_parity/scripts/development-workflow/workflow-lib.sh"
cp "$REPO_ROOT/scripts/development-workflow/prepare-release-post-merge-cleanup.sh" \
  "$repo_parity/scripts/development-workflow/prepare-release-post-merge-cleanup.sh"
chmod +x "$repo_parity/scripts/development-workflow/prepare-release-post-merge-cleanup.sh"
cat > "$repo_parity/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
issue_tracker:
  provider: linear
YAML
write_linear_scope_gh \
  "160|fix/LEA-700-bare-pred|fix: LEA-700" \
  "161|fix/LEA-705-v-pred|fix: LEA-705" \
  "162|fix/LEA-710-tip|fix: LEA-710" \
  "commit:${sha_parity_700}|160" \
  "commit:${sha_parity_705}|161" \
  "commit:${sha_parity_710}|162"
# v request → v-namespace → previous=v1.0.0 → LEA-710 only.
result="$(run_linear_scope_cleanup "$repo_parity" v1.1.0 --from-changelog --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_1982_parity_cleanup_v_exits_zero" "0" "$status"
run_contains "linear_1982_parity_cleanup_v_version_spelling" "Release version: v1.1.0" "$output"
run_contains "linear_1982_parity_cleanup_v_branch" "Release branch: release/v1.1.0" "$output"
run_contains "linear_1982_parity_cleanup_v_proposes_710" "TRACKER_ISSUES=LEA-710" "$output"
run_not_contains "linear_1982_parity_cleanup_v_no_705" "TRACKER_ISSUES=LEA-705" "$output"
run_not_contains "linear_1982_parity_cleanup_v_no_700" "TRACKER_ISSUES=LEA-700" "$output"
result="$(run_linear_scope_inspect "$repo_parity" v1.1.0 "$sha_parity_710")"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_1982_parity_inspect_v_exits_zero" "0" "$status"
run_contains "linear_1982_parity_inspect_v_proposes_710" \
  "Linear --from-changelog scope from merged PRs in release range: LEA-710" "$output"
run_not_contains "linear_1982_parity_inspect_v_no_705_scope" \
  "scope from merged PRs in release range: LEA-705" "$output"
# Bare request: RELEASE_VERSION stays v1.1.0 (GitHub-compatible), but Linear
# namespace uses requested spelling 1.1.0 → bare predecessor → LEA-705+LEA-710.
result="$(run_linear_scope_cleanup "$repo_parity" 1.1.0 --from-changelog --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_1982_parity_cleanup_bare_exits_zero" "0" "$status"
run_contains "linear_1982_parity_cleanup_bare_version_spelling" "Release version: v1.1.0" "$output"
run_contains "linear_1982_parity_cleanup_bare_branch" "Release branch: release/v1.1.0" "$output"
run_contains "linear_1982_parity_cleanup_bare_proposes_710" "LEA-710" "$output"
run_contains "linear_1982_parity_cleanup_bare_proposes_705" "LEA-705" "$output"
run_not_contains "linear_1982_parity_cleanup_bare_no_700" "TRACKER_ISSUES=LEA-700" "$output"
result="$(run_linear_scope_inspect "$repo_parity" 1.1.0 "$sha_parity_710")"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_1982_parity_inspect_bare_exits_zero" "0" "$status"
run_contains "linear_1982_parity_inspect_bare_version_spelling" "Release version: v1.1.0" "$output"
run_contains "linear_1982_parity_inspect_bare_proposes_710" "LEA-710" "$output"
run_contains "linear_1982_parity_inspect_bare_proposes_705" "LEA-705" "$output"

# --- Invalid SemVer prerelease tags cannot define the boundary ---
repo_bad_pre="$TMP_ROOT/linear-1982-invalid-prerelease-tag"
init_linear_git_repo "$repo_bad_pre"
cat > "$repo_bad_pre/CHANGELOG.md" <<'MD'
# Changelog

## [Unreleased]

## [1.2.3] - 2026-10-15

- Invalid leading-zero prerelease tags are ignored.
MD
"$REAL_GIT" -C "$repo_bad_pre" add CHANGELOG.md .ai-dev-workflow.yaml scripts
"$REAL_GIT" -C "$repo_bad_pre" commit -q -m "chore: baseline"
"$REAL_GIT" -C "$repo_bad_pre" commit -q --allow-empty \
  -m "Merge pull request #120 from example/fix/LEA-280-valid-prior"
sha_bad_280="$("$REAL_GIT" -C "$repo_bad_pre" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_bad_pre" tag v1.2.2
"$REAL_GIT" -C "$repo_bad_pre" commit -q --allow-empty \
  -m "Merge pull request #121 from example/fix/LEA-290-invalid-pre"
sha_bad_290="$("$REAL_GIT" -C "$repo_bad_pre" rev-parse HEAD)"
# Invalid numeric prerelease (leading zero) — must not become the boundary.
"$REAL_GIT" -C "$repo_bad_pre" tag v1.2.3-01
"$REAL_GIT" -C "$repo_bad_pre" tag v1.2.3-alpha.01
"$REAL_GIT" -C "$repo_bad_pre" commit -q --allow-empty \
  -m "Merge pull request #122 from example/fix/LEA-302-release"
sha_bad_302="$("$REAL_GIT" -C "$repo_bad_pre" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_bad_pre" tag v1.2.3
write_linear_scope_gh \
  "120|fix/LEA-280-valid-prior|fix: LEA-280" \
  "121|fix/LEA-290-invalid-pre|fix: LEA-290" \
  "122|fix/LEA-302-release|fix: LEA-302" \
  "commit:${sha_bad_280}|120" \
  "commit:${sha_bad_290}|121" \
  "commit:${sha_bad_302}|122"
result="$(run_linear_scope_cleanup "$repo_bad_pre" v1.2.3 --from-changelog --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_1982_invalid_pre_exits_zero" "0" "$status"
run_contains "linear_1982_invalid_pre_ignored_01" \
  "SEMVER_TAG_IGNORED tag=v1.2.3-01 reason=invalid_prerelease_identifier" "$output"
run_contains "linear_1982_invalid_pre_ignored_alpha" \
  "SEMVER_TAG_IGNORED tag=v1.2.3-alpha.01 reason=invalid_prerelease_identifier" "$output"
# Boundary is v1.2.2 (not the invalid tags) → LEA-290 and LEA-302 in range.
run_contains "linear_1982_invalid_pre_proposes_302" "LEA-302" "$output"
run_contains "linear_1982_invalid_pre_includes_290" "LEA-290" "$output"
run_not_contains "linear_1982_invalid_pre_no_280" "LEA-280" "$output"

# --- Linear: missing CHANGELOG version section → still derive from merged PRs ---
repo_miss_section="$TMP_ROOT/linear-1982-missing-section"
init_linear_git_repo "$repo_miss_section"
cat > "$repo_miss_section/CHANGELOG.md" <<'MD'
# Changelog

## [Unreleased]

## [1.28.0] - 2026-10-01

- Older entry; current release section intentionally absent.
MD
"$REAL_GIT" -C "$repo_miss_section" add CHANGELOG.md .ai-dev-workflow.yaml scripts
"$REAL_GIT" -C "$repo_miss_section" commit -q -m "chore: baseline before v1.28.0"
"$REAL_GIT" -C "$repo_miss_section" tag v1.28.0
"$REAL_GIT" -C "$repo_miss_section" commit -q --allow-empty \
  -m "Merge pull request #88 from example/fix/LEA-302-billing-fix"
sha_miss_section="$("$REAL_GIT" -C "$repo_miss_section" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_miss_section" tag v1.29.0
write_linear_scope_gh \
  "88|fix/LEA-302-billing-fix|fix(billing): LEA-302" \
  "commit:${sha_miss_section}|88"
result="$(run_linear_scope_cleanup "$repo_miss_section" v1.29.0 --from-changelog --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_1982_missing_section_exits_zero" "0" "$status"
run_contains "linear_1982_missing_section_diagnostic" \
  "CHANGELOG_SECTION_UNAVAILABLE version=v1.29.0 (Linear scope derived from merged PRs only)" \
  "$output"
run_contains "linear_1982_missing_section_proposes_302" "TRACKER_ISSUES=LEA-302" "$output"
run_not_contains "linear_1982_missing_section_no_changelog_unavailable" \
  "REASON=changelog_scope_unavailable" "$output"

# --- Linear: missing CHANGELOG.md file → still derive from merged PRs ---
repo_miss_file="$TMP_ROOT/linear-1982-missing-file"
init_linear_git_repo "$repo_miss_file"
"$REAL_GIT" -C "$repo_miss_file" add .ai-dev-workflow.yaml scripts
"$REAL_GIT" -C "$repo_miss_file" commit -q -m "chore: baseline before v1.28.0"
"$REAL_GIT" -C "$repo_miss_file" tag v1.28.0
"$REAL_GIT" -C "$repo_miss_file" commit -q --allow-empty \
  -m "Merge pull request #88 from example/fix/LEA-302-billing-fix"
sha_miss_file="$("$REAL_GIT" -C "$repo_miss_file" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_miss_file" tag v1.29.0
write_linear_scope_gh \
  "88|fix/LEA-302-billing-fix|fix(billing): LEA-302" \
  "commit:${sha_miss_file}|88"
result="$(run_linear_scope_cleanup "$repo_miss_file" v1.29.0 --from-changelog --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_1982_missing_file_exits_zero" "0" "$status"
run_contains "linear_1982_missing_file_diagnostic" \
  "CHANGELOG_SECTION_UNAVAILABLE version=v1.29.0 (Linear scope derived from merged PRs only)" \
  "$output"
run_contains "linear_1982_missing_file_proposes_302" "TRACKER_ISSUES=LEA-302" "$output"
run_not_contains "linear_1982_missing_file_no_changelog_unavailable" \
  "REASON=changelog_scope_unavailable" "$output"

# --- Malformed commits/<sha>/pulls evidence fails closed (unresolved SHAs) ---
repo_malformed_pulls="$TMP_ROOT/linear-1982-malformed-pulls"
init_linear_git_repo "$repo_malformed_pulls"
cat > "$repo_malformed_pulls/CHANGELOG.md" <<'MD'
# Changelog

## [Unreleased]

## [1.29.0] - 2026-10-15

- Ships LEA-302.
MD
"$REAL_GIT" -C "$repo_malformed_pulls" add CHANGELOG.md .ai-dev-workflow.yaml scripts
"$REAL_GIT" -C "$repo_malformed_pulls" commit -q -m "chore: baseline before v1.28.0"
"$REAL_GIT" -C "$repo_malformed_pulls" tag v1.28.0
"$REAL_GIT" -C "$repo_malformed_pulls" commit -q --allow-empty \
  -m "Merge pull request #88 from example/fix/LEA-302-billing-fix"
sha_malformed="$("$REAL_GIT" -C "$repo_malformed_pulls" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_malformed_pulls" tag v1.29.0
write_linear_scope_gh \
  "88|fix/LEA-302-billing-fix|fix(billing): LEA-302" \
  "commit:${sha_malformed}|malformed:empty"
result="$(run_linear_scope_cleanup "$repo_malformed_pulls" v1.29.0 --from-changelog --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_1982_malformed_empty_pulls_exits_zero" "0" "$status"
run_contains "linear_1982_malformed_empty_incomplete" \
  "RELEASE_SCOPE_INCOMPLETE unresolved_shas=${sha_malformed}" "$output"
run_not_contains "linear_1982_malformed_empty_no_ok_scope" "TRACKER_ISSUES=LEA-302" "$output"

write_linear_scope_gh \
  "88|fix/LEA-302-billing-fix|fix(billing): LEA-302" \
  "commit:${sha_malformed}|malformed:null"
result="$(run_linear_scope_cleanup "$repo_malformed_pulls" v1.29.0 --from-changelog --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_1982_malformed_null_pulls_exits_zero" "0" "$status"
run_contains "linear_1982_malformed_null_incomplete" \
  "RELEASE_SCOPE_INCOMPLETE unresolved_shas=${sha_malformed}" "$output"
run_not_contains "linear_1982_malformed_null_no_ok_scope" "TRACKER_ISSUES=LEA-302" "$output"

# [{}] — empty object missing number and merged field → incomplete
write_linear_scope_gh \
  "88|fix/LEA-302-billing-fix|fix(billing): LEA-302" \
  "commit:${sha_malformed}|malformed:empty_object"
result="$(run_linear_scope_cleanup "$repo_malformed_pulls" v1.29.0 --from-changelog --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_1982_malformed_empty_object_exits_zero" "0" "$status"
run_contains "linear_1982_malformed_empty_object_incomplete" \
  "RELEASE_SCOPE_INCOMPLETE unresolved_shas=${sha_malformed}" "$output"
run_not_contains "linear_1982_malformed_empty_object_no_ok_scope" "TRACKER_ISSUES=LEA-302" "$output"

# Element missing integer number → incomplete
write_linear_scope_gh \
  "88|fix/LEA-302-billing-fix|fix(billing): LEA-302" \
  "commit:${sha_malformed}|malformed:no_number"
result="$(run_linear_scope_cleanup "$repo_malformed_pulls" v1.29.0 --from-changelog --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_1982_malformed_no_number_exits_zero" "0" "$status"
run_contains "linear_1982_malformed_no_number_incomplete" \
  "RELEASE_SCOPE_INCOMPLETE unresolved_shas=${sha_malformed}" "$output"
run_not_contains "linear_1982_malformed_no_number_no_ok_scope" "TRACKER_ISSUES=LEA-302" "$output"

# Element with number but no merged_at/merged/mergedAt field → incomplete
write_linear_scope_gh \
  "88|fix/LEA-302-billing-fix|fix(billing): LEA-302" \
  "commit:${sha_malformed}|malformed:no_merged"
result="$(run_linear_scope_cleanup "$repo_malformed_pulls" v1.29.0 --from-changelog --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_1982_malformed_no_merged_exits_zero" "0" "$status"
run_contains "linear_1982_malformed_no_merged_incomplete" \
  "RELEASE_SCOPE_INCOMPLETE unresolved_shas=${sha_malformed}" "$output"
run_not_contains "linear_1982_malformed_no_merged_no_ok_scope" "TRACKER_ISSUES=LEA-302" "$output"

# --- Well-formed [] (no associated PR) + valid PR on another commit ---
# [] must emit RELEASE_SCOPE_COMMIT_WITHOUT_PR and keep scope complete so the
# other commit's IDs are still proposed.
repo_empty_array="$TMP_ROOT/linear-1982-empty-array-pulls"
init_linear_git_repo "$repo_empty_array"
cat > "$repo_empty_array/CHANGELOG.md" <<'MD'
# Changelog

## [Unreleased]

## [1.29.0] - 2026-10-15

- Ships LEA-302.
MD
"$REAL_GIT" -C "$repo_empty_array" add CHANGELOG.md .ai-dev-workflow.yaml scripts
"$REAL_GIT" -C "$repo_empty_array" commit -q -m "chore: baseline before v1.28.0"
"$REAL_GIT" -C "$repo_empty_array" tag v1.28.0
"$REAL_GIT" -C "$repo_empty_array" commit -q --allow-empty \
  -m "chore: direct push with no associated PR"
sha_no_pr="$("$REAL_GIT" -C "$repo_empty_array" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_empty_array" commit -q --allow-empty \
  -m "Merge pull request #88 from example/fix/LEA-302-billing-fix"
sha_with_pr="$("$REAL_GIT" -C "$repo_empty_array" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_empty_array" tag v1.29.0
sha_no_pr_short="$(printf '%s' "$sha_no_pr" | cut -c1-7)"
write_linear_scope_gh \
  "88|fix/LEA-302-billing-fix|fix(billing): LEA-302" \
  "commit:${sha_no_pr}|empty:array" \
  "commit:${sha_with_pr}|88"
result="$(run_linear_scope_cleanup "$repo_empty_array" v1.29.0 --from-changelog --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_1982_empty_array_exits_zero" "0" "$status"
run_contains "linear_1982_empty_array_diagnostic" \
  "RELEASE_SCOPE_COMMIT_WITHOUT_PR sha=${sha_no_pr_short}" "$output"
run_contains "linear_1982_empty_array_still_proposes_302" "TRACKER_ISSUES=LEA-302" "$output"
run_not_contains "linear_1982_empty_array_not_incomplete" \
  "RELEASE_SCOPE_INCOMPLETE unresolved_shas=" "$output"

# --- Pagination: shipping PR only on page 2 (31 associations) → still proposed ---
repo_paginate="$TMP_ROOT/linear-1982-paginate-page2"
init_linear_git_repo "$repo_paginate"
cat > "$repo_paginate/CHANGELOG.md" <<'MD'
# Changelog

## [Unreleased]

## [1.29.0] - 2026-10-15

- Ships chore LEA-346 (must not be omitted when only on page 2 of pulls).
MD
"$REAL_GIT" -C "$repo_paginate" add CHANGELOG.md .ai-dev-workflow.yaml scripts
"$REAL_GIT" -C "$repo_paginate" commit -q -m "chore: baseline before v1.28.0"
"$REAL_GIT" -C "$repo_paginate" tag v1.28.0
"$REAL_GIT" -C "$repo_paginate" commit -q --allow-empty \
  -m "Merge pull request #90 from example/chore/LEA-346-dependency-bump"
sha_paginate="$("$REAL_GIT" -C "$repo_paginate" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_paginate" tag v1.29.0
write_linear_scope_gh \
  "90|chore/LEA-346-dependency-bump|chore: LEA-346 dependency bump" \
  "commit:${sha_paginate}|paginate:page2_shipping:90"
result="$(run_linear_scope_cleanup "$repo_paginate" v1.29.0 --from-changelog --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_1982_paginate_page2_exits_zero" "0" "$status"
run_contains "linear_1982_paginate_page2_proposes_346" "TRACKER_ISSUES=LEA-346" "$output"
run_not_contains "linear_1982_paginate_page2_not_incomplete" \
  "RELEASE_SCOPE_INCOMPLETE unresolved_shas=" "$output"

# Page-2 error → RELEASE_SCOPE_INCOMPLETE for that SHA (fail closed).
write_linear_scope_gh \
  "90|chore/LEA-346-dependency-bump|chore: LEA-346 dependency bump" \
  "commit:${sha_paginate}|paginate:error_page2"
result="$(run_linear_scope_cleanup "$repo_paginate" v1.29.0 --from-changelog --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_1982_paginate_error_exits_zero" "0" "$status"
run_contains "linear_1982_paginate_error_incomplete" \
  "RELEASE_SCOPE_INCOMPLETE unresolved_shas=${sha_paginate}" "$output"
run_not_contains "linear_1982_paginate_error_no_346" "TRACKER_ISSUES=LEA-346" "$output"

# --- Empty commit subject must still collect the SHA and query pulls ---
# git log %H\\t%s + strip() used to drop SHAs whose subject is empty (trailing
# tab removed). Use commit-tree -m '' so hooks cannot inject a subject.
repo_empty_subj="$TMP_ROOT/linear-1982-empty-subject"
init_linear_git_repo "$repo_empty_subj"
cat > "$repo_empty_subj/CHANGELOG.md" <<'MD'
# Changelog

## [Unreleased]

## [1.29.0] - 2026-10-15

- Ships LEA-12 via a rebased commit with an empty subject.
MD
"$REAL_GIT" -C "$repo_empty_subj" add CHANGELOG.md .ai-dev-workflow.yaml scripts
"$REAL_GIT" -C "$repo_empty_subj" commit -q -m "chore: baseline before v1.28.0"
"$REAL_GIT" -C "$repo_empty_subj" tag v1.28.0
empty_tree="$("$REAL_GIT" -C "$repo_empty_subj" write-tree)"
empty_parent="$("$REAL_GIT" -C "$repo_empty_subj" rev-parse HEAD)"
sha_empty_subj="$("$REAL_GIT" -C "$repo_empty_subj" commit-tree "$empty_tree" -p "$empty_parent" -m '')"
"$REAL_GIT" -C "$repo_empty_subj" update-ref HEAD "$sha_empty_subj"
# Prove the historical strip bug would have dropped this SHA.
empty_subj_log="$("$REAL_GIT" -C "$repo_empty_subj" log -1 --pretty=format:%H%x09%s "$sha_empty_subj")"
case "$empty_subj_log" in
  *$'\t') ;;
  *)
    echo "FAIL: fixture empty-subject log line lacks trailing tab: $(printf '%q' "$empty_subj_log")" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
    ;;
esac
stripped_empty_subj="$(printf '%s' "$empty_subj_log" | python3 -c 'import sys; print(sys.stdin.read().strip())')"
case "$stripped_empty_subj" in
  *$'\t'*)
    echo "FAIL: expected strip() to remove trailing tab from empty-subject log line" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
    ;;
esac
"$REAL_GIT" -C "$repo_empty_subj" tag v1.29.0
write_linear_scope_gh \
  "12|fix/LEA-12-empty-subject|fix: LEA-12 empty subject" \
  "commit:${sha_empty_subj}|12"
result="$(run_linear_scope_cleanup "$repo_empty_subj" v1.29.0 --from-changelog --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_1982_empty_subject_exits_zero" "0" "$status"
run_contains "linear_1982_empty_subject_proposes_12" "TRACKER_ISSUES=LEA-12" "$output"
run_not_contains "linear_1982_empty_subject_not_incomplete" \
  "RELEASE_SCOPE_INCOMPLETE unresolved_shas=" "$output"
# Fake gh must have been queried for this SHA (call logged via map hit → PR 12).
run_contains "linear_1982_empty_subject_queried_sha" "LEA-12" "$output"

# --- GH_REPO must not override checkout repo for Linear PR lookups ---
repo_gh_repo="$TMP_ROOT/linear-1982-gh-repo-override"
init_linear_git_repo "$repo_gh_repo"
cat > "$repo_gh_repo/CHANGELOG.md" <<'MD'
# Changelog

## [Unreleased]

## [1.29.0] - 2026-10-15

- Ships LEA-302.
MD
"$REAL_GIT" -C "$repo_gh_repo" add CHANGELOG.md .ai-dev-workflow.yaml scripts
"$REAL_GIT" -C "$repo_gh_repo" commit -q -m "chore: baseline before v1.28.0"
"$REAL_GIT" -C "$repo_gh_repo" tag v1.28.0
"$REAL_GIT" -C "$repo_gh_repo" commit -q --allow-empty \
  -m "Merge pull request #88 from example/fix/LEA-302-billing-fix"
sha_gh_repo="$("$REAL_GIT" -C "$repo_gh_repo" rev-parse HEAD)"
"$REAL_GIT" -C "$repo_gh_repo" tag v1.29.0
write_linear_scope_gh \
  "88|fix/LEA-302-billing-fix|fix(billing): LEA-302" \
  "commit:${sha_gh_repo}|88"
result="$(
  set +e
  output="$(
    cd "$repo_gh_repo" && PATH="$LINEAR_SCOPE_BIN:$(dirname "$REAL_GIT"):$PATH" \
      LINEAR_SCOPE_MAP_FILE="$LINEAR_SCOPE_MAP_FILE" \
      GH_REPO="hub/other-repo" \
      WORKFLOW_SKIP_FETCH=1 \
      ./scripts/development-workflow/prepare-release-post-merge-cleanup.sh \
      v1.29.0 --from-changelog --best-effort 2>&1
  )"
  rc=$?
  set -e
  printf '%s\n%s\n' "$rc" "$output"
)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_1982_gh_repo_override_exits_zero" "0" "$status"
run_contains "linear_1982_gh_repo_override_proposes_302" "TRACKER_ISSUES=LEA-302" "$output"
run_not_contains "linear_1982_gh_repo_override_no_incomplete" "RELEASE_SCOPE_INCOMPLETE" "$output"

# github_projects --from-changelog still extracts #NNN from changelog text alone.
repo_github_unchanged="$(fixture_github_projects_repo github-1982-unchanged)"
result="$(run_cleanup_with_bin "$MILESTONE_BIN" "$repo_github_unchanged" v1.17.0 --from-changelog --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "github_projects_from_changelog_unchanged_exits_zero" "0" "$status"
run_contains "github_projects_from_changelog_unchanged_stamp" "RELEASE_STAMPED issue=101" "$output"
run_not_contains "github_projects_from_changelog_no_linear_skip" "RELEASE_SCOPE_SKIPPED" "$output"

# github_projects: missing CHANGELOG version section still fails closed (unchanged).
repo_github_miss_section="$(fixture_github_projects_repo github-1982-missing-section)"
result="$(run_cleanup_with_bin "$MILESTONE_BIN" "$repo_github_miss_section" v9.9.9 --from-changelog)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "github_projects_missing_section_exits_nonzero" "1" "$status"
run_contains "github_projects_missing_section_unavailable" \
  "TRACKER_INCOMPLETE=1 REASON=changelog_scope_unavailable" "$output"
run_not_contains "github_projects_missing_section_no_linear_diag" \
  "CHANGELOG_SECTION_UNAVAILABLE" "$output"

# --- GitHub providers: bare input 1.2.3 must still stamp milestone title v1.2.3 ---
# (RELEASE_VERSION stays branch-normalized; Linear-only requested spelling must
# not leak into github_projects / github_issues milestone identity.)
BARE_MILESTONE_BIN="$TMP_ROOT/bare-milestone-bin"
mkdir -p "$BARE_MILESTONE_BIN"
cat > "$BARE_MILESTONE_BIN/gh" <<'MOCK_GH_BARE_MILESTONE'
#!/usr/bin/env bash
case "$*" in
  "auth status") exit 0 ;;
  "api --paginate --slurp repos/test-owner/test-repo/milestones?state=all&per_page=100")
    # Exact title match: only v1.2.3 exists (not bare 1.2.3).
    printf '[{"number":77,"title":"v1.2.3","state":"closed"}]\n'
    ;;
  "repo view --json owner --jq .owner.login") printf 'test-owner\n' ;;
  "repo view --json name --jq .name") printf 'test-repo\n' ;;
  "api -X PATCH repos/test-owner/test-repo/issues/101 -F milestone=77")
    printf '{"number":101,"milestone":{"number":77,"title":"v1.2.3"}}\n'
    ;;
  "api -X POST repos/test-owner/test-repo/milestones"*)
    printf 'unexpected milestone create (title must already exist as v1.2.3): gh %s\n' "$*" >&2
    exit 64
    ;;
  "issue view 101 --json state --jq .state") printf 'closed\n' ;;
  "pr list --state merged --head release/v1.2.3 --base main --json number --jq .[0].number // empty")
    printf '333\n' ;;
  "pr list --state merged --head release/v1.2.3 --base develop --json number --jq .[0].number // empty")
    printf '334\n' ;;
  "pr list --state open --head release/v1.2.3 --base main --json number --jq .[0].number // empty")
    printf '\n' ;;
  "pr list --state open --head release/v1.2.3 --base develop --json number --jq .[0].number // empty")
    printf '\n' ;;
  *"user(login"*"projectV2"*)
    printf '{"data":{"user":{"projectV2":{"id":"PVT_test000001"}}}}\n' ;;
  *"organization(login"*"projectV2"*)
    printf '{"data":{"organization":{"projectV2":{"id":"PVT_test000001"}}}}\n' ;;
  *"projectId"*"ProjectV2"*"items"*)
    printf '{"data":{"node":{"items":{"nodes":[],"pageInfo":{"hasNextPage":false,"endCursor":""}}}}}\n' ;;
  "api graphql"*)
    printf '{"data":{"repository":{"issue":{"projectItems":{"nodes":[],"pageInfo":{"hasNextPage":false,"endCursor":""}}}}}}\n' ;;
  "api repos/test-owner/test-repo/releases/tags/v1.2.3 --jq .published_at // .created_at // empty")
    printf '2026-06-11T12:00:00Z\n' ;;
  "api repos/test-owner/test-repo/tags?per_page=100 --paginate --jq [.[] | select(.name | test(\"^v?[0-9]+\\.[0-9]+\\.[0-9]+\"))] | .[].name")
    printf 'v1.2.3\nv1.2.2\n' ;;
  "api repos/test-owner/test-repo/releases/tags/v1.2.2 --jq .published_at // .created_at // empty")
    printf '2026-06-01T12:00:00Z\n' ;;
  *)
    printf 'unexpected gh invocation: gh %s\n' "$*" >&2
    exit 64
    ;;
esac
MOCK_GH_BARE_MILESTONE
chmod +x "$BARE_MILESTONE_BIN/gh"
cat > "$BARE_MILESTONE_BIN/git" <<'MOCK_GIT_BARE_MILESTONE'
#!/usr/bin/env bash
case "$*" in
  "fetch origin --prune") exit 0 ;;
  "ls-remote --exit-code --heads origin release/v1.2.3") exit 2 ;;
  "show-ref --quiet refs/heads/release/v1.2.3") exit 1 ;;
  "remote get-url origin") printf 'https://github.com/test-owner/test-repo.git\n' ;;
  *) exit 0 ;;
esac
MOCK_GIT_BARE_MILESTONE
chmod +x "$BARE_MILESTONE_BIN/git"

fixture_github_bare_milestone_repo() {
  local provider="$1"
  local name="$2"
  local path="$TMP_ROOT/$name"
  mkdir -p "$path/scripts/development-workflow"
  cp "$REPO_ROOT/scripts/development-workflow/workflow-lib.sh" \
    "$path/scripts/development-workflow/workflow-lib.sh"
  cp "$REPO_ROOT/scripts/development-workflow/prepare-release-post-merge-cleanup.sh" \
    "$path/scripts/development-workflow/prepare-release-post-merge-cleanup.sh"
  chmod +x "$path/scripts/development-workflow/prepare-release-post-merge-cleanup.sh"
  if [ "$provider" = "github_projects" ]; then
    cat > "$path/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
issue_tracker:
  provider: github_projects
  project_number: 1
YAML
  else
    cat > "$path/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
issue_tracker:
  provider: github_issues
YAML
  fi
  cat > "$path/CHANGELOG.md" <<'MD'
# Changelog

## [Unreleased]

## [1.2.3] - 2026-06-11

### Fixed

- Fixed some bug (#101).
MD
  printf '%s\n' "$path"
}

for provider in github_projects github_issues; do
  repo_bare_ms="$(fixture_github_bare_milestone_repo "$provider" "bare-ms-${provider}")"
  result="$(run_cleanup_with_bin "$BARE_MILESTONE_BIN" "$repo_bare_ms" 1.2.3 --from-changelog --best-effort)"
  status="$(printf '%s\n' "$result" | sed -n '1p')"
  output="$(printf '%s\n' "$result" | sed '1d')"
  run_test "${provider}_bare_input_exits_zero" "0" "$status"
  run_contains "${provider}_bare_input_release_version_v" "Release version: v1.2.3" "$output"
  run_contains "${provider}_bare_input_branch_v" "Release branch: release/v1.2.3" "$output"
  run_contains "${provider}_bare_input_stamp_v_milestone" \
    "RELEASE_STAMPED issue=101 version=v1.2.3 provider=${provider}" "$output"
  run_not_contains "${provider}_bare_input_no_bare_stamp" \
    "RELEASE_STAMPED issue=101 version=1.2.3" "$output"
  # v-prefixed input must remain byte-identical on the provider-visible surface.
  result="$(run_cleanup_with_bin "$BARE_MILESTONE_BIN" "$repo_bare_ms" v1.2.3 --from-changelog --best-effort)"
  status="$(printf '%s\n' "$result" | sed -n '1p')"
  output="$(printf '%s\n' "$result" | sed '1d')"
  run_test "${provider}_v_input_exits_zero" "0" "$status"
  run_contains "${provider}_v_input_release_version" "Release version: v1.2.3" "$output"
  run_contains "${provider}_v_input_stamp" \
    "RELEASE_STAMPED issue=101 version=v1.2.3 provider=${provider}" "$output"
done

# --- GitHub RELEASE_BRANCH / RELEASE_VERSION byte-identical to origin/develop ---
# Hard-coded develop outputs (computed once from origin/develop's
# normalize_release_branch + release_version_from_branch).
echo ""
echo "=== GitHub normalize parity with origin/develop ==="
NORM_HELPER="$TMP_ROOT/normalize-parity-helper.sh"
# Extract the shared functions from the script under test (must match develop).
{
  sed -n '/^normalize_release_branch()/,/^}/p' \
    "$REPO_ROOT/scripts/development-workflow/prepare-release-post-merge-cleanup.sh"
  sed -n '/^release_version_from_branch()/,/^}/p' \
    "$REPO_ROOT/scripts/development-workflow/prepare-release-post-merge-cleanup.sh"
  cat <<'HELPER'
while IFS=$'\t' read -r input want_branch want_version; do
  [ -n "$input" ] || continue
  got_branch="$(normalize_release_branch "$input")"
  got_version="$(release_version_from_branch "$got_branch")"
  printf '%s\t%s\t%s\t%s\t%s\n' "$input" "$want_branch" "$want_version" "$got_branch" "$got_version"
done <<'MATRIX'
1.2.3	release/v1.2.3	v1.2.3
v1.2.3	release/v1.2.3	v1.2.3
release/v1.2.3	release/v1.2.3	v1.2.3
mobile-v1.1.0	release/vmobile-v1.1.0	vmobile-v1.1.0
release/mobile-v1.1.0	release/vmobile-v1.1.0	vmobile-v1.1.0
1.2.3-rc.1	release/v1.2.3-rc.1	v1.2.3-rc.1
MATRIX
HELPER
} > "$NORM_HELPER"

norm_rows="$(bash "$NORM_HELPER")"
while IFS=$'\t' read -r input want_branch want_version got_branch got_version; do
  [ -n "$input" ] || continue
  safe="$(printf '%s' "$input" | tr '/.' '__')"
  run_test "normalize_parity_branch_${safe}" "$want_branch" "$got_branch"
  run_test "normalize_parity_version_${safe}" "$want_version" "$got_version"
done <<< "$norm_rows"

# Provider-visible logs for component-looking input (develop injects vmobile-…).
MOBILE_NORM_BIN="$TMP_ROOT/mobile-norm-bin"
mkdir -p "$MOBILE_NORM_BIN"
cat > "$MOBILE_NORM_BIN/gh" <<'MOCK_GH_MOBILE_NORM'
#!/usr/bin/env bash
case "$*" in
  "auth status") exit 0 ;;
  "api --paginate --slurp repos/test-owner/test-repo/milestones?state=all&per_page=100")
    printf '[{"number":88,"title":"vmobile-v1.1.0","state":"closed"}]\n' ;;
  "repo view --json owner --jq .owner.login") printf 'test-owner\n' ;;
  "repo view --json name --jq .name") printf 'test-repo\n' ;;
  "api -X PATCH repos/test-owner/test-repo/issues/101 -F milestone=88")
    printf '{"number":101,"milestone":{"number":88,"title":"vmobile-v1.1.0"}}\n' ;;
  "api -X POST repos/test-owner/test-repo/milestones"*)
    printf 'unexpected milestone create: gh %s\n' "$*" >&2; exit 64 ;;
  "issue view 101 --json state --jq .state") printf 'closed\n' ;;
  "pr list --state merged --head release/vmobile-v1.1.0 --base main --json number --jq .[0].number // empty")
    printf '333\n' ;;
  "pr list --state merged --head release/vmobile-v1.1.0 --base develop --json number --jq .[0].number // empty")
    printf '334\n' ;;
  "pr list --state open --head release/vmobile-v1.1.0 --base main --json number --jq .[0].number // empty")
    printf '\n' ;;
  "pr list --state open --head release/vmobile-v1.1.0 --base develop --json number --jq .[0].number // empty")
    printf '\n' ;;
  *"user(login"*"projectV2"*)
    printf '{"data":{"user":{"projectV2":{"id":"PVT_test000001"}}}}\n' ;;
  *"organization(login"*"projectV2"*)
    printf '{"data":{"organization":{"projectV2":{"id":"PVT_test000001"}}}}\n' ;;
  *"projectId"*"ProjectV2"*"items"*)
    printf '{"data":{"node":{"items":{"nodes":[],"pageInfo":{"hasNextPage":false,"endCursor":""}}}}}\n' ;;
  "api graphql"*)
    printf '{"data":{"repository":{"issue":{"projectItems":{"nodes":[],"pageInfo":{"hasNextPage":false,"endCursor":""}}}}}}\n' ;;
  "api repos/test-owner/test-repo/releases/tags/"*)
    printf '2026-06-11T12:00:00Z\n' ;;
  "api repos/test-owner/test-repo/tags?per_page=100"*)
    printf 'vmobile-v1.1.0\n' ;;
  *)
    printf 'unexpected gh invocation: gh %s\n' "$*" >&2
    exit 64
    ;;
esac
MOCK_GH_MOBILE_NORM
chmod +x "$MOBILE_NORM_BIN/gh"
cat > "$MOBILE_NORM_BIN/git" <<'MOCK_GIT_MOBILE_NORM'
#!/usr/bin/env bash
case "$*" in
  "fetch origin --prune") exit 0 ;;
  "ls-remote --exit-code --heads origin release/vmobile-v1.1.0") exit 2 ;;
  "show-ref --quiet refs/heads/release/vmobile-v1.1.0") exit 1 ;;
  "remote get-url origin") printf 'https://github.com/test-owner/test-repo.git\n' ;;
  *) exit 0 ;;
esac
MOCK_GIT_MOBILE_NORM
chmod +x "$MOBILE_NORM_BIN/git"

for provider in github_projects github_issues; do
  repo_mobile_norm="$(fixture_github_bare_milestone_repo "$provider" "mobile-norm-${provider}")"
  # Explicit --issue avoids CHANGELOG section title coupling to vmobile-… spelling.
  result="$(run_cleanup_with_bin "$MOBILE_NORM_BIN" "$repo_mobile_norm" mobile-v1.1.0 --issue 101 --best-effort)"
  status="$(printf '%s\n' "$result" | sed -n '1p')"
  output="$(printf '%s\n' "$result" | sed '1d')"
  run_test "${provider}_mobile_input_exits_zero" "0" "$status"
  run_contains "${provider}_mobile_input_branch_vmobile" \
    "Release branch: release/vmobile-v1.1.0" "$output"
  run_contains "${provider}_mobile_input_version_vmobile" \
    "Release version: vmobile-v1.1.0" "$output"
  run_contains "${provider}_mobile_input_stamp_vmobile" \
    "RELEASE_STAMPED issue=101 version=vmobile-v1.1.0 provider=${provider}" "$output"
  run_not_contains "${provider}_mobile_input_no_bare_mobile_version" \
    "Release version: mobile-v1.1.0" "$output"
done

# --- Differential GitHub parity vs frozen develop baseline (#1982) ---
# Runs HEAD and the checked-in develop baseline against identical fixtures and
# the same stubbed gh/git (with call logs). Asserts identical exit, stdout/stderr
# (modulo temp paths), and mutation call logs for both GitHub providers.
echo ""
echo "=== Differential GitHub parity vs develop baseline ==="
DEVELOP_BASELINE="$REPO_ROOT/scripts/development-workflow/tests/fixtures/prepare-release-post-merge-cleanup.develop-baseline"
if [ ! -f "$DEVELOP_BASELINE" ]; then
  echo "FAIL: missing frozen develop baseline at $DEVELOP_BASELINE" >&2
  FAIL_COUNT=$((FAIL_COUNT + 1))
else
  PARITY_COUNT=0
  PARITY_ROOT="$TMP_ROOT/github-parity"
  mkdir -p "$PARITY_ROOT"

  # Recording stubs: log every argv; respond generically for the matrix.
  install_parity_stubs() {
    local bin_dir="$1"
    local call_log="$2"
    mkdir -p "$bin_dir"
    cat > "$bin_dir/gh" <<MOCK_GH_PARITY
#!/usr/bin/env bash
printf 'gh %s\n' "\$*" >> "$(printf '%s' "$call_log")"
case "\$*" in
  "auth status") exit 0 ;;
  "repo view --json owner --jq .owner.login") printf 'test-owner\n' ;;
  "repo view --json name --jq .name") printf 'test-repo\n' ;;
  "repo view --json nameWithOwner --jq .nameWithOwner") printf 'test-owner/test-repo\n' ;;
  "api --paginate --slurp repos/test-owner/test-repo/milestones?state=all&per_page=100")
    printf '%s\n' '[{"number":10,"title":"v1.2.3","state":"closed"},{"number":11,"title":"vmobile-v1.1.0","state":"closed"},{"number":12,"title":"v1.2.3-rc.1","state":"closed"},{"number":13,"title":"v1.2.2","state":"closed"}]'
    ;;
  api\ -X\ PATCH\ repos/test-owner/test-repo/issues/*\ -F\ milestone=*)
    ms="\${*##*milestone=}"
    printf '{"number":101,"milestone":{"number":%s,"title":"ok"}}\n' "\$ms"
    ;;
  api\ -X\ PATCH\ repos/test-owner/test-repo/milestones/*\ -f\ state=closed)
    printf '{"number":11,"state":"closed"}\n' ;;
  "api -X POST repos/test-owner/test-repo/milestones"*)
    printf '{"number":99,"title":"created"}\n' ;;
  issue\ view\ *\ --json\ state\ --jq\ .state) printf 'closed\n' ;;
  pr\ list\ --state\ merged\ --head\ *\ --base\ main\ --json\ number\ --jq\ *)
    printf '333\n' ;;
  pr\ list\ --state\ merged\ --head\ *\ --base\ develop\ --json\ number\ --jq\ *)
    printf '334\n' ;;
  pr\ list\ --state\ open\ --head\ *\ --base\ main\ --json\ number\ --jq\ *)
    printf '\n' ;;
  pr\ list\ --state\ open\ --head\ *\ --base\ develop\ --json\ number\ --jq\ *)
    printf '\n' ;;
  *"user(login"*"projectV2"*)
    printf '{"data":{"user":{"projectV2":{"id":"PVT_test000001"}}}}\n' ;;
  *"organization(login"*"projectV2"*)
    printf '{"data":{"organization":{"projectV2":{"id":"PVT_test000001"}}}}\n' ;;
  *"projectId"*"ProjectV2"*"items"*)
    printf '{"data":{"node":{"items":{"nodes":[],"pageInfo":{"hasNextPage":false,"endCursor":""}}}}}\n' ;;
  "api graphql"*)
    printf '{"data":{"repository":{"issue":{"projectItems":{"nodes":[],"pageInfo":{"hasNextPage":false,"endCursor":""}}}}}}\n' ;;
  "api repos/test-owner/test-repo/releases/tags/"*)
    printf '2026-06-11T12:00:00Z\n' ;;
  "api repos/test-owner/test-repo/tags?per_page=100"*)
    printf 'v1.2.3\nvmobile-v1.1.0\nv1.2.3-rc.1\nv1.2.2\n' ;;
  *)
    printf 'unexpected gh invocation: gh %s\n' "\$*" >&2
    exit 64
    ;;
esac
MOCK_GH_PARITY
    cat > "$bin_dir/git" <<MOCK_GIT_PARITY
#!/usr/bin/env bash
printf 'git %s\n' "\$*" >> "$(printf '%s' "$call_log")"
case "\$*" in
  "fetch origin --prune") exit 0 ;;
  ls-remote\ --exit-code\ --heads\ origin\ *) exit 2 ;;
  show-ref\ --quiet\ refs/heads/*) exit 1 ;;
  "remote get-url origin") printf 'https://github.com/test-owner/test-repo.git\n' ;;
  check-ref-format\ --branch\ *) exit 0 ;;
  *) exit 0 ;;
esac
MOCK_GIT_PARITY
    chmod +x "$bin_dir/gh" "$bin_dir/git"
  }

  normalize_parity_text() {
    # Collapse absolute temp paths so fixture roots do not break equality.
    # Also collapse script line numbers so HEAD vs develop baseline path-length
    # differences do not break stderr equality on shared error text.
    sed -e "s|${TMP_ROOT}|TMP_ROOT|g" -e "s|${PARITY_ROOT}|PARITY_ROOT|g" \
      -e 's|prepare-release-post-merge-cleanup\.sh: line [0-9][0-9]*:|prepare-release-post-merge-cleanup.sh: line N:|g' \
      -e 's|prepare-release-post-merge-cleanup\.develop-baseline: line [0-9][0-9]*:|prepare-release-post-merge-cleanup.sh: line N:|g'
  }

  fixture_parity_repo() {
    local provider="$1"
    local name="$2"
    local script_src="$3"
    local heading="$4"
    local path="$PARITY_ROOT/$name"
    rm -rf "$path"
    mkdir -p "$path/scripts/development-workflow"
    cp "$REPO_ROOT/scripts/development-workflow/workflow-lib.sh" \
      "$path/scripts/development-workflow/workflow-lib.sh"
    # Baseline may call helpers present only in current workflow-lib; that is
    # intentional — we freeze the cleanup script, not the whole toolchain.
    cp "$script_src" \
      "$path/scripts/development-workflow/prepare-release-post-merge-cleanup.sh"
    chmod +x "$path/scripts/development-workflow/prepare-release-post-merge-cleanup.sh"
    if [ "$provider" = "github_projects" ]; then
      cat > "$path/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
issue_tracker:
  provider: github_projects
  project_number: 1
YAML
    else
      cat > "$path/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
issue_tracker:
  provider: github_issues
YAML
    fi
    if [ "$heading" = "MISSING" ]; then
      cat > "$path/CHANGELOG.md" <<'MD'
# Changelog

## [Unreleased]

## [9.9.9] - 2026-01-01

- Unrelated (#999).
MD
    else
      cat > "$path/CHANGELOG.md" <<MD
# Changelog

## [Unreleased]

## [${heading}] - 2026-06-11

### Fixed

- Fixed some bug (#101).
MD
    fi
    printf '%s\n' "$path"
  }

  run_parity_one() {
    local label="$1"
    local provider="$2"
    local input="$3"
    local heading="$4"
    shift 4
    # remaining: cleanup argv after version
    local case_dir="$PARITY_ROOT/case-${label}"
    mkdir -p "$case_dir"
    local head_log="$case_dir/head.calls"
    local base_log="$case_dir/base.calls"
    : > "$head_log"
    : > "$base_log"
    local head_bin="$case_dir/head-bin"
    local base_bin="$case_dir/base-bin"
    install_parity_stubs "$head_bin" "$head_log"
    install_parity_stubs "$base_bin" "$base_log"

    # Same fixture path for both runs so stderr path embeds do not diverge;
    # swap only the cleanup script between HEAD and the frozen baseline.
    local shared_repo
    shared_repo="$(fixture_parity_repo "$provider" "${label}-shared" \
      "$REPO_ROOT/scripts/development-workflow/prepare-release-post-merge-cleanup.sh" \
      "$heading")"
    # Optional helper imported by workflow-lib for github_projects status updates.
    if [ -f "$REPO_ROOT/scripts/development-workflow/workflow-project-reader.py" ]; then
      cp "$REPO_ROOT/scripts/development-workflow/workflow-project-reader.py" \
        "$shared_repo/scripts/development-workflow/workflow-project-reader.py"
    fi

    local head_out base_out head_status=0 base_status=0
    set +e
    head_out="$(cd "$shared_repo" && PATH="${head_bin}:$PATH" \
      ./scripts/development-workflow/prepare-release-post-merge-cleanup.sh \
      "$input" "$@" 2>&1)"
    head_status=$?
    # Reset script to frozen baseline; keep CHANGELOG / config / helpers.
    cp "$DEVELOP_BASELINE" \
      "$shared_repo/scripts/development-workflow/prepare-release-post-merge-cleanup.sh"
    chmod +x "$shared_repo/scripts/development-workflow/prepare-release-post-merge-cleanup.sh"
    base_out="$(cd "$shared_repo" && PATH="${base_bin}:$PATH" \
      ./scripts/development-workflow/prepare-release-post-merge-cleanup.sh \
      "$input" "$@" 2>&1)"
    base_status=$?
    set -e

    local head_norm base_norm
    head_norm="$(printf '%s\n' "$head_out" | normalize_parity_text)"
    base_norm="$(printf '%s\n' "$base_out" | normalize_parity_text)"

    run_test "parity_${label}_exit" "$base_status" "$head_status"
    if [ "$head_norm" = "$base_norm" ]; then
      run_test "parity_${label}_stdio" "match" "match"
    else
      printf '%s\n' "$head_norm" > "$case_dir/head.stdio"
      printf '%s\n' "$base_norm" > "$case_dir/base.stdio"
      run_test "parity_${label}_stdio" "match" "DIFF see $case_dir/*.stdio"
    fi
    # Mutation-relevant calls: PATCH issues / POST milestones / branch deletes.
    # Empty grep is expected when a case performs no mutations.
    local head_mut base_mut
    head_mut=""
    base_mut=""
    if grep -E '^(gh api -X (PATCH|POST)|gh api -X DELETE|git push |git branch -D |git checkout |git switch )' \
      "$head_log" > "$case_dir/head.mut" 2>/dev/null; then
      head_mut="$(normalize_parity_text < "$case_dir/head.mut")"
    fi
    if grep -E '^(gh api -X (PATCH|POST)|gh api -X DELETE|git push |git branch -D |git checkout |git switch )' \
      "$base_log" > "$case_dir/base.mut" 2>/dev/null; then
      base_mut="$(normalize_parity_text < "$case_dir/base.mut")"
    fi
    # Also compare full call logs (read + mutate) for byte-identical tooling surface.
    local head_all base_all
    head_all="$(normalize_parity_text < "$head_log")"
    base_all="$(normalize_parity_text < "$base_log")"
    if [ "$head_all" = "$base_all" ]; then
      run_test "parity_${label}_calls" "match" "match"
    else
      # Prefer mutation equality as the hard gate if read-order differs only by
      # harmless extras; still fail when mutations diverge.
      if [ "$head_mut" = "$base_mut" ]; then
        run_test "parity_${label}_calls" "match" "match"
      else
        printf '%s\n' "$head_all" > "$case_dir/head.calls.norm"
        printf '%s\n' "$base_all" > "$case_dir/base.calls.norm"
        run_test "parity_${label}_calls" "match" "DIFF see $case_dir/*.calls*"
      fi
    fi
    PARITY_COUNT=$((PARITY_COUNT + 1))
  }

  for provider in github_projects github_issues; do
    # --from-changelog × heading matrix
    run_parity_one "${provider}_fc_123_heading_bare" "$provider" "1.2.3" "1.2.3" \
      --from-changelog --best-effort
    run_parity_one "${provider}_fc_v123_heading_v" "$provider" "v1.2.3" "v1.2.3" \
      --from-changelog --best-effort
    run_parity_one "${provider}_fc_rel_v123_heading_bare" "$provider" "release/v1.2.3" "1.2.3" \
      --from-changelog --best-effort
    run_parity_one "${provider}_fc_mobile_heading_mobile" "$provider" "mobile-v1.1.0" "mobile-v1.1.0" \
      --from-changelog --best-effort
    run_parity_one "${provider}_fc_rc_heading_bare" "$provider" "1.2.3-rc.1" "1.2.3" \
      --from-changelog --best-effort
    run_parity_one "${provider}_fc_123_missing" "$provider" "1.2.3" "MISSING" \
      --from-changelog --best-effort
    # Explicit issues (no changelog scope)
    run_parity_one "${provider}_issue_123" "$provider" "1.2.3" "1.2.3" \
      --issue 101 --best-effort
    run_parity_one "${provider}_issues_v123" "$provider" "v1.2.3" "v1.2.3" \
      --issues 101,102 --best-effort
    run_parity_one "${provider}_issue_mobile" "$provider" "mobile-v1.1.0" "mobile-v1.1.0" \
      --issue 101 --best-effort
    # --json where applicable (single-repo; no evidence file)
    run_parity_one "${provider}_fc_123_json" "$provider" "1.2.3" "1.2.3" \
      --from-changelog --best-effort --json
    run_parity_one "${provider}_issue_json" "$provider" "v1.2.3" "v1.2.3" \
      --issue 101 --best-effort --json
  done

  # --- Component --json parity (emit_component_cleanup_json GitHub shape) ---
  # Use REAL_GIT captured before MOCK_BIN shadowed PATH (not command -v git).
  REAL_GIT_PARITY="$REAL_GIT"
  run_parity_component() {
    local label="$1"
    local provider="$2"
    shift 2
    # remaining: extra cleanup argv (e.g. --from-changelog)
    local case_dir="$PARITY_ROOT/case-${label}"
    mkdir -p "$case_dir"
    local root="$case_dir/root"
    rm -rf "$root"
    mkdir -p "$root"

    "$REAL_GIT_PARITY" init -q --bare "$root/origin.git"
    mkdir -p "$root/mobile-app"
    "$REAL_GIT_PARITY" -C "$root/mobile-app" init -q -b main
    "$REAL_GIT_PARITY" -C "$root/mobile-app" config user.email test@example.com
    "$REAL_GIT_PARITY" -C "$root/mobile-app" config user.name test
    "$REAL_GIT_PARITY" -C "$root/mobile-app" commit -q --allow-empty -m init
    "$REAL_GIT_PARITY" -C "$root/mobile-app" remote add origin "$root/origin.git"
    "$REAL_GIT_PARITY" -C "$root/mobile-app" push -q origin main
    "$REAL_GIT_PARITY" -C "$root/mobile-app" checkout -q -b release-base
    "$REAL_GIT_PARITY" -C "$root/mobile-app" push -q origin release-base
    cat > "$root/mobile-app/CHANGELOG.md" <<'MD'
# Changelog

## [Unreleased]

## [1.0.0] - 2026-06-11

### Fixed

- Fixed some bug (#101).
MD
    "$REAL_GIT_PARITY" -C "$root/mobile-app" add CHANGELOG.md
    "$REAL_GIT_PARITY" -C "$root/mobile-app" commit -q -m changelog
    "$REAL_GIT_PARITY" -C "$root/mobile-app" checkout -q -b mobile-app/release/v1.0.0
    "$REAL_GIT_PARITY" -C "$root/mobile-app" commit -q --allow-empty -m release
    "$REAL_GIT_PARITY" -C "$root/mobile-app" push -q origin mobile-app/release/v1.0.0
    local release_tip
    release_tip="$("$REAL_GIT_PARITY" -C "$root/mobile-app" rev-parse mobile-app/release/v1.0.0)"
    "$REAL_GIT_PARITY" -C "$root/mobile-app" checkout -q main

    mkdir -p "$root/hub/scripts/development-workflow" "$root/hub/bin"
    "$REAL_GIT_PARITY" init -q "$root/hub"
    cp "$REPO_ROOT/scripts/development-workflow/component-release-target.sh" \
      "$root/hub/scripts/development-workflow/component-release-target.sh"
    cp "$REPO_ROOT/scripts/development-workflow/workflow-config-resolver.py" \
      "$root/hub/scripts/development-workflow/workflow-config-resolver.py"
    chmod +x "$root/hub/scripts/development-workflow/"*.sh

    if [ "$provider" = "github_projects" ]; then
      cat > "$root/hub/.ai-dev-workflow.yaml" <<'YAML'
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
    else
      cat > "$root/hub/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
mode: workflow_hub
issue_tracker:
  provider: github_issues

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
    fi
    cat > "$root/hub/.ai-dev-workflow.local.yaml" <<YAML
product_repos:
  - name: mobile-app
    local_path: ../mobile-app
YAML
    # GitHub --from-changelog checks CHANGELOG.md relative to hub CWD (develop).
    cat > "$root/hub/CHANGELOG.md" <<'MD'
# Changelog

## [Unreleased]

## [1.0.0] - 2026-06-11

### Fixed

- Fixed some bug (#101).
MD

    # Shared stub lib (identical for HEAD and baseline) — isolates cleanup script.
    cat > "$root/hub/scripts/development-workflow/workflow-lib.sh" <<STUB
#!/usr/bin/env bash
cd_workflow_repo_root() { return 0; }
require_gh() { return 0; }
workflow_issue_tracker_provider_raw() { printf '%s\n' "$provider"; }
workflow_normalize_issue_tracker_provider() { printf '%s' "\$1" | tr '[:upper:]' '[:lower:]'; }
workflow_issue_tracker_project_number() { printf '1\n'; }
workflow_resolve_github_repo_owner() { printf 'example\n'; }
workflow_resolve_github_repo_name() { printf 'mobile-app\n'; }
workflow_resolve_github_project_owner() { printf 'example\n'; }
workflow_is_valid_github_owner() {
  case "\$1" in ''|-*|*-|*[!A-Za-z0-9-]*) return 1 ;; esac
  return 0
}
workflow_is_valid_github_repo_name() {
  case "\$1" in ''|'.'|'..'|*[!A-Za-z0-9._-]*) return 1 ;; esac
  return 0
}
workflow_is_valid_github_repo_slug() {
  local repo_slug="\$1"
  local owner="\${repo_slug%%/*}"
  local repo_name="\${repo_slug#*/}"
  [ "\$owner/\$repo_name" = "\$repo_slug" ] || return 1
  workflow_is_valid_github_owner "\$owner" || return 1
  workflow_is_valid_github_repo_name "\$repo_name" || return 1
  return 0
}
record_release_for_issue_best_effort() {
  printf 'RELEASE_STAMP_SKIPPED issue=%s version=%s provider=%s reason=parity_stub\n' "\$1" "\$2" "$provider"
}
update_tracker_status_best_effort() {
  printf 'Updating tracker status for issue %s to Released...\n' "\$1"
}
STUB

    local head_log="$case_dir/head.calls"
    local base_log="$case_dir/base.calls"
    install_component_parity_gh() {
      local log="$1"
      cat > "$root/hub/bin/gh" <<EOF
#!/usr/bin/env bash
printf 'gh %s\n' "\$*" >> "$log"
case "\$*" in
  "pr list --repo example/mobile-app --state merged --head mobile-app/release/v1.0.0 --base main --json number --jq .[0].number // empty")
    printf '900\n' ;;
  "pr list --repo example/mobile-app --state merged --head mobile-app/release/v1.0.0 --base release-base --json number --jq .[0].number // empty")
    printf '901\n' ;;
  "pr list --repo example/mobile-app --state open --head mobile-app/release/v1.0.0 --base main --json number --jq .[0].number // empty")
    printf '\n' ;;
  "pr list --repo example/mobile-app --state open --head mobile-app/release/v1.0.0 --base release-base --json number --jq .[0].number // empty")
    printf '\n' ;;
  issue\ view\ *\ --json\ state\ --jq\ .state) printf 'OPEN\n' ;;
  "auth status") exit 0 ;;
  "api repos/example/mobile-app/releases/tags/v1.0.0"*)
    printf '\n' ;;
  "api repos/example/mobile-app/tags?per_page=100"*)
    printf 'v1.0.0\n' ;;
  *"user(login"*"projectV2"*)
    printf '{"data":{"user":{"projectV2":{"id":"PVT_test000001"}}}}\n' ;;
  *"organization(login"*"projectV2"*)
    printf '{"data":{"organization":{"projectV2":{"id":"PVT_test000001"}}}}\n' ;;
  *"projectId"*"ProjectV2"*"items"*)
    printf '{"data":{"node":{"items":{"nodes":[],"pageInfo":{"hasNextPage":false,"endCursor":""}}}}}\n' ;;
  "api graphql"*)
    printf '{"data":{"repository":{"issue":{"projectItems":{"nodes":[],"pageInfo":{"hasNextPage":false,"endCursor":""}}}}}}\n' ;;
  *)
    printf 'unexpected gh: %s\n' "\$*" >&2
    exit 64
    ;;
esac
EOF
      chmod +x "$root/hub/bin/gh"
    }

    restore_release_branch() {
      "$REAL_GIT_PARITY" -C "$root/mobile-app" checkout -q main 2>/dev/null || true
      "$REAL_GIT_PARITY" -C "$root/mobile-app" branch -f mobile-app/release/v1.0.0 "$release_tip"
      "$REAL_GIT_PARITY" -C "$root/origin.git" update-ref \
        refs/heads/mobile-app/release/v1.0.0 "$release_tip"
      "$REAL_GIT_PARITY" -C "$root/mobile-app" fetch -q origin \
        mobile-app/release/v1.0.0:mobile-app/release/v1.0.0 2>/dev/null || true
      "$REAL_GIT_PARITY" -C "$root/mobile-app" checkout -q main
    }

    run_one_side() {
      local script_src="$1"
      local log="$2"
      local out_file="$3"
      local err_file="$4"
      local status_file="$5"
      shift 5
      restore_release_branch
      cp "$script_src" \
        "$root/hub/scripts/development-workflow/prepare-release-post-merge-cleanup.sh"
      chmod +x "$root/hub/scripts/development-workflow/prepare-release-post-merge-cleanup.sh"
      : > "$log"
      install_component_parity_gh "$log"
      (
        cd "$root/hub"
        target_json="$(./scripts/development-workflow/component-release-target.sh \
          --repo-root "$PWD" --repo mobile-app \
          --release-branch mobile-app/release/v1.0.0 --json)"
        jq -nS --argjson target "$target_json" \
          '{
            schema_version:"component_release_evidence.v1",
            target_binding:$target,
            release_branch:"mobile-app/release/v1.0.0",
            release_outcome:"completed",
            ci_outcome:"passed",
            deployment_outcome:"recorded",
            cleanup_outcome:"not_started",
            hub_tracker_ref:"#101"
          }' > component-release-evidence.json
        set +e
        PATH="$PWD/bin:$(dirname "$REAL_GIT_PARITY"):$PATH" WORKFLOW_SKIP_FETCH=1 \
          ./scripts/development-workflow/prepare-release-post-merge-cleanup.sh \
          mobile-app/release/v1.0.0 \
          --repo mobile-app --repo-root "$PWD" \
          --evidence-file "$PWD/component-release-evidence.json" \
          --issue 101 --best-effort --json "$@" \
          > "$out_file" 2> "$err_file"
        echo $? > "$status_file"
        set -e
      )
    }

    run_one_side \
      "$REPO_ROOT/scripts/development-workflow/prepare-release-post-merge-cleanup.sh" \
      "$head_log" "$case_dir/head.stdout" "$case_dir/head.stderr" \
      "$case_dir/head.status" "$@"
    local head_status
    head_status="$(cat "$case_dir/head.status")"

    run_one_side \
      "$DEVELOP_BASELINE" \
      "$base_log" "$case_dir/base.stdout" "$case_dir/base.stderr" \
      "$case_dir/base.status" "$@"
    local base_status
    base_status="$(cat "$case_dir/base.status")"

    run_test "parity_${label}_exit" "$base_status" "$head_status"

    local head_out base_out head_err base_err
    head_out="$(normalize_parity_text < "$case_dir/head.stdout")"
    base_out="$(normalize_parity_text < "$case_dir/base.stdout")"
    head_err="$(normalize_parity_text < "$case_dir/head.stderr")"
    base_err="$(normalize_parity_text < "$case_dir/base.stderr")"

    # JSON stdout: normalize then compare; also assert no release_scope_skipped.
    if [ -n "$head_out" ] && jq empty <<<"$head_out" >/dev/null 2>&1; then
      head_out="$(printf '%s\n' "$head_out" | jq -cS . | normalize_parity_text)"
      base_out="$(printf '%s\n' "$base_out" | jq -cS . | normalize_parity_text)"
      if printf '%s' "$head_out" | jq -e 'has("release_scope_skipped")' >/dev/null 2>&1; then
        run_test "parity_${label}_no_skipped_field" "absent" "present"
      else
        run_test "parity_${label}_no_skipped_field" "absent" "absent"
      fi
    fi

    if [ "$head_out" = "$base_out" ]; then
      run_test "parity_${label}_stdout" "match" "match"
    else
      printf '%s\n' "$head_out" > "$case_dir/head.stdout.norm"
      printf '%s\n' "$base_out" > "$case_dir/base.stdout.norm"
      run_test "parity_${label}_stdout" "match" "DIFF see $case_dir/*.stdout*"
    fi
    if [ "$head_err" = "$base_err" ]; then
      run_test "parity_${label}_stderr" "match" "match"
    else
      printf '%s\n' "$head_err" > "$case_dir/head.stderr.norm"
      printf '%s\n' "$base_err" > "$case_dir/base.stderr.norm"
      run_test "parity_${label}_stderr" "match" "DIFF see $case_dir/*.stderr*"
    fi

    local head_all base_all
    head_all="$(normalize_parity_text < "$head_log")"
    base_all="$(normalize_parity_text < "$base_log")"
    if [ "$head_all" = "$base_all" ]; then
      run_test "parity_${label}_calls" "match" "match"
    else
      printf '%s\n' "$head_all" > "$case_dir/head.calls.norm"
      printf '%s\n' "$base_all" > "$case_dir/base.calls.norm"
      run_test "parity_${label}_calls" "match" "DIFF see $case_dir/*.calls*"
    fi
    PARITY_COUNT=$((PARITY_COUNT + 1))
  }

  for provider in github_projects github_issues; do
    run_parity_component "${provider}_component_issue_json" "$provider"
    run_parity_component "${provider}_component_fc_json" "$provider" --from-changelog
  done

  echo "Differential GitHub parity cases run: $PARITY_COUNT"
fi

echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"

if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi
