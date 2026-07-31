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
  "ls-remote --exit-code --heads origin mobile-app/release/v1.18.0")
    exit 2
    ;;
  "show-ref --quiet refs/heads/mobile-app/release/v1.18.0")
    exit 1
    ;;
  *)
    printf 'unexpected git invocation: git %s\n' "$*" >&2
    exit 64
    ;;
esac
MOCK_GIT

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
    printf '{"data":{"repository":{"issue":{"timelineItems":{"nodes":[{"__typename":"CrossReferencedEvent","source":{"__typename":"PullRequest","number":500,"merged":true}}],"pageInfo":{"hasNextPage":false,"endCursor":""}}}}}}\n' ;;
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
run_contains "detect_parent_epic_issues_list" "ISSUES=201" "$output"

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"

if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi
