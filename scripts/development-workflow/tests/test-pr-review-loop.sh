#!/usr/bin/env bash
# test-pr-review-loop.sh — pr-review-loop.sh harness: verdict, config, and
# lifecycle core, plus the ergonomics and size checks for the whole split
# harness.
# duration: 15
# covers: scripts/development-workflow/pr-review-loop.sh
# covers: scripts/development-workflow/tests/lib/pr-review-loop-harness.sh
# covers: docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md
# covers: .github/workflows/shellcheck.yml
# covers: scripts/development-workflow/tests/test-pr-review-loop-*.sh
#
# The pr-review-loop.sh harness is split across these suites (#1876), which
# share their preamble — snapshot re-exec, --area filter, gh/git mocks, the
# HARNESS_MODE source of pr-review-loop.sh, and the run_test helpers — through
# tests/lib/pr-review-loop-harness.sh:
#
#   test-pr-review-loop.sh
#   test-pr-review-loop-cycles-labels.sh
#   test-pr-review-loop-failure-paths-1.sh
#   test-pr-review-loop-failure-paths-2.sh
#   test-pr-review-loop-failure-paths-3.sh
#   test-pr-review-loop-failure-paths-4.sh
#   test-pr-review-loop-release-bugbot.sh
#   test-pr-review-loop-pr-agent-coderabbit.sh
#   test-pr-review-loop-staged-gates.sh
#   test-pr-review-loop-no-verdict-yet.sh
#
# Areas in this suite:
#   Area 0a: project advisory checks hook
#   Area 0: draft/ready lifecycle config parsing
#   Area 0b: doc branch timeout defaults
#   Area 1: normalize_platform_verdict
#   Area 2: check_unreplied_rest_comments
#   Area 3: append_compare_metrics_row (platform config detection)
#   Area 4: lock cleanup on SIGTERM
#   Area 5: auto_reply_unreplied_rest_comments
#   Area 6: check_unresolved_threads
#   Area 6b: check_unresolved_threads mode=provisional (#1508)
#   Area 7: bot_login_for_platform — copilot
#   Area 8: run_copilot_review — clean / needs_fixes / escalate
#   Area 9: haystack platform
#   Area 1710: local-ai quota escalate forwarding
#   Area 10: per-platform result tokens in summary comment
#   Area 10b: reviewer-loop history payload
#   Area 18: suite ergonomics and execution budget (#1562)
#   Area 1876: harness split into small suites
#
# Usage: bash scripts/development-workflow/tests/test-pr-review-loop.sh [--area <name>]... [--list-areas]
# No external tooling required beyond bash, git, and jq (git only locates the
# repository root at startup; mock gh commands replace all network calls).
#
# Exit code: 0 if all tests pass, 1 if any test fails, 2 on a usage error.
#
# Many assignments here set pr-review-loop.sh globals that the functions under
# test read. ShellCheck does not follow that source, so each such assignment
# carries its own `# shellcheck disable=SC2034` with the reason inline.

set -euo pipefail

# Resolve the shared harness from the checked-in suite path. Inside a snapshot
# run $0 is a temp copy, so TEST_PR_REVIEW_LOOP_ORIGIN (set by the harness on
# re-exec, or by hand for an out-of-tree copy) takes precedence.
_prl_harness="$(dirname -- "${TEST_PR_REVIEW_LOOP_ORIGIN:-$0}")/lib/pr-review-loop-harness.sh"
if [ ! -f "$_prl_harness" ]; then
  echo "ERROR: shared harness not found: $_prl_harness" >&2
  echo "  Run the checked-in suite, or set TEST_PR_REVIEW_LOOP_ORIGIN to its path." >&2
  exit 2
fi
# shellcheck source=scripts/development-workflow/tests/lib/pr-review-loop-harness.sh
source "$_prl_harness" "$@"
unset _prl_harness

# ---------------------------------------------------------------------------
# Area 0a: project advisory checks hook
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 0a: project advisory checks hook ==="

_ADVISORY_TMP="$(mktemp -d)"

set +e
_default_advisory_output="$(bash "$REPO_ROOT/scripts/development-workflow/run-advisory-checks.sh" 123)"
_default_advisory_status=$?
set -e
run_test "project_advisory_default_stub_exit" "0" "$_default_advisory_status"
run_test "project_advisory_default_stub_empty" "" "$_default_advisory_output"

_marker_script="$_ADVISORY_TMP/marker-advisory.sh"
_marker_file="$_ADVISORY_TMP/marker-count.txt"
_empty_advisory_output_file="$_ADVISORY_TMP/project-advisory-empty.out"
cat > "$_marker_script" <<'EOF_MARKER_ADVISORY'
#!/usr/bin/env bash
printf '%s\n' "${1:-}" >> "$MARKER_FILE"
printf '\n\n**Advisory checks** _(informational - never blocks merge)_\n'
printf -- '- marker ran for PR %s\n' "${1:-}"
EOF_MARKER_ADVISORY
chmod +x "$_marker_script"
MARKER_FILE="$_marker_file" run_project_advisory_checks "" "$_marker_script" >"$_empty_advisory_output_file"
if [ -e "$_marker_file" ]; then
  _empty_pr_invoked="yes"
else
  _empty_pr_invoked="no"
fi
run_test "project_advisory_empty_pr_no_invoke" "no" "$_empty_pr_invoked"
run_test "project_advisory_empty_pr_empty_output" "" "$(cat "$_empty_advisory_output_file")"

_missing_advisory_output="$(run_project_advisory_checks 42 "$_ADVISORY_TMP/missing-advisory.sh")"
run_test "project_advisory_missing_script_empty" "" "$_missing_advisory_output"

_marker_output="$(MARKER_FILE="$_marker_file" run_project_advisory_checks 42 "$_marker_script")"
run_test "project_advisory_marker_invoked_once" "1" "$(wc -l < "$_marker_file" | tr -d ' ')"
run_test "project_advisory_multiline_preserved" "yes" "$(
  if printf '%s\n' "$_marker_output" | grep -q 'marker ran for PR 42'; then
    printf 'yes'
  else
    printf 'no'
  fi
)"

_failing_advisory_script="$_ADVISORY_TMP/failing-advisory.sh"
cat > "$_failing_advisory_script" <<'EOF_FAILING_ADVISORY'
#!/usr/bin/env bash
printf '\n\n**Advisory checks** _(informational - never blocks merge)_\n'
printf -- '- diagnostic preserved\n'
exit 17
EOF_FAILING_ADVISORY
chmod +x "$_failing_advisory_script"
set +e
_failing_advisory_output="$(run_project_advisory_checks 42 "$_failing_advisory_script")"
_failing_advisory_status=$?
set -e
run_test "project_advisory_failure_returns_zero" "0" "$_failing_advisory_status"
run_test "project_advisory_failure_preserves_stdout" "yes" "$(
  if printf '%s\n' "$_failing_advisory_output" | grep -q 'diagnostic preserved'; then
    printf 'yes'
  else
    printf 'no'
  fi
)"

# ---------------------------------------------------------------------------
# Area 0: draft/ready lifecycle config parsing
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 0: draft/ready lifecycle config parsing ==="

_CONFIG_DIR="$(mktemp -d)"
cat > "$_CONFIG_DIR/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2

review:
  on_draft:
    runner:
      # Default Codex runner.
      - codex
    github:

      - pr-agent
  on_ready:
    github:
      - haystack
YAML

draft_runner_parsed="$(workflow_config_review_on_draft_runner "$_CONFIG_DIR/.ai-dev-workflow.yaml" | paste -sd ',' -)"
draft_github_parsed="$(workflow_config_review_on_draft_github "$_CONFIG_DIR/.ai-dev-workflow.yaml" | paste -sd ',' -)"
ready_github_parsed="$(workflow_config_review_on_ready_github "$_CONFIG_DIR/.ai-dev-workflow.yaml" | paste -sd ',' -)"
all_github_parsed="$(workflow_config_review_platforms "$_CONFIG_DIR/.ai-dev-workflow.yaml" | paste -sd ',' -)"
phase_after_clean_parsed="$(workflow_config_review_phase_after_clean_platforms "$_CONFIG_DIR/.ai-dev-workflow.yaml" | paste -sd ',' -)"
run_test "review_on_draft_runner_parser" "codex" "$draft_runner_parsed"
run_test "review_on_draft_github_parser" "pr-agent" "$draft_github_parsed"
run_test "review_on_ready_github_parser" "haystack" "$ready_github_parsed"
run_test "review_lifecycle_combined_platforms" "pr-agent,haystack" "$all_github_parsed"
run_test "phase_after_clean_compat_maps_ready_github" "haystack" "$phase_after_clean_parsed"

cat > "$_CONFIG_DIR/.ai-dev-workflow-legacy.yaml" <<'YAML'
schema_version: 1

review:
  platforms:
    - pr-agent
    - haystack
  phase_after_clean:
    - haystack
  internal_reviewers:
    - codex
YAML

legacy_draft_runner="$(workflow_config_review_on_draft_runner "$_CONFIG_DIR/.ai-dev-workflow-legacy.yaml" | paste -sd ',' -)"
legacy_draft_github="$(workflow_config_review_on_draft_github "$_CONFIG_DIR/.ai-dev-workflow-legacy.yaml" | paste -sd ',' -)"
legacy_ready_github="$(workflow_config_review_on_ready_github "$_CONFIG_DIR/.ai-dev-workflow-legacy.yaml" | paste -sd ',' -)"
legacy_all_github="$(workflow_config_review_platforms "$_CONFIG_DIR/.ai-dev-workflow-legacy.yaml" | paste -sd ',' -)"
run_test "legacy_internal_reviewers_mapping" "codex" "$legacy_draft_runner"
run_test "legacy_platforms_phase_draft_mapping" "pr-agent" "$legacy_draft_github"
run_test "legacy_platforms_phase_ready_mapping" "haystack" "$legacy_ready_github"
run_test "legacy_platforms_phase_combined_mapping" "pr-agent,haystack" "$legacy_all_github"

cat > "$_CONFIG_DIR/.ai-dev-workflow-legacy-platforms-only.yaml" <<'YAML'
schema_version: 1

review:
  platforms: [pr-agent, haystack]
YAML

legacy_platforms_only_ready="$(workflow_config_review_on_ready_github "$_CONFIG_DIR/.ai-dev-workflow-legacy-platforms-only.yaml" | paste -sd ',' -)"
run_test "legacy_platforms_without_phase_mapping" "pr-agent,haystack" "$legacy_platforms_only_ready"

cat > "$_CONFIG_DIR/.ai-dev-workflow-mixed.yaml" <<'YAML'
schema_version: 2

review:
  on_draft:
    runner: [codex]
    github: [pr-agent]
  on_ready:
    github: [haystack]
  internal_reviewers: [claude]
  platforms: [greptile, coderabbit]
  phase_after_clean: [coderabbit]
YAML

mixed_runner="$(workflow_config_review_on_draft_runner "$_CONFIG_DIR/.ai-dev-workflow-mixed.yaml" | paste -sd ',' -)"
mixed_draft_github="$(workflow_config_review_on_draft_github "$_CONFIG_DIR/.ai-dev-workflow-mixed.yaml" | paste -sd ',' -)"
mixed_ready_github="$(workflow_config_review_on_ready_github "$_CONFIG_DIR/.ai-dev-workflow-mixed.yaml" | paste -sd ',' -)"
mixed_all_github="$(workflow_config_review_platforms "$_CONFIG_DIR/.ai-dev-workflow-mixed.yaml" | paste -sd ',' -)"
run_test "mixed_new_legacy_runner_prefers_new" "codex" "$mixed_runner"
run_test "mixed_new_legacy_draft_prefers_new" "pr-agent" "$mixed_draft_github"
run_test "mixed_new_legacy_ready_prefers_new" "haystack" "$mixed_ready_github"
run_test "mixed_new_legacy_combined_prefers_new" "pr-agent,haystack" "$mixed_all_github"

_LOCAL_OVERRIDE_DIR="$(mktemp -d)"
cat > "$_LOCAL_OVERRIDE_DIR/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2

review:
  on_draft:
    runner: [codex]
    github: [pr-agent]
  on_ready:
    github: [haystack]
YAML
cat > "$_LOCAL_OVERRIDE_DIR/.ai-dev-workflow.local.yaml" <<'YAML'
review:
  on_draft:
    runner: [cursor]
    github: [pr-agent]
  on_ready:
    github: [bugbot]
YAML
local_override_parsed="$(
  workflow_repo_root() { printf '%s\n' "$_LOCAL_OVERRIDE_DIR"; }
  printf 'runner=%s\n' "$(workflow_config_review_on_draft_runner "$(workflow_config_file)" | paste -sd ',' -)"
  printf 'draft=%s\n' "$(workflow_config_review_on_draft_github "$(workflow_config_file)" | paste -sd ',' -)"
  printf 'ready=%s\n' "$(workflow_config_review_on_ready_github "$(workflow_config_file)" | paste -sd ',' -)"
  printf 'all=%s\n' "$(workflow_config_review_platforms "$(workflow_config_file)" | paste -sd ',' -)"
)"
run_test "local_review_override_applied" $'runner=cursor\ndraft=pr-agent\nready=bugbot\nall=pr-agent,bugbot' "$local_override_parsed"

_TEMP_CONFIG="$(mktemp)"
cat > "$_TEMP_CONFIG" <<'YAML'
schema_version: 2

review:
  on_draft:
    runner: [codex]
    github: [pr-agent]
  on_ready:
    github: [haystack]
YAML
temp_override_parsed="$(
  workflow_repo_root() { printf '%s\n' "$_LOCAL_OVERRIDE_DIR"; }
  WORKFLOW_APPLY_LOCAL_REVIEW_OVERRIDES=1 workflow_config_review_platforms "$_TEMP_CONFIG" | paste -sd ',' -
)"
run_test "local_review_override_applies_to_temp_config_when_forced" "pr-agent,bugbot" "$temp_override_parsed"

_TEMP_WORKTREE_DIR="$(mktemp -d)"
initiating_override_parsed="$(
  workflow_repo_root() { printf '%s\n' "$_TEMP_WORKTREE_DIR"; }
  WORKFLOW_LOCAL_REVIEW_OVERRIDE_ROOT="$_LOCAL_OVERRIDE_DIR" \
    WORKFLOW_APPLY_LOCAL_REVIEW_OVERRIDES=1 \
    workflow_config_review_platforms "$_TEMP_CONFIG" | paste -sd ',' -
)"
run_test "initiating_local_override_applies_in_temp_worktree" "pr-agent,bugbot" "$initiating_override_parsed"

caller_override_root="$(
  WORKFLOW_LOCAL_REVIEW_OVERRIDE_ROOT="$_LOCAL_OVERRIDE_DIR" \
    resolve_local_review_override_root "$_TEMP_WORKTREE_DIR"
)"
run_test "caller_override_root_is_preserved" "$_LOCAL_OVERRIDE_DIR" "$caller_override_root"
rm -rf "$_TEMP_WORKTREE_DIR"
unset _TEMP_WORKTREE_DIR initiating_override_parsed caller_override_root

missing_override_status=0
if WORKFLOW_LOCAL_REVIEW_OVERRIDE_ROOT="$_LOCAL_OVERRIDE_DIR/missing" workflow_local_config_file >/dev/null 2>&1; then
  missing_override_status=0
else
  missing_override_status=$?
fi
run_test "unavailable_initiating_override_stops_resolution" "1" "$missing_override_status"

# #1560: an externally created linked worktree (plain `git worktree add`, the
# Protocol 90 isolation path) has no gitignored local override of its own. The
# initiating root must resolve to the main clone's file, and the exported
# override root must be the directory that actually holds it. The harness's
# git mock rejects everything but `rev-parse --git-common-dir`, so this block
# runs against the real git found on the PATH the harness started with.
_REAL_PATH="${PATH#"$MOCK_BIN:"}"
_WT_MAIN="$(mktemp -d)"
_WT_MAIN="$(CDPATH='' cd -- "$_WT_MAIN" && pwd -P)"
git() { PATH="$_REAL_PATH" command git "$@"; }
git -C "$_WT_MAIN" init -q
cat > "$_WT_MAIN/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2

review:
  on_draft:
    runner: [codex]
    github: [pr-agent]
  on_ready:
    github: [haystack]
YAML
git -C "$_WT_MAIN" add .ai-dev-workflow.yaml
git -C "$_WT_MAIN" -c user.name=fixture -c user.email=fixture@example.com commit -q -m init
cat > "$_WT_MAIN/.ai-dev-workflow.local.yaml" <<'YAML'
review:
  on_draft:
    runner: [cursor]
    github: [pr-agent]
  on_ready:
    github: [bugbot]
YAML
_WT_LINKED="$_WT_MAIN-linked"
git -C "$_WT_MAIN" worktree add -q "$_WT_LINKED" -b fixture/linked-1560 HEAD
# The resolver shells out to git itself, so it needs the real PATH too.
linked_override_root="$(PATH="$_REAL_PATH" resolve_local_review_override_root "$_WT_LINKED")"
run_test "linked_worktree_override_root_is_main_clone" "$_WT_MAIN" "$linked_override_root"
linked_local_file="$(
  workflow_repo_root() { printf '%s\n' "$_WT_LINKED"; }
  workflow_local_config_file
)"
run_test "linked_worktree_local_config_file_is_main_clone" "$_WT_MAIN/.ai-dev-workflow.local.yaml" "$linked_local_file"
linked_platforms="$(
  workflow_repo_root() { printf '%s\n' "$_WT_LINKED"; }
  workflow_config_review_platforms "$_WT_LINKED/.ai-dev-workflow.yaml" | paste -sd ',' -
)"
run_test "linked_worktree_applies_main_clone_review_override" "pr-agent,bugbot" "$linked_platforms"
linked_main_root="$(workflow_linked_worktree_main_root "$_WT_LINKED")"
run_test "linked_worktree_main_root_detected" "$_WT_MAIN" "$linked_main_root"
# A worktree-local file with no `review:` section (set-local-path output) must
# not mask the main clone's reviewer override.
printf 'product_repos:\n  - name: mobile-app\n    local_path: ../mobile-app\n' > "$_WT_LINKED/.ai-dev-workflow.local.yaml"
product_only_local_file="$(
  workflow_repo_root() { printf '%s\n' "$_WT_LINKED"; }
  workflow_local_config_file
)"
run_test "product_only_worktree_file_does_not_mask_main_clone" "$_WT_MAIN/.ai-dev-workflow.local.yaml" "$product_only_local_file"
printf 'review:\n  on_ready:\n    github: [haystack]\n' > "$_WT_LINKED/.ai-dev-workflow.local.yaml"
review_local_file="$(
  workflow_repo_root() { printf '%s\n' "$_WT_LINKED"; }
  workflow_local_config_file
)"
run_test "worktree_file_with_review_section_wins" "$_WT_LINKED/.ai-dev-workflow.local.yaml" "$review_local_file"
printf 'review: {}\n' > "$_WT_LINKED/.ai-dev-workflow.local.yaml"
empty_review_local_file="$(
  workflow_repo_root() { printf '%s\n' "$_WT_LINKED"; }
  workflow_local_config_file
)"
run_test "worktree_file_with_empty_review_key_wins" "$_WT_LINKED/.ai-dev-workflow.local.yaml" "$empty_review_local_file"
printf 'review : {}\n' > "$_WT_LINKED/.ai-dev-workflow.local.yaml"
spaced_review_local_file="$(
  workflow_repo_root() { printf '%s\n' "$_WT_LINKED"; }
  workflow_local_config_file
)"
run_test "worktree_file_with_spaced_review_key_wins" "$_WT_LINKED/.ai-dev-workflow.local.yaml" "$spaced_review_local_file"
# An unreadable checkout-local file is an error, not "no review section"
# (CodeRabbit on PR #1575). Skipped as root, where chmod 000 is readable.
if [ "$(id -u)" -ne 0 ]; then
  chmod 000 "$_WT_LINKED/.ai-dev-workflow.local.yaml"
  unreadable_status=0
  unreadable_out="$(
    workflow_repo_root() { printf '%s\n' "$_WT_LINKED"; }
    workflow_local_config_file 2>/dev/null
  )" || unreadable_status=$?
  run_test "unreadable_worktree_file_is_an_error" "1:" "$unreadable_status:$unreadable_out"
  chmod 644 "$_WT_LINKED/.ai-dev-workflow.local.yaml"
  unset unreadable_status unreadable_out
fi
rm -f "$_WT_LINKED/.ai-dev-workflow.local.yaml"
# An unreadable main-clone file is the same structured error as an unreadable
# checkout file — the checkout has none of its own, so resolution falls
# through to the main clone, and that file cannot be read either.
if [ "$(id -u)" -ne 0 ]; then
  chmod 000 "$_WT_MAIN/.ai-dev-workflow.local.yaml"
  unreadable_main_status=0
  unreadable_main_out="$(
    workflow_repo_root() { printf '%s\n' "$_WT_LINKED"; }
    workflow_local_config_file 2>/dev/null
  )" || unreadable_main_status=$?
  run_test "unreadable_main_clone_file_is_an_error" "1:" "$unreadable_main_status:$unreadable_main_out"
  chmod 644 "$_WT_MAIN/.ai-dev-workflow.local.yaml"
  unset unreadable_main_status unreadable_main_out
fi
main_root_status=0
workflow_linked_worktree_main_root "$_WT_MAIN" >/dev/null 2>&1 || main_root_status=$?
run_test "main_clone_is_not_a_linked_worktree" "1" "$main_root_status"
# Detection is git-free: under the harness's git mock (which exits 64 for
# anything but one rev-parse form) the worktree is still recognised, and no
# git call is logged. run-epic-policy-recommender.sh relies on this — it is
# forbidden from invoking git, and it reads the review config through these
# helpers (caught by its CI suite, not locally, where the local file exists).
mock_git_status=0
mock_git_main_root="$(
  unset -f git
  workflow_linked_worktree_main_root "$_WT_LINKED" 2>/dev/null
)" || mock_git_status=$?
run_test "linked_worktree_detected_without_invoking_git" "0:$_WT_MAIN" "$mock_git_status:$mock_git_main_root"
# The referenced gitdir must exist: otherwise path resolution fails before
# the worktrees-layout check and the test proves nothing about that check.
mkdir -p "$_WT_MAIN/.git/modules/sub" "$_WT_MAIN/fake-submodule"
printf 'gitdir: ../.git/modules/sub\n' > "$_WT_MAIN/fake-submodule/.git"
submodule_status=0
workflow_linked_worktree_main_root "$_WT_MAIN/fake-submodule" >/dev/null 2>&1 || submodule_status=$?
run_test "submodule_gitdir_file_is_not_a_linked_worktree" "1" "$submodule_status"
git -C "$_WT_MAIN" worktree remove --force "$_WT_LINKED"
unset -f git
rm -rf "$_WT_MAIN"
unset _REAL_PATH _WT_MAIN _WT_LINKED linked_override_root linked_local_file linked_platforms linked_main_root main_root_status mock_git_status mock_git_main_root product_only_local_file review_local_file empty_review_local_file spaced_review_local_file

cat > "$_LOCAL_OVERRIDE_DIR/.ai-dev-workflow.local.yaml" <<'YAML'
review:
  on_ready:
    github: []
YAML
local_empty_ready_parsed="$(
  workflow_repo_root() { printf '%s\n' "$_LOCAL_OVERRIDE_DIR"; }
  workflow_config_review_on_ready_github "$(workflow_config_file)" | paste -sd ',' -
)"
run_test "local_review_override_empty_ready_github_applied" "" "$local_empty_ready_parsed"
rm -rf "$_LOCAL_OVERRIDE_DIR"
rm -f "$_TEMP_CONFIG"
unset _LOCAL_OVERRIDE_DIR _TEMP_CONFIG local_override_parsed local_empty_ready_parsed temp_override_parsed

cat > "$_CONFIG_DIR/.ai-dev-workflow-duplicates.yaml" <<'YAML'
schema_version: 2

review:
  on_draft:
    runner: [codex]
    github: [pr-agent, haystack]
  on_ready:
    github: [haystack]
YAML

duplicate_warning="$(emit_review_lifecycle_duplicate_warnings "$_CONFIG_DIR/.ai-dev-workflow-duplicates.yaml" 2>&1 || true)"
case "$duplicate_warning" in
  *'reviewer "haystack" in more than one bucket'*) duplicate_detected=yes ;;
  *) duplicate_detected=no ;;
esac
run_test "duplicate_lifecycle_reviewer_warning" "yes" "$duplicate_detected"

_DUP_OVERRIDE_DIR="$(mktemp -d)"
cat > "$_DUP_OVERRIDE_DIR/.ai-dev-workflow.local.yaml" <<'YAML'
review:
  on_draft:
    github: [bugbot]
  on_ready:
    github: [bugbot]
YAML
_DUP_TEMP_CONFIG="$(mktemp)"
cat > "$_DUP_TEMP_CONFIG" <<'YAML'
schema_version: 2

review:
  on_draft:
    github: [pr-agent]
  on_ready:
    github: [haystack]
YAML
duplicate_override_warning="$(
  workflow_repo_root() { printf '%s\n' "$_DUP_OVERRIDE_DIR"; }
  WORKFLOW_APPLY_LOCAL_REVIEW_OVERRIDES=1 emit_review_lifecycle_duplicate_warnings "$_DUP_TEMP_CONFIG" 2>&1 || true
)"
case "$duplicate_override_warning" in
  *'reviewer "bugbot" in more than one bucket'*) duplicate_override_detected=yes ;;
  *) duplicate_override_detected=no ;;
esac
run_test "duplicate_lifecycle_warning_uses_local_override_for_temp_config" "yes" "$duplicate_override_detected"
rm -rf "$_DUP_OVERRIDE_DIR"
rm -f "$_DUP_TEMP_CONFIG"
unset _DUP_OVERRIDE_DIR _DUP_TEMP_CONFIG duplicate_override_warning duplicate_override_detected

declare -a phase_after_clean_platforms=()
append_phase_after_clean_platforms "coderabbit, pr-agent"
if is_phase_after_clean_platform "coderabbit" && is_phase_after_clean_platform "pr-agent"; then
  phase_membership="yes"
else
  phase_membership="no"
fi
run_test "phase_after_clean_membership" "yes" "$phase_membership"

declare -a phase_after_clean_platforms=("coderabbit")
declare -a platforms=("pr-agent")
phase_after_clean_filtered_out=""
filter_phase_after_clean_platforms
run_test "phase_after_clean_filters_absent_platform" "0" "${#phase_after_clean_platforms[@]}"
run_test "phase_after_clean_filtered_out_records_absent_platform" "coderabbit" "$phase_after_clean_filtered_out"

declare -a phase_after_clean_platforms=("coderabbit")
declare -a platforms=("pr-agent" "coderabbit")
filter_pre_after_clean_platforms
run_test "pre_after_clean_only_filters_phase_platform" "pr-agent" "${platforms[0]}"
run_test "pre_after_clean_only_platform_count" "1" "${#platforms[@]}"

declare -a phase_after_clean_platforms=("haystack")
declare -a platforms=("pr-agent" "haystack")
filter_pre_after_clean_platforms
run_test "draft_github_only_filters_ready_reviewers" "pr-agent" "${platforms[0]}"

if grep -q -- '--ready-phase)' "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh" \
    && grep -q 'append_ready_phase_platforms "$2"' "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh"; then
  _ready_phase_flag_parse=1
else
  _ready_phase_flag_parse=0
fi
run_test "ready_phase_flag_parsing_wired" "1" "$_ready_phase_flag_parse"

if grep -q -- '--draft-github-only)' "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh" \
    && grep -q 'pre_after_clean_only=1' "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh"; then
  _draft_github_only_flag_parse=1
else
  _draft_github_only_flag_parse=0
fi
run_test "draft_github_only_flag_parsing_wired" "1" "$_draft_github_only_flag_parse"
unset _ready_phase_flag_parse _draft_github_only_flag_parse

# ---------------------------------------------------------------------------
# Area 0b: doc branch timeout defaults
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 0b: doc branch timeout defaults ==="

unset PR_REVIEW_LOOP_DOC_MAX_WAIT
run_test "doc_branch_default_max_wait" "180" "$(doc_branch_default_max_wait)"

PR_REVIEW_LOOP_DOC_MAX_WAIT=240
export PR_REVIEW_LOOP_DOC_MAX_WAIT
run_test "doc_branch_env_override_max_wait" "240" "$(doc_branch_default_max_wait)"

PR_REVIEW_LOOP_DOC_MAX_WAIT=abc
export PR_REVIEW_LOOP_DOC_MAX_WAIT
_doc_timeout_output="$(doc_branch_default_max_wait 2>/dev/null)"
run_test "doc_branch_invalid_env_falls_back" "180" "$_doc_timeout_output"

# #1789: the documentation-branch poll interval is resolved per platform by
# reviewer_poll_interval_resolve (plan D14); the clamp below the budget is
# unchanged.
_0b_saved_branch="${branch_name-}"
branch_name="spec/0b-doc"
unset poll_interval_override
run_test "doc_branch_poll_interval_default" "30" "$(reviewer_poll_interval_resolve devin 180)"
run_test "doc_branch_poll_interval_equal_clamps" "15" "$(reviewer_poll_interval_resolve devin 30)"
run_test "doc_branch_poll_interval_greater_clamps" "10" "$(reviewer_poll_interval_resolve devin 20)"
branch_name="$_0b_saved_branch"
unset _0b_saved_branch

unset PR_REVIEW_LOOP_DOC_MAX_WAIT _doc_timeout_output

unset CODEX_GITHUB_MAX_WAIT CODEX_GITHUB_POLL_INTERVAL
run_test "codex_github_default_max_wait" "1800" "$(codex_github_default_max_wait)"
run_test "codex_github_default_poll_interval" "60" "$(codex_github_default_poll_interval 1800)"
run_test "codex_github_poll_interval_clamps_to_budget" "15" "$(codex_github_default_poll_interval 30)"

CODEX_GITHUB_MAX_WAIT=2400
CODEX_GITHUB_POLL_INTERVAL=90
export CODEX_GITHUB_MAX_WAIT CODEX_GITHUB_POLL_INTERVAL
run_test "codex_github_env_override_max_wait" "2400" "$(codex_github_default_max_wait)"
run_test "codex_github_env_override_poll_interval" "90" "$(codex_github_default_poll_interval 2400)"

CODEX_GITHUB_MAX_WAIT=bad
CODEX_GITHUB_POLL_INTERVAL=bad
export CODEX_GITHUB_MAX_WAIT CODEX_GITHUB_POLL_INTERVAL
_codex_timeout_output="$(codex_github_default_max_wait 2>/dev/null)"
_codex_poll_output="$(codex_github_default_poll_interval 1800 2>/dev/null)"
run_test "codex_github_invalid_env_falls_back_max_wait" "1800" "$_codex_timeout_output"
run_test "codex_github_invalid_env_falls_back_poll_interval" "60" "$_codex_poll_output"

# #1789: the Codex GitHub defaults no longer drive a global budget or poll
# interval. They apply to codex-github only; a peer platform configured in the
# same run keeps its own default (plan D2/D14).
unset CODEX_GITHUB_MAX_WAIT CODEX_GITHUB_POLL_INTERVAL max_wait_override poll_interval_override
_0b_saved_branch="${branch_name-}"
_0b_saved_config="${config_file-}"
branch_name="feature/0b-codex"
config_file="/nonexistent/0b-config.yaml"
# shellcheck disable=SC2034  # read by functions sourced from pr-review-loop.sh
changed_files_count=-1
declare -a platforms=("pr-agent" "codex-github")
declare -a phase_after_clean_platforms=()
run_test "codex_github_defaults_apply_to_codex_budget" "1800 default none" "$(reviewer_wait_budget_resolve codex-github)"
run_test "codex_github_defaults_apply_to_codex_poll" "60" "$(reviewer_poll_interval_resolve codex-github 1800)"
run_test "codex_github_defaults_not_applied_to_peer_budget" "1200 default none" "$(reviewer_wait_budget_resolve pr-agent)"
run_test "codex_github_defaults_not_applied_to_peer_poll" "120" "$(reviewer_poll_interval_resolve pr-agent 1200)"
CODEX_GITHUB_MAX_WAIT=2400
export CODEX_GITHUB_MAX_WAIT
run_test "codex_github_env_budget_is_codex_configured_value" "2400 configured none" "$(reviewer_wait_budget_resolve codex-github)"
run_test "codex_github_env_budget_not_applied_to_peer" "1200 default none" "$(reviewer_wait_budget_resolve pr-agent)"
CODEX_GITHUB_MAX_WAIT=bad
_0b_codex_bad_err="$(reviewer_wait_budget_resolve codex-github 2>&1 >/dev/null)"
run_test "codex_github_invalid_env_budget_falls_back_to_default" "1800 default none" "$(reviewer_wait_budget_resolve codex-github 2>/dev/null)"
run_contains "codex_github_invalid_env_budget_keeps_existing_warning" "WARN: CODEX_GITHUB_MAX_WAIT must be a positive integer" "$_0b_codex_bad_err"
unset CODEX_GITHUB_MAX_WAIT _0b_codex_bad_err
branch_name="$_0b_saved_branch"
config_file="$_0b_saved_config"
unset _0b_saved_branch _0b_saved_config

run_test "codex_github_pre_trigger_wait_forwarded" "yes" \
  "$(if grep -q -- '--pre-trigger-wait "$pre_trigger_wait"' "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh"; then printf yes; else printf no; fi)"

platforms=()
phase_after_clean_platforms=()
unset CODEX_GITHUB_MAX_WAIT CODEX_GITHUB_POLL_INTERVAL _codex_timeout_output _codex_poll_output _codex_defaults_apply_active _codex_defaults_apply_telemetry

# ---------------------------------------------------------------------------
# Area 1: normalize_platform_verdict
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 1: normalize_platform_verdict ==="

actual="$(normalize_platform_verdict "clean" "")"
run_test "verdict_clean" "clean" "$actual"

actual="$(normalize_platform_verdict "needs_fixes" "")"
run_test "verdict_needs_fixes" "blocking" "$actual"

actual="$(normalize_platform_verdict "advisory" "")"
run_test "verdict_advisory" "advisory" "$actual"

actual="$(normalize_platform_verdict "skipped" "")"
run_test "verdict_skipped" "unavailable" "$actual"

actual="$(normalize_platform_verdict "needs_rerun" "")"
run_test "verdict_needs_rerun" "blocking" "$actual"

actual="$(normalize_platform_verdict "waiting_on_reviewer" "REASON=codex-github-review-pending")"
run_test "verdict_waiting_on_reviewer" "waiting" "$actual"

actual="$(normalize_platform_verdict "escalate" "REASON=timeout")"
run_test "verdict_escalate_timeout" "timed out" "$actual"

actual="$(normalize_platform_verdict "escalate" "REASON=timed_out")"
run_test "verdict_escalate_timed_out" "timed out" "$actual"

actual="$(normalize_platform_verdict "escalate" "REASON=max_wait_exceeded")"
run_test "verdict_escalate_max_wait" "timed out" "$actual"

actual="$(normalize_platform_verdict "escalate" "REASON=no_response")"
run_test "verdict_escalate_no_response" "timed out" "$actual"

actual="$(normalize_platform_verdict "escalate" "REASON=rate_limit_max_retries")"
run_test "verdict_escalate_rate_limit_max_retries" "timed out" "$actual"

actual="$(normalize_platform_verdict "escalate" "REASON=pending_timeout")"
run_test "verdict_escalate_pending_timeout" "timed out" "$actual"

actual="$(normalize_platform_verdict "escalate" "REASON=service_error")"
run_test "verdict_escalate_unknown" "unavailable" "$actual"

actual="$(normalize_platform_verdict "something_else" "")"
run_test "verdict_unknown_token" "unavailable" "$actual"

# ---------------------------------------------------------------------------
# Area 2: check_unreplied_rest_comments
#
# gh api --paginate writes one JSON array per page as separate documents.
# jq -s wraps multiple documents into an array of arrays: [[page1_items], ...].
# For single-page mocks, output one JSON array; jq -s wraps it to [[...items...]].
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 2: check_unreplied_rest_comments ==="

# test: no comments at all
export MOCK_GH_OUTPUT='[]'
actual="$(check_unreplied_rest_comments "1" "owner/repo" "coderabbitai[bot]" "[]")"
run_test "rest_no_comments" "0" "$actual"

# test: one root comment from bot, no replies
export MOCK_GH_OUTPUT='[{"id":10,"in_reply_to_id":null,"user":{"login":"coderabbitai[bot]"},"body":"Finding X"}]'
actual="$(check_unreplied_rest_comments "1" "owner/repo" "coderabbitai[bot]" "[]")"
run_test "rest_single_bot_root_unreplied" "1" "$actual"

# test: bot root comment with one human reply
export MOCK_GH_OUTPUT='[{"id":10,"in_reply_to_id":null,"user":{"login":"coderabbitai[bot]"},"body":"Finding X"},{"id":11,"in_reply_to_id":10,"user":{"login":"humanuser"},"body":"Acknowledged"}]'
actual="$(check_unreplied_rest_comments "1" "owner/repo" "coderabbitai[bot]" "[]")"
run_test "rest_bot_root_with_human_reply" "0" "$actual"

# test: bot root comment with bot-only reply (bot replies do not count as acknowledgment)
export MOCK_GH_OUTPUT='[{"id":10,"in_reply_to_id":null,"user":{"login":"coderabbitai[bot]"},"body":"Finding X"},{"id":11,"in_reply_to_id":10,"user":{"login":"someother[bot]"},"body":"Auto-ack"}]'
actual="$(check_unreplied_rest_comments "1" "owner/repo" "coderabbitai[bot]" "[]")"
run_test "rest_bot_root_with_bot_reply_only" "1" "$actual"

# test: root comment body contains "✅ Addressed" — self-resolved, excluded
export MOCK_GH_OUTPUT='[{"id":10,"in_reply_to_id":null,"user":{"login":"coderabbitai[bot]"},"body":"✅ Addressed — no action needed"}]'
actual="$(check_unreplied_rest_comments "1" "owner/repo" "coderabbitai[bot]" "[]")"
run_test "rest_addressed_marker" "0" "$actual"

# test: root comment whose GraphQL thread is already resolved (id in resolved_ids)
export MOCK_GH_OUTPUT='[{"id":10,"in_reply_to_id":null,"user":{"login":"coderabbitai[bot]"},"body":"Finding X"}]'
actual="$(check_unreplied_rest_comments "1" "owner/repo" "coderabbitai[bot]" "[10]")"
run_test "rest_resolved_id_excluded" "0" "$actual"

# test: root comment from non-bot human user — not counted (only bot roots are tracked)
export MOCK_GH_OUTPUT='[{"id":10,"in_reply_to_id":null,"user":{"login":"humanuser"},"body":"Human comment"}]'
actual="$(check_unreplied_rest_comments "1" "owner/repo" "coderabbitai[bot]" "[]")"
run_test "rest_human_comment_ignored" "0" "$actual"

# test: three bot root comments, one with human reply — expect count 2
export MOCK_GH_OUTPUT='[
  {"id":10,"in_reply_to_id":null,"user":{"login":"coderabbitai[bot]"},"body":"Finding A"},
  {"id":11,"in_reply_to_id":null,"user":{"login":"coderabbitai[bot]"},"body":"Finding B"},
  {"id":12,"in_reply_to_id":null,"user":{"login":"coderabbitai[bot]"},"body":"Finding C"},
  {"id":13,"in_reply_to_id":11,"user":{"login":"humanuser"},"body":"Acknowledged B"}
]'
actual="$(check_unreplied_rest_comments "1" "owner/repo" "coderabbitai[bot]" "[]")"
run_test "rest_multiple_bot_comments_partial_replied" "2" "$actual"

# ---------------------------------------------------------------------------
# Area 3: append_compare_metrics_row — platform config change detection
#
# workflow_repo_root is overridden to return a temp directory per test.
# The metrics file is at <repo_root>/docs/workflow/retro-metrics-platforms.md.
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 3: append_compare_metrics_row (platform config detection) ==="

# Helper: create a fresh temp directory for each Area 3 test.
# The metrics file lives at $tmpdir/docs/workflow/retro-metrics-platforms.md.
_setup_metrics_dir() {
  if [ -n "${_METRICS_DIR:-}" ]; then
    rm -rf "$_METRICS_DIR"
  fi
  _METRICS_DIR="$(mktemp -d)"
  mkdir -p "$_METRICS_DIR/docs/workflow"
  export HARNESS_REPO_ROOT="$_METRICS_DIR"
  _METRICS_TMP="$_METRICS_DIR/docs/workflow/retro-metrics-platforms.md"
}

# Helper: count data rows in the metrics file (lines starting with "| #").
# grep -c exits 1 when count is 0, so capture exit code separately.
_count_data_rows() {
  local n
  n="$(grep -c '^| #' "$_METRICS_TMP" 2>/dev/null)" || n="0"
  printf '%s\n' "$n"
}

# Helper: check whether a separator comment row exists (lines containing
# "*(platforms changed:").
# Returns 0 if no separator, 1+ if separator found.
_has_separator_row() {
  local n
  n="$(grep -c '(platforms changed:' "$_METRICS_TMP" 2>/dev/null)" || n="0"
  printf '%s\n' "$n"
}

# test: file does not exist — should be created with header and one data row
_setup_metrics_dir
append_compare_metrics_row "42" "fix/some-branch" "clean" "coderabbit" "clean"
if [ -f "$_METRICS_TMP" ]; then
  data_rows="$(_count_data_rows)"
  run_test "compare_no_existing_file" "1" "$data_rows"
else
  run_test "compare_no_existing_file" "file_exists" "file_missing"
fi

# test: same platform set and order — no separator comment row
_setup_metrics_dir
# Create initial state with coderabbit
append_compare_metrics_row "10" "fix/first" "clean" "coderabbit" "clean"
# Append second row with same platform
append_compare_metrics_row "11" "fix/second" "blocking" "coderabbit" "blocking"
sep_count="$(_has_separator_row)"
data_rows="$(_count_data_rows)"
run_test "compare_same_platform_set_no_separator" "0" "$sep_count"
run_test "compare_same_platform_set_two_rows" "2" "$data_rows"

# test: platform added — existing file has fewer platforms; should insert separator
_setup_metrics_dir
# Create initial state with one platform
append_compare_metrics_row "10" "fix/first" "clean" "coderabbit" "clean"
# Append with two platforms now
append_compare_metrics_row "11" "fix/second" "clean" "coderabbit" "clean" "pr-agent" "clean"
sep_count="$(_has_separator_row)"
run_test "compare_platform_added" "1" "$sep_count"

# test: same platform count but different order — should insert separator
_setup_metrics_dir
append_compare_metrics_row "10" "fix/first" "clean" "coderabbit" "clean" "pr-agent" "clean"
# Reversed order
append_compare_metrics_row "11" "fix/second" "clean" "pr-agent" "clean" "coderabbit" "clean"
sep_count="$(_has_separator_row)"
run_test "compare_platform_reordered" "1" "$sep_count"

# test: same platform count but renamed — should insert separator
_setup_metrics_dir
append_compare_metrics_row "10" "fix/first" "clean" "coderabbit" "clean"
# Different platform name (renamed)
append_compare_metrics_row "11" "fix/second" "clean" "pr-agent" "clean"
sep_count="$(_has_separator_row)"
run_test "compare_platform_renamed" "1" "$sep_count"

# ---------------------------------------------------------------------------
# Area 4: lock cleanup on SIGTERM
#
# This test verifies that the TERM signal trap in the lock guard section removes
# the lockdir before the process exits — specifically when the script is blocked
# inside _interruptible_sleep (a background sleep + wait pattern), which is the
# actual blocking pattern used in all polling loops.
#
# The previous test used "sleep 3600 & wait" directly in the wrapper.  That
# already uses the interruptible pattern, but it did NOT test the CURRENT_CHILD_PID
# kill-child step that the production code now uses to interrupt a running child
# before the wait returns.  This updated test reproduces the full
# _interruptible_sleep helper (including CURRENT_CHILD_PID tracking) so that the
# TERM handler's "kill -TERM $CURRENT_CHILD_PID" path is exercised.
#
# SIGINT is not testable via kill -INT on a background subprocess because bash
# sets SIGINT disposition to SIG_IGN for background processes (POSIX behaviour).
# The SIGINT trap is still valuable for interactive invocations (Ctrl+C) — it is
# verified by inspection rather than subprocess signalling.
#
# A self-contained wrapper script is used instead of invoking pr-review-loop.sh
# directly because the full script requires workflow-lib.sh functions and a
# valid git/gh context that are not available in the test environment.
# The lock guard section itself is small and stable; testing it in isolation
# avoids mocking the entire script ecosystem while still validating the traps.
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 4: lock cleanup on SIGTERM ==="

# Helper: spin up a subprocess that acquires a lockdir then blocks inside
# _interruptible_sleep (foreground blocking via background child + wait),
# send SIGTERM to the outer process, and verify the lockdir is removed.
_run_sigterm_lock_test() {
  local pr_num="9997${RANDOM}"
  local lock_dir="/tmp/pr-review-loop-${pr_num}.lockdir"
  rm -rf "$lock_dir"

  # Self-contained wrapper: reproduces the lock guard + CURRENT_CHILD_PID-aware
  # signal traps from pr-review-loop.sh, then calls _interruptible_sleep to
  # simulate the foreground-blocking polling-loop scenario that was the root
  # cause of #615.
  local wrapper
  # Use XXXXXX at the end (macOS mktemp requires Xs at the end of the template).
  wrapper="$(mktemp /tmp/pr-review-loop-lock-test.XXXXXX)"
  # Build with printf to avoid heredoc quoting issues with embedded variables.
  printf '#!/usr/bin/env bash\n'                                                          > "$wrapper"
  printf 'set -euo pipefail\n'                                                           >> "$wrapper"
  printf '_LOCK_DIR="%s"\n'                   "$lock_dir"                               >> "$wrapper"
  printf '_OWN_LOCK=0\n'                                                                 >> "$wrapper"
  printf 'CURRENT_CHILD_PID=""\n'                                                        >> "$wrapper"
  printf 'if mkdir "$_LOCK_DIR" 2>/dev/null; then\n'                                    >> "$wrapper"
  printf '  printf '"'"'%%d\\n'"'"' "$$"           > "$_LOCK_DIR/pid"\n'               >> "$wrapper"
  printf '  printf '"'"'%%s\\n'"'"' "test-locker"  > "$_LOCK_DIR/cmd"\n'               >> "$wrapper"
  printf '  _OWN_LOCK=1\n'                                                               >> "$wrapper"
  printf 'fi\n'                                                                           >> "$wrapper"
  printf 'trap '"'"'[ "$_OWN_LOCK" -eq 1 ] && rm -rf "$_LOCK_DIR"'"'"' EXIT\n'         >> "$wrapper"
  # Updated TERM/INT traps: kill the background child (CURRENT_CHILD_PID) before
  # removing the lock — mirrors the production trap handlers added to fix #615.
  printf 'trap '"'"'[ -n "$CURRENT_CHILD_PID" ] && kill -TERM "$CURRENT_CHILD_PID" 2>/dev/null || true; [ "$_OWN_LOCK" -eq 1 ] && rm -rf "$_LOCK_DIR"; trap - TERM; kill -TERM "$$"'"'"' TERM\n' >> "$wrapper"
  printf 'trap '"'"'[ -n "$CURRENT_CHILD_PID" ] && kill -TERM "$CURRENT_CHILD_PID" 2>/dev/null || true; [ "$_OWN_LOCK" -eq 1 ] && rm -rf "$_LOCK_DIR"; trap - INT;  kill -INT  "$$"'"'"' INT\n'  >> "$wrapper"
  # Reproduce _interruptible_sleep: start sleep as a background job so that
  # (a) CURRENT_CHILD_PID is set (exercising the kill-child path in the trap), and
  # (b) wait IS interruptible by signals (bash fires traps between commands during wait).
  printf '_interruptible_sleep() { sleep "$1" & CURRENT_CHILD_PID=$!; wait "$CURRENT_CHILD_PID" 2>/dev/null || true; CURRENT_CHILD_PID=""; }\n' >> "$wrapper"
  printf '_interruptible_sleep 3600\n'                                                   >> "$wrapper"
  chmod +x "$wrapper"

  bash "$wrapper" &
  local sub_pid=$!

  # Wait for the lock dir to appear (up to 3 s, polling every 0.1 s).
  local waited=0
  while [ ! -d "$lock_dir" ] && [ "$waited" -lt 30 ]; do
    sleep 0.1
    waited=$((waited + 1))
  done

  if [ ! -d "$lock_dir" ]; then
    run_test "sigterm_lock_acquired" "lock_dir_present" "lock_dir_absent"
    wait "$sub_pid" 2>/dev/null || true
    rm -f "$wrapper"
    return
  fi
  run_test "sigterm_lock_acquired" "lock_dir_present" "lock_dir_present"

  # Send SIGTERM and wait for the subprocess to exit (up to 3 s).
  kill -TERM "$sub_pid" 2>/dev/null || true
  local kill_waited=0
  while kill -0 "$sub_pid" 2>/dev/null && [ "$kill_waited" -lt 30 ]; do
    sleep 0.1
    kill_waited=$((kill_waited + 1))
  done
  wait "$sub_pid" 2>/dev/null || true

  if [ -d "$lock_dir" ]; then
    run_test "sigterm_lock_cleaned" "lock_dir_absent" "lock_dir_present"
    rm -rf "$lock_dir"
  else
    run_test "sigterm_lock_cleaned" "lock_dir_absent" "lock_dir_absent"
  fi

  rm -f "$wrapper"
}

_run_sigterm_lock_test

# Verify that the INT trap is registered (code inspection — SIGINT cannot be
# tested via kill -INT on a background subprocess because bash resets SIGINT
# to SIG_IGN for background processes per POSIX).
int_trap_present="$(grep -c 'kill -INT.*\$\$' \
  "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh" 2>/dev/null || true)"
if [ "${int_trap_present:-0}" -gt 0 ]; then
  run_test "sigint_trap_registered" "present" "present"
else
  run_test "sigint_trap_registered" "present" "absent"
fi

# ---------------------------------------------------------------------------
# Area 5: auto_reply_unreplied_rest_comments
#
# Tests that the function posts replies to unreplied CodeRabbit REST comments
# and returns the correct count / exit code.
# Uses MOCK_GH_CALL_LOG to verify the POST endpoint is called for each
# unreplied comment, and MOCK_GH_POST_EXIT to simulate API failures.
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 5: auto_reply_unreplied_rest_comments ==="

# Reset POST-related mock vars between tests.
unset MOCK_GH_POST_EXIT MOCK_GH_POST_OUTPUT MOCK_GH_CALL_LOG

# test: no unreplied comments — nothing to reply to, exit 0, count 0
export MOCK_GH_OUTPUT='[]'
actual="$(auto_reply_unreplied_rest_comments "1" "owner/repo" "coderabbitai[bot]" "[]")"
run_test "auto_reply_no_comments" "0" "$actual"

# test: one unreplied bot comment — should post one reply, return count 1
_call_log="$(mktemp)"
export MOCK_GH_CALL_LOG="$_call_log"
export MOCK_GH_OUTPUT='[{"id":10,"in_reply_to_id":null,"user":{"login":"coderabbitai[bot]"},"body":"Finding X"}]'
actual="$(auto_reply_unreplied_rest_comments "1" "owner/repo" "coderabbitai[bot]" "[]")"
run_test "auto_reply_single_comment_count" "1" "$actual"
post_calls="$(grep -c -- '--method POST' "$_call_log" 2>/dev/null || true)"
run_test "auto_reply_single_comment_post_called" "1" "$post_calls"
rm -f "$_call_log"
unset MOCK_GH_CALL_LOG

# test: two unreplied bot comments — should post two replies, return count 2
_call_log="$(mktemp)"
export MOCK_GH_CALL_LOG="$_call_log"
export MOCK_GH_OUTPUT='[
  {"id":10,"in_reply_to_id":null,"user":{"login":"coderabbitai[bot]"},"body":"Finding A"},
  {"id":11,"in_reply_to_id":null,"user":{"login":"coderabbitai[bot]"},"body":"Finding B"}
]'
actual="$(auto_reply_unreplied_rest_comments "1" "owner/repo" "coderabbitai[bot]" "[]")"
run_test "auto_reply_two_comments_count" "2" "$actual"
post_calls="$(grep -c -- '--method POST' "$_call_log" 2>/dev/null || true)"
run_test "auto_reply_two_comments_posts" "2" "$post_calls"
rm -f "$_call_log"
unset MOCK_GH_CALL_LOG

# test: unreplied comment already in resolved_ids — should be skipped, count 0
export MOCK_GH_OUTPUT='[{"id":10,"in_reply_to_id":null,"user":{"login":"coderabbitai[bot]"},"body":"Finding X"}]'
actual="$(auto_reply_unreplied_rest_comments "1" "owner/repo" "coderabbitai[bot]" "[10]")"
run_test "auto_reply_resolved_id_skipped" "0" "$actual"

# test: comment already replied to by a human — should be skipped, count 0
export MOCK_GH_OUTPUT='[
  {"id":10,"in_reply_to_id":null,"user":{"login":"coderabbitai[bot]"},"body":"Finding X"},
  {"id":11,"in_reply_to_id":10,"user":{"login":"humanuser"},"body":"Ack"}
]'
actual="$(auto_reply_unreplied_rest_comments "1" "owner/repo" "coderabbitai[bot]" "[]")"
run_test "auto_reply_already_replied_skipped" "0" "$actual"

# test: POST API failure — function should return exit code 1
export MOCK_GH_OUTPUT='[{"id":10,"in_reply_to_id":null,"user":{"login":"coderabbitai[bot]"},"body":"Finding X"}]'
export MOCK_GH_POST_EXIT=1
actual_exit=0
auto_reply_unreplied_rest_comments "1" "owner/repo" "coderabbitai[bot]" "[]" > /dev/null 2>&1 || actual_exit=$?
run_test "auto_reply_post_failure_exit_code" "1" "$actual_exit"
unset MOCK_GH_POST_EXIT

# ---------------------------------------------------------------------------
# Area 6: check_unresolved_threads
#
# Tests that the function counts unresolved bot-authored review threads correctly
# via the GraphQL API mock. The mock gh command returns MOCK_GH_OUTPUT for all
# non-POST calls. check_unresolved_threads calls `gh api graphql ... --jq ...`
# which outputs the filtered JSON directly (not the raw gh output). Because the
# mock gh does not run the --jq filter, we set MOCK_GH_OUTPUT to the pre-filtered
# JSON that the real GraphQL query would return after --jq (the --jq filter is
# `.data.repository.pullRequest`, so MOCK_GH_OUTPUT must be an object with a
# top-level "reviewThreads" key — and, for provisional-mode cases, a top-level
# "commits" key holding the PR head commit's committedDate).
#
# Important: GitHub's GraphQL API returns author.login WITHOUT the "[bot]" suffix
# (e.g. "coderabbitai", not "coderabbitai[bot]"). The aggregate gate strips the
# "[bot]" suffix from bot_login_for_platform() output before adding to
# unresolved_bot_logins, so check_unresolved_threads always receives login strings
# without the "[bot]" suffix. All test cases below use sanitized login strings.
#
# check_unresolved_threads takes a required "mode" argument ("strict" or
# "provisional") as its third positional parameter, before the bot_logins
# varargs. Every call below passes it explicitly.
#
# Note: the post-clean recheck logic (POST_CLEAN_RECHECK / LATE_THREADS_FOUND)
# lives in the main execution block which is skipped by HARNESS_MODE=1. Those
# code paths call check_unresolved_threads (tested here) and _interruptible_sleep
# (a trivial sleep wrapper). Their integration is validated by the reviewer loop
# end-to-end run in CI.
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 6: check_unresolved_threads ==="

unset MOCK_GH_POST_EXIT MOCK_GH_POST_OUTPUT MOCK_GH_CALL_LOG

# test: no review threads — count should be 0
export MOCK_GH_OUTPUT='{"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}}'
actual="$(check_unresolved_threads "1" "owner/repo" strict "coderabbitai")"
run_test "unresolved_threads_none" "0" "$actual"

# test: one unresolved bot thread — count should be 1
# GraphQL author.login is "coderabbitai" (no "[bot]" suffix — stripped by caller)
export MOCK_GH_OUTPUT='{"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"id":"RT1","isResolved":false,"firstComment":{"nodes":[{"author":{"login":"coderabbitai"},"body":"Blocking issue"}]}}]}}'
actual="$(check_unresolved_threads "1" "owner/repo" strict "coderabbitai")"
run_test "unresolved_threads_one_bot" "1" "$actual"

# test: one resolved bot thread — count should be 0
export MOCK_GH_OUTPUT='{"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"id":"RT1","isResolved":true,"firstComment":{"nodes":[{"author":{"login":"coderabbitai"},"body":"Blocking issue"}]}}]}}'
actual="$(check_unresolved_threads "1" "owner/repo" strict "coderabbitai")"
run_test "unresolved_threads_resolved_skipped" "0" "$actual"

# test: bot thread with "✅ Addressed" in body — count should be 0
export MOCK_GH_OUTPUT='{"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"id":"RT1","isResolved":false,"firstComment":{"nodes":[{"author":{"login":"coderabbitai"},"body":"✅ Addressed — fixed in latest commit"}]}}]}}'
actual="$(check_unresolved_threads "1" "owner/repo" strict "coderabbitai")"
run_test "unresolved_threads_addressed_body_skipped" "0" "$actual"

# test: human-authored thread unresolved — count should be 0 (bot-only filter)
export MOCK_GH_OUTPUT='{"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"id":"RT1","isResolved":false,"firstComment":{"nodes":[{"author":{"login":"humanreview"},"body":"Please change this"}]}}]}}'
actual="$(check_unresolved_threads "1" "owner/repo" strict "coderabbitai")"
run_test "unresolved_threads_human_ignored" "0" "$actual"

# test: two bot threads, one resolved, one not — count should be 1
export MOCK_GH_OUTPUT='{"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"id":"RT1","isResolved":true,"firstComment":{"nodes":[{"author":{"login":"coderabbitai"},"body":"First finding"}]}},{"id":"RT2","isResolved":false,"firstComment":{"nodes":[{"author":{"login":"coderabbitai"},"body":"Second finding"}]}}]}}'
actual="$(check_unresolved_threads "1" "owner/repo" strict "coderabbitai")"
run_test "unresolved_threads_mixed_resolved" "1" "$actual"

# test: [bot]-suffix login NOT matched (gate strips suffix; bare login is required)
# Passing "coderabbitai[bot]" should NOT match GraphQL "coderabbitai" — returns 0.
export MOCK_GH_OUTPUT='{"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"id":"RT1","isResolved":false,"firstComment":{"nodes":[{"author":{"login":"coderabbitai"},"body":"Blocking issue"}]}}]}}'
actual="$(check_unresolved_threads "1" "owner/repo" strict "coderabbitai[bot]")"
run_test "unresolved_threads_bot_suffix_no_match" "0" "$actual"

# test: GraphQL API failure (exit 1 from gh) — function should return exit 3
export MOCK_GH_EXIT=1
actual_exit=0
check_unresolved_threads "1" "owner/repo" strict "coderabbitai" > /dev/null 2>&1 || actual_exit=$?
run_test "unresolved_threads_graphql_failure_exit3" "3" "$actual_exit"
unset MOCK_GH_EXIT

# test: unrecognized mode value fails safe to strict — a reply-after-head-commit
# must NOT be treated as provisionally addressed when mode is misspelled/garbage.
export MOCK_GH_OUTPUT='{"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"id":"RT1","isResolved":false,"firstComment":{"nodes":[{"author":{"login":"chatgpt-codex-connector"},"body":"Blocking issue"}]},"lastComment":{"nodes":[{"author":{"login":"humanreview"},"body":"fixed","createdAt":"2026-08-21T02:00:00Z"}]}}]},"commits":{"nodes":[{"commit":{"committedDate":"2026-08-21T01:00:00Z"}}]}}'
actual="$(check_unresolved_threads "1" "owner/repo" bogus-mode "chatgpt-codex-connector")"
run_test "unresolved_threads_unrecognized_mode_fails_safe_to_strict" "1" "$actual"

# ---------------------------------------------------------------------------
# Area 6b: check_unresolved_threads mode=provisional (#1508)
#
# A replied-but-unresolved thread must not block phase-1 gates (run_codex_
# github_review, run_claude_code_action_review) from re-triggering a review
# when the reply came from a non-bot author AFTER the current PR head commit
# — this is the "fixer pushed and replied but has not yet called
# resolveReviewThread" state described in issue #1508. Every other caller
# (the aggregate clean gate, coderabbit_thread_gate_clean, the post-trigger
# findings recount, and the post-clean recheck) keeps using mode=strict, so
# these provisional-mode semantics can only ever make check_unresolved_threads
# return a SMALLER count than strict mode for the same input — never used by
# anything that decides RESULT=clean. Confirmed at the call-site level in the
# "call-site mode audit" test below.
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 6b: check_unresolved_threads mode=provisional (#1508) ==="

# Direction 1 (the reported bug): a thread replied to by a human AFTER the
# head commit was pushed must NOT block re-review in provisional mode — count
# should be 0, even though isResolved is still false (no resolveReviewThread
# call was made).
export MOCK_GH_OUTPUT='{"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"id":"RT1","isResolved":false,"firstComment":{"nodes":[{"author":{"login":"chatgpt-codex-connector"},"body":"Blocking issue"}]},"lastComment":{"nodes":[{"author":{"login":"humanreview"},"body":"Fixed in the latest push, see commit abc123","createdAt":"2026-08-21T02:00:00Z"}]}}]},"commits":{"nodes":[{"commit":{"committedDate":"2026-08-21T01:00:00Z"}}]}}'
actual="$(check_unresolved_threads "1" "owner/repo" provisional "chatgpt-codex-connector")"
run_test "unresolved_threads_provisional_reply_after_head_not_blocking" "0" "$actual"

# The SAME fixture under mode=strict must still count as unresolved (1) —
# this is the load-bearing guarantee that provisional mode cannot leak into
# any RESULT=clean decision: strict mode ignores the reply entirely and
# requires true GraphQL resolution.
actual="$(check_unresolved_threads "1" "owner/repo" strict "chatgpt-codex-connector")"
run_test "unresolved_threads_strict_still_blocks_same_replied_thread" "1" "$actual"

# Direction 2 (must not open the false-clean class, #1531/#1437): a reply
# posted BEFORE the head commit (i.e. the fixer pushed AFTER replying, or the
# reply predates the fix entirely) must still count as unresolved even in
# provisional mode — an old reply is not evidence the current HEAD was
# addressed.
export MOCK_GH_OUTPUT='{"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"id":"RT1","isResolved":false,"firstComment":{"nodes":[{"author":{"login":"chatgpt-codex-connector"},"body":"Blocking issue"}]},"lastComment":{"nodes":[{"author":{"login":"humanreview"},"body":"looking into it","createdAt":"2026-08-20T23:00:00Z"}]}}]},"commits":{"nodes":[{"commit":{"committedDate":"2026-08-21T01:00:00Z"}}]}}'
actual="$(check_unresolved_threads "1" "owner/repo" provisional "chatgpt-codex-connector")"
run_test "unresolved_threads_provisional_reply_before_head_still_blocks" "1" "$actual"

# Direction 2 (continued): a reply from the bot ITSELF (e.g. a second bot
# comment in the thread) must not count as a "human/agent reply" — still
# unresolved even in provisional mode.
export MOCK_GH_OUTPUT='{"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"id":"RT1","isResolved":false,"firstComment":{"nodes":[{"author":{"login":"chatgpt-codex-connector"},"body":"Blocking issue"}]},"lastComment":{"nodes":[{"author":{"login":"chatgpt-codex-connector"},"body":"still an issue","createdAt":"2026-08-21T02:00:00Z"}]}}]},"commits":{"nodes":[{"commit":{"committedDate":"2026-08-21T01:00:00Z"}}]}}'
actual="$(check_unresolved_threads "1" "owner/repo" provisional "chatgpt-codex-connector")"
run_test "unresolved_threads_provisional_bot_last_comment_still_blocks" "1" "$actual"

# Direction 2 (continued): with no lastComment data at all (e.g. thread has
# exactly one comment — the bot's own finding, never replied to), provisional
# mode must behave exactly like strict — still unresolved.
export MOCK_GH_OUTPUT='{"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"id":"RT1","isResolved":false,"firstComment":{"nodes":[{"author":{"login":"chatgpt-codex-connector"},"body":"Blocking issue"}]}}]},"commits":{"nodes":[{"commit":{"committedDate":"2026-08-21T01:00:00Z"}}]}}'
actual="$(check_unresolved_threads "1" "owner/repo" provisional "chatgpt-codex-connector")"
run_test "unresolved_threads_provisional_no_reply_still_blocks" "1" "$actual"

# Sanity: true resolution (isResolved=true) still counts as resolved under
# provisional mode exactly as under strict — provisional mode only ADDS a
# relaxation, it never removes the existing strict checks.
export MOCK_GH_OUTPUT='{"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"id":"RT1","isResolved":true,"firstComment":{"nodes":[{"author":{"login":"chatgpt-codex-connector"},"body":"Blocking issue"}]}}]},"commits":{"nodes":[{"commit":{"committedDate":"2026-08-21T01:00:00Z"}}]}}'
actual="$(check_unresolved_threads "1" "owner/repo" provisional "chatgpt-codex-connector")"
run_test "unresolved_threads_provisional_true_resolution_still_clean" "0" "$actual"
unset MOCK_GH_OUTPUT

# ---------------------------------------------------------------------------
# Area 7: bot_login_for_platform — copilot platform
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 7: bot_login_for_platform — copilot ==="

unset COPILOT_BOT_LOGIN

actual="$(bot_login_for_platform "copilot")"
run_test "copilot_bot_login_default" "copilot-pull-request-reviewer[bot]" "$actual"

export COPILOT_BOT_LOGIN="custom-copilot-bot[bot]"
actual="$(bot_login_for_platform "copilot")"
run_test "copilot_bot_login_env_override" "custom-copilot-bot[bot]" "$actual"
unset COPILOT_BOT_LOGIN

# ---------------------------------------------------------------------------
# Area 8: run_copilot_review() — exit-code and key-value output contract (AC-8)
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 8: run_copilot_review — clean / needs_fixes / escalate ==="

# Helper overrides used across all Area 8 tests.
# cd_workflow_repo_root: no-op (no real directory change needed in harness).
# repo_slug: returns a fixed owner/repo slug so gh URL is deterministic.
# require_gh: no-op (mock gh already present on PATH).
_copilot_overrides='
  cd_workflow_repo_root() { :; }
  repo_slug() { printf "owner/repo\n"; }
  require_gh() { :; }
'

# Test 8.1: clean path — Copilot posts APPROVED review
# POST (reviewer request) succeeds; GET (reviews poll) returns a JSON array of
# review objects. run_copilot_review pipes gh output through jq, so MOCK_GH_OUTPUT
# must be a valid JSON array. MOCK_GH_HEAD_SHA is set so the SHA-filtered path is
# exercised and commit_id in the review matches.
# Use || to capture exit code safely when run_copilot_review may call set -e internally.
export MOCK_GH_POST_OUTPUT='{}'
export MOCK_GH_HEAD_SHA='abc123sha'
export MOCK_GH_OUTPUT='[{"user":{"login":"copilot-pull-request-reviewer[bot]"},"state":"APPROVED","commit_id":"abc123sha"}]'
unset COPILOT_BOT_LOGIN
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_copilot_overrides"
  _ec=0
  run_copilot_review "42" "feature/42-test" "1" "5" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "copilot_clean_result" "RESULT=clean" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "copilot_clean_blocking_count" "BLOCKING_COUNT=0" \
  "$(printf '%s\n' "$actual_output" | grep "^BLOCKING_COUNT=")"
run_test "copilot_clean_exit_code" "0" "$actual_exit"

# Test 8.2: needs_fixes path — Copilot posts CHANGES_REQUESTED review.
# The mock review includes an id (456) so the review-comments API call is
# exercised. The mock gh returns the same MOCK_GH_OUTPUT for all GET calls,
# so the review-comments endpoint returns one element (the review object) —
# length=1. BLOCKING_COUNT should equal 1 (the actual inline count).
export MOCK_GH_POST_OUTPUT='{}'
export MOCK_GH_HEAD_SHA='abc123sha'
export MOCK_GH_OUTPUT='[{"id":456,"user":{"login":"copilot-pull-request-reviewer[bot]"},"state":"CHANGES_REQUESTED","commit_id":"abc123sha"}]'
unset COPILOT_BOT_LOGIN
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_copilot_overrides"
  _ec=0
  run_copilot_review "42" "feature/42-test" "1" "5" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "copilot_needs_fixes_result" "RESULT=needs_fixes" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "copilot_needs_fixes_blocking_count" "BLOCKING_COUNT=1" \
  "$(printf '%s\n' "$actual_output" | grep "^BLOCKING_COUNT=")"
run_test "copilot_needs_fixes_exit_code" "1" "$actual_exit"

# Test 8.3: No verdict yet path — no review posted within max_wait
# POST succeeds; GET returns empty array (no reviews yet); max_wait=0 so the
# while loop body never executes and execution falls through to the expiry block.
# MOCK_GH_HEAD_SHA is set so the SHA check passes and the expiry block is reached.
# #1789 (plan D8 Copilot row): an expired wait is No verdict yet
# (waiting_on_reviewer / reviewer-no-verdict-yet, exit 4), not escalate/timeout.
export MOCK_GH_POST_OUTPUT='{}'
export MOCK_GH_HEAD_SHA='abc123sha'
export MOCK_GH_OUTPUT='[]'
unset COPILOT_BOT_LOGIN
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_copilot_overrides"
  _ec=0
  run_copilot_review "42" "feature/42-test" "1" "0" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "copilot_timeout_result" "RESULT=waiting_on_reviewer" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "copilot_timeout_reason" "REASON=reviewer-no-verdict-yet" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"
run_test "copilot_timeout_detail" "WAIT_EXPIRED_DETAIL=review_not_submitted" \
  "$(printf '%s\n' "$actual_output" | grep "^WAIT_EXPIRED_DETAIL=")"
run_test "copilot_timeout_pending_head" "PENDING_REVIEW_HEAD_SHA=abc123sha" \
  "$(printf '%s\n' "$actual_output" | grep "^PENDING_REVIEW_HEAD_SHA=")"
run_test "copilot_timeout_exit_code" "4" "$actual_exit"

# Test 8.4: escalate (unavailable) path — reviewer request API call fails
# POST fails (non-zero exit); function must return RESULT=escalate REASON=unavailable.
# MOCK_GH_HEAD_SHA is set so the SHA check passes and the POST failure path is reached.
export MOCK_GH_POST_EXIT=1
export MOCK_GH_HEAD_SHA='abc123sha'
export MOCK_GH_OUTPUT=''
unset COPILOT_BOT_LOGIN
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_copilot_overrides"
  _ec=0
  run_copilot_review "42" "feature/42-test" "1" "5" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "copilot_unavailable_result" "RESULT=escalate" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "copilot_unavailable_reason" "REASON=unavailable" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"
run_test "copilot_unavailable_exit_code" "2" "$actual_exit"
unset MOCK_GH_POST_EXIT
export MOCK_GH_OUTPUT='[]'

# Test 8.5: clean path — Copilot posts COMMENTED review (non-blocking comment)
# COMMENTED is treated as clean (exit 0), BLOCKING_COUNT=0, SUGGESTION_COUNT=1.
export MOCK_GH_POST_OUTPUT='{}'
export MOCK_GH_HEAD_SHA='abc123sha'
export MOCK_GH_OUTPUT='[{"user":{"login":"copilot-pull-request-reviewer[bot]"},"state":"COMMENTED","commit_id":"abc123sha"}]'
unset COPILOT_BOT_LOGIN
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_copilot_overrides"
  _ec=0
  run_copilot_review "42" "feature/42-test" "1" "5" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "copilot_commented_result" "RESULT=clean" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "copilot_commented_blocking_count" "BLOCKING_COUNT=0" \
  "$(printf '%s\n' "$actual_output" | grep "^BLOCKING_COUNT=")"
run_test "copilot_commented_suggestion_count" "SUGGESTION_COUNT=1" \
  "$(printf '%s\n' "$actual_output" | grep "^SUGGESTION_COUNT=")"
run_test "copilot_commented_exit_code" "0" "$actual_exit"
export MOCK_GH_OUTPUT='[]'

# Test 8.6: zero poll interval guard — effective_poll_interval must be floored to 1
# A poll_interval of 0 would cause elapsed to never increment, hanging forever.
# The guard clamps it to 1. Test verifies the function completes (doesn't hang)
# when poll_interval=0, by returning on the first poll with an APPROVED state.
export MOCK_GH_POST_OUTPUT='{}'
export MOCK_GH_HEAD_SHA='abc123sha'
export MOCK_GH_OUTPUT='[{"user":{"login":"copilot-pull-request-reviewer[bot]"},"state":"APPROVED","commit_id":"abc123sha"}]'
unset COPILOT_BOT_LOGIN
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_copilot_overrides"
  _ec=0
  run_copilot_review "42" "feature/42-test" "0" "5" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "copilot_zero_poll_interval_completes" "RESULT=clean" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "copilot_zero_poll_interval_exit_code" "0" "$actual_exit"
export MOCK_GH_OUTPUT='[]'

# Test 8.7: escalate (head-sha-unavailable) path — headRefOid lookup returns empty
# When head_sha is empty the function must escalate immediately rather than
# falling back to an unscoped review query that could match stale verdicts.
unset MOCK_GH_HEAD_SHA
export MOCK_GH_POST_OUTPUT='{}'
unset COPILOT_BOT_LOGIN
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_copilot_overrides"
  _ec=0
  run_copilot_review "42" "feature/42-test" "1" "5" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "copilot_head_sha_unavailable_result" "RESULT=escalate" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "copilot_head_sha_unavailable_reason" "REASON=head-sha-unavailable" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"
run_test "copilot_head_sha_unavailable_exit_code" "2" "$actual_exit"

# ---------------------------------------------------------------------------
# Area 9: haystack platform
#
# Tests that bot_login_for_platform returns "" for haystack (no GitHub review
# threads are posted by the Haystack CLI in this MVP), and that run_platform_review
# routes to run_haystack_review for the haystack platform.
#
# run_haystack_review itself calls haystack-reviewer.sh which requires the
# haystack CLI binary. Full integration is validated by the smoke test runbook
# at docs/testing/workflow/720-haystack-triage-review-platform.smoke-test.md.
# These unit tests cover only the routing and bot-login layers.
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 9: haystack platform ==="

unset MOCK_GH_POST_EXIT MOCK_GH_POST_OUTPUT MOCK_GH_CALL_LOG MOCK_GH_EXIT

# test: bot_login_for_platform returns "" for haystack
actual="$(bot_login_for_platform haystack)"
run_test "bot_login_for_platform_haystack" "" "$actual"

# test: bot_login_for_platform still returns "" for unknown platforms
actual="$(bot_login_for_platform unknown-platform-xyz)"
run_test "bot_login_for_platform_unknown_still_empty" "" "$actual"

# test: run_platform_review routes "haystack" to run_haystack_review
_haystack_dispatch_called=0
run_haystack_review() { _haystack_dispatch_called=1; }
run_platform_review "haystack" "999" "feature/test" "30" "120" >/dev/null 2>&1 || true
run_test "run_platform_review_routes_to_run_haystack_review" "1" "$_haystack_dispatch_called"
unset -f run_haystack_review
unset _haystack_dispatch_called
HARNESS_MODE=1 source "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh"
workflow_repo_root() { printf '%s\n' "${HARNESS_REPO_ROOT:-$REPO_ROOT}"; }

# test: legacy ensure_pr_ready_for_after_clean wrapper converts draft PRs before ready-phase reviewers
_call_log="$(mktemp)"
export MOCK_GH_CALL_LOG="$_call_log"
MOCK_GH_OUTPUT="true"
MOCK_GH_EXIT=0
export MOCK_GH_OUTPUT MOCK_GH_EXIT
ensure_pr_ready_for_after_clean "999" >/dev/null 2>&1
ready_calls="$(grep -c -- 'pr ready 999' "$_call_log" 2>/dev/null || true)"
run_test "after_clean_ready_converts_draft_pr" "1" "$ready_calls"
rm -f "$_call_log"
unset MOCK_GH_CALL_LOG MOCK_GH_OUTPUT MOCK_GH_EXIT ready_calls

# test: ensure_pr_ready_for_after_clean leaves non-draft PRs unchanged
_call_log="$(mktemp)"
export MOCK_GH_CALL_LOG="$_call_log"
MOCK_GH_OUTPUT="false"
MOCK_GH_EXIT=0
export MOCK_GH_OUTPUT MOCK_GH_EXIT
ensure_pr_ready_for_after_clean "999" >/dev/null 2>&1
ready_calls="$(grep -c -- 'pr ready 999' "$_call_log" 2>/dev/null || true)"
run_test "after_clean_ready_skips_non_draft_pr" "0" "$ready_calls"
rm -f "$_call_log"
unset MOCK_GH_CALL_LOG MOCK_GH_OUTPUT MOCK_GH_EXIT ready_calls

# test: ensure_pr_ready_for_after_clean fails closed when draft state cannot be read
MOCK_GH_OUTPUT=""
MOCK_GH_EXIT=1
export MOCK_GH_OUTPUT MOCK_GH_EXIT
set +e
ensure_pr_ready_for_after_clean "999" >/dev/null 2>&1
ready_status=$?
set -e
run_test "after_clean_ready_fails_closed_on_state_error" "2" "$ready_status"
unset MOCK_GH_OUTPUT MOCK_GH_EXIT ready_status

# test: ensure_pr_ready_for_after_clean fails closed when gh pr ready fails
MOCK_GH_OUTPUT="true"
MOCK_GH_EXIT=0
MOCK_GH_READY_EXIT=1
export MOCK_GH_OUTPUT MOCK_GH_EXIT MOCK_GH_READY_EXIT
set +e
ensure_pr_ready_for_after_clean "999" >/dev/null 2>&1
ready_status=$?
set -e
run_test "after_clean_ready_fails_closed_on_ready_error" "2" "$ready_status"
unset MOCK_GH_OUTPUT MOCK_GH_EXIT MOCK_GH_READY_EXIT ready_status

# test: run_haystack_review skips draft PRs before invoking haystack-reviewer.sh
_haystack_draft_overrides='
  cd_workflow_repo_root() { :; }
  repo_slug() { printf "owner/repo\n"; }
  require_gh() { :; }
'
export MOCK_GH_OUTPUT="true"
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_haystack_draft_overrides"
  _ec=0
  run_haystack_review "42" "feature/test" "1" "30" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "haystack_skips_draft_pr_result" "RESULT=skipped" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "haystack_skips_draft_pr_reason" "REASON=pr-is-draft" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"
run_test "haystack_skips_draft_pr_exit_code" "0" "$actual_exit"
unset MOCK_GH_OUTPUT _haystack_draft_overrides actual_output actual_exit

# test: run_haystack_review escalates when draft state cannot be determined
_haystack_draft_overrides='
  cd_workflow_repo_root() { :; }
  repo_slug() { printf "owner/repo\n"; }
  require_gh() { :; }
'
export MOCK_GH_OUTPUT=""
export MOCK_GH_EXIT=1
actual_output="$(
  eval "$_haystack_draft_overrides"
  _ec=0
  run_haystack_review "42" "feature/test" "1" "30" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "haystack_draft_state_unavailable_result" "RESULT=escalate" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "haystack_draft_state_unavailable_reason" "REASON=draft-state-unavailable" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"
run_test "haystack_draft_state_unavailable_exit_code" "2" "$actual_exit"
unset MOCK_GH_OUTPUT MOCK_GH_EXIT _haystack_draft_overrides actual_output actual_exit

# test: run_haystack_review forwards Haystack auth errors from companion script
_haystack_auth_overrides='
  cd_workflow_repo_root() { :; }
  repo_slug() { printf "owner/repo\n"; }
  require_gh() { :; }
'
export MOCK_GH_OUTPUT="false"
_haystack_reviewer_stub="$(mktemp -d)"
mkdir -p "$_haystack_reviewer_stub/scripts/development-workflow"
cat > "$_haystack_reviewer_stub/scripts/development-workflow/haystack-reviewer.sh" <<'HAYSTACK_STUB'
#!/usr/bin/env bash
printf 'RESULT=skipped\nREASON=forbidden\nBLOCKING_COUNT=0\nSUGGESTION_COUNT=0\nCOMMENT_COUNT=0\n'
exit 3
HAYSTACK_STUB
chmod +x "$_haystack_reviewer_stub/scripts/development-workflow/haystack-reviewer.sh"
workflow_repo_root() { printf "%s\n" "$_haystack_reviewer_stub"; }
actual_output="$(
  eval "$_haystack_auth_overrides"
  _ec=0
  run_haystack_review "42" "feature/test" "1" "30" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "haystack_forwards_auth_reason" "REASON=forbidden" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"
run_test "haystack_forwards_auth_exit_code" "0" "$actual_exit"
rm -rf "$_haystack_reviewer_stub"
unset MOCK_GH_OUTPUT _haystack_auth_overrides actual_output actual_exit
workflow_repo_root() { printf '%s\n' "${HARNESS_REPO_ROOT:-$REPO_ROOT}"; }

# test: run_haystack_review forwards the terminal file-limit reason and display
_haystack_file_limit_overrides='
  cd_workflow_repo_root() { :; }
  repo_slug() { printf "owner/repo\n"; }
  require_gh() { :; }
'
export MOCK_GH_OUTPUT="false"
_haystack_reviewer_stub="$(mktemp -d)"
mkdir -p "$_haystack_reviewer_stub/scripts/development-workflow"
cat > "$_haystack_reviewer_stub/scripts/development-workflow/haystack-reviewer.sh" <<'HAYSTACK_STUB'
#!/usr/bin/env bash
printf 'RESULT=skipped\n'
printf 'REASON=analysis_skipped_file_limit\n'
printf 'DISPLAY_RESULT=skipped (analysis file limit)\n'
printf 'BLOCKING_COUNT=0\nSUGGESTION_COUNT=0\nCOMMENT_COUNT=0\n'
exit 3
HAYSTACK_STUB
chmod +x "$_haystack_reviewer_stub/scripts/development-workflow/haystack-reviewer.sh"
workflow_repo_root() { printf "%s\n" "$_haystack_reviewer_stub"; }
actual_output="$(
  eval "$_haystack_file_limit_overrides"
  _ec=0
  run_haystack_review "42" "feature/test" "1" "30" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "haystack_file_limit_reason_forwarded" "REASON=analysis_skipped_file_limit" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"
run_test "haystack_file_limit_display_forwarded" "DISPLAY_RESULT=skipped (analysis file limit)" \
  "$(printf '%s\n' "$actual_output" | grep "^DISPLAY_RESULT=")"
run_test "haystack_file_limit_maps_to_healthy_skip" "RESULT=skipped" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "haystack_file_limit_mapping_exit_code" "0" "$actual_exit"
rm -rf "$_haystack_reviewer_stub"
unset MOCK_GH_OUTPUT _haystack_file_limit_overrides actual_output actual_exit
workflow_repo_root() { printf '%s\n' "${HARNESS_REPO_ROOT:-$REPO_ROOT}"; }

# ---------------------------------------------------------------------------
# Area 1710: local-ai-reviewer quota escalate forwarding
# ---------------------------------------------------------------------------
#
# When the companion emits REASON=quota_exhausted with optional QUOTA_RESET_AT,
# run_local_ai_reviewer_review must forward both on exit 2 so loop consumers
# see the reset hint (not only the remapped REASON).
echo ""
echo "=== Area 1710: local-ai quota escalate forwarding ==="

_local_ai_quota_overrides='
  require_gh() { :; }
  repo_slug() { printf "owner/repo\n"; }
  reviewer_for_branch() { printf "developer\n"; }
'
_local_ai_reviewer_stub="$(mktemp -d)"
mkdir -p "$_local_ai_reviewer_stub/scripts/development-workflow"
cat > "$_local_ai_reviewer_stub/scripts/development-workflow/local-ai-reviewer.sh" <<'LOCAL_AI_STUB'
#!/usr/bin/env bash
printf 'RESULT=escalate\n'
printf 'REASON=quota_exhausted\n'
printf 'QUOTA_RESET_AT=Sep 7th, 2026 1:17 PM\n'
printf 'BLOCKING_COUNT=0\nSUGGESTION_COUNT=0\nCOMMENT_COUNT=0\n'
printf 'REVIEWED_HEAD=abc123\n'
printf 'GRAPH_CONTEXT=none\n'
exit 2
LOCAL_AI_STUB
chmod +x "$_local_ai_reviewer_stub/scripts/development-workflow/local-ai-reviewer.sh"
_local_ai_prev_repo_root="${repo_root:-}"
repo_root="$_local_ai_reviewer_stub"
workflow_repo_root() { printf "%s\n" "$_local_ai_reviewer_stub"; }
actual_output="$(
  eval "$_local_ai_quota_overrides"
  _ec=0
  run_local_ai_reviewer_review "42" "fix/1710-quota-exhausted-reason" "1" "30" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "local_ai_quota_exhausted_reason_forwarded" "REASON=quota_exhausted" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"
run_test "local_ai_quota_reset_at_forwarded" "QUOTA_RESET_AT=Sep 7th, 2026 1:17 PM" \
  "$(printf '%s\n' "$actual_output" | grep "^QUOTA_RESET_AT=")"
run_test "local_ai_quota_exhausted_maps_to_escalate" "RESULT=escalate" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "local_ai_quota_exhausted_exit_code" "2" "$actual_exit"
rm -rf "$_local_ai_reviewer_stub"
repo_root="$_local_ai_prev_repo_root"
unset _local_ai_quota_overrides _local_ai_reviewer_stub _local_ai_prev_repo_root actual_output actual_exit
workflow_repo_root() { printf '%s\n' "${HARNESS_REPO_ROOT:-$REPO_ROOT}"; }

# ---------------------------------------------------------------------------
# Area 10: per-platform result tokens in summary comment (#755)
#
# Tests that:
#   (a) _summary_platform_list is built correctly from platform_result_tokens.
#   (b) _post_review_summary renders the correct result_line for result="skipped".
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 10: per-platform result tokens in summary comment ==="

# Test 10.1: _summary_platform_list format from platform_result_tokens
_test_tokens=("pr-agent:clean" "haystack:unavailable" "claude-code-action:escalated (timeout)")
_test_spl=""
for _sprt in "${_test_tokens[@]:-}"; do
  _spname="${_sprt%%:*}"; _spdisp="${_sprt#*:}"
  [ -n "$_test_spl" ] && _test_spl="${_test_spl}, "
  _test_spl="${_test_spl}${_spname} (${_spdisp})"
done
[ -z "$_test_spl" ] && _test_spl="none"
run_test "summary_platform_list_format" \
  "pr-agent (clean), haystack (unavailable), claude-code-action (escalated (timeout))" \
  "$_test_spl"
unset _test_tokens _test_spl _sprt _spname _spdisp

# Test 10.1b: display override allows Haystack policy verdicts to avoid reading as clean
_platform_output='RESULT=clean
DISPLAY_RESULT=needs-review: policy
POLICY_REVIEW_REQUIRED=1'
_prt_display_override="$(kv_value_default DISPLAY_RESULT "$_platform_output" "")"
if [ -n "$_prt_display_override" ]; then
  _prt_disp="$_prt_display_override"
else
  _prt_disp="clean"
fi
run_test "summary_platform_display_override" "needs-review: policy" "$_prt_disp"
run_test "policy_review_compare_verdict" "advisory" "$(normalize_platform_verdict clean "$_platform_output")"
run_test "policy_review_does_not_override_needs_fixes" "blocking" "$(normalize_platform_verdict needs_fixes "$_platform_output")"
run_test "policy_review_does_not_override_skipped" "unavailable" "$(normalize_platform_verdict skipped "$_platform_output")"
unset _platform_output _prt_display_override _prt_disp

_platform_output='RESULT=skipped
REASON=analysis_skipped_file_limit
DISPLAY_RESULT=skipped (analysis file limit)'
_prt_display_override="$(kv_value_default DISPLAY_RESULT "$_platform_output" "")"
run_test "summary_file_limit_display_override" "skipped (analysis file limit)" "$_prt_display_override"
run_test "file_limit_skip_compare_verdict" "unavailable" "$(normalize_platform_verdict skipped "$_platform_output")"
unset _platform_output _prt_display_override

# Test 10.1c: policy metadata is rendered as an explicit handoff note.
_platform_name="haystack"
_platform_output='RESULT=clean
POLICY_STATUS_AVAILABLE=1
POLICY_BUCKET=needs-assignment
POLICY_NEEDS_HUMAN=true
POLICY_DISPOSITION=policy-human-review
POLICY_VERDICT=needs-review
POLICY_ANALYSIS_STATUS=ready
POLICY_RATING=5
POLICY_HAS_REVIEWER=false'
_policy_note="${_platform_name}:"
_policy_bucket="$(kv_value_default POLICY_BUCKET "$_platform_output" "")"
_policy_needs_human="$(kv_value_default POLICY_NEEDS_HUMAN "$_platform_output" "")"
_policy_disposition="$(kv_value_default POLICY_DISPOSITION "$_platform_output" "")"
_policy_verdict="$(kv_value_default POLICY_VERDICT "$_platform_output" "")"
_policy_analysis_status="$(kv_value_default POLICY_ANALYSIS_STATUS "$_platform_output" "")"
_policy_rating="$(kv_value_default POLICY_RATING "$_platform_output" "")"
_policy_has_reviewer="$(kv_value_default POLICY_HAS_REVIEWER "$_platform_output" "")"
[ -n "$_policy_bucket" ] && _policy_note="${_policy_note} bucket=${_policy_bucket};"
[ -n "$_policy_needs_human" ] && _policy_note="${_policy_note} needsHumanReview=${_policy_needs_human};"
[ -n "$_policy_disposition" ] && _policy_note="${_policy_note} disposition=${_policy_disposition};"
[ -n "$_policy_verdict" ] && _policy_note="${_policy_note} verdict=${_policy_verdict};"
[ -n "$_policy_analysis_status" ] && _policy_note="${_policy_note} analysisStatus=${_policy_analysis_status};"
[ -n "$_policy_rating" ] && _policy_note="${_policy_note} rating=${_policy_rating};"
[ -n "$_policy_has_reviewer" ] && _policy_note="${_policy_note} hasReviewer=${_policy_has_reviewer};"
run_test "summary_policy_status_note" \
  "haystack: bucket=needs-assignment; needsHumanReview=true; disposition=policy-human-review; verdict=needs-review; analysisStatus=ready; rating=5; hasReviewer=false;" \
  "$_policy_note"
unset _platform_name _platform_output _policy_note _policy_bucket
unset _policy_needs_human _policy_disposition _policy_verdict
unset _policy_analysis_status _policy_rating _policy_has_reviewer

# Test 10.2: _summary_platform_list is "none" when token list is empty
_test_tokens=()
_test_spl=""
if [ "${#_test_tokens[@]}" -gt 0 ]; then
  for _sprt in "${_test_tokens[@]}"; do
    _spname="${_sprt%%:*}"; _spdisp="${_sprt#*:}"
    [ -n "$_test_spl" ] && _test_spl="${_test_spl}, "
    _test_spl="${_test_spl}${_spname} (${_spdisp})"
  done
fi
[ -z "$_test_spl" ] && _test_spl="none"
run_test "summary_platform_list_empty_tokens" "none" "$_test_spl"
unset _test_tokens _test_spl _sprt _spname _spdisp

# Test 10.3: _post_review_summary source contains the skipped result_line constant.
# _post_review_summary is defined after the HARNESS_MODE return point and cannot
# be called directly from the test harness; verify the string constant in the source
# so any accidental change to the wording is caught.
if grep -qF 'result_line="skipped — no GitHub reviewers configured in review.on_draft.github or review.on_ready.github"' \
    "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh" 2>/dev/null; then
  _skipped_constant_count=1
else
  _skipped_constant_count=0
fi
run_test "summary_result_line_skipped" "1" "$_skipped_constant_count"
unset _skipped_constant_count

# Test 10.4: _post_review_summary source renders needs_fixes as active findings.
if grep -qF 'result_line="${blocking} blocking finding(s) require fixes"' \
    "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh" \
    && grep -qF 'needs_fixes)' \
      "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh"; then
  _needs_fixes_summary_count=1
else
  _needs_fixes_summary_count=0
fi
run_test "summary_needs_fixes_active_findings" "1" "$_needs_fixes_summary_count"
unset _needs_fixes_summary_count

# Test 10.5: the summary is posted (via _post_review_summary) before the
# needs_fixes exit branch runs, and that branch simply selects exit 1.
#
# UPDATED for #1502's dual-cap single-RESULT-line fix: _post_review_summary
# now runs ONCE, before the whole `case "$aggregate_result" in` statement
# (so a persistence failure can correct aggregate_result to escalate BEFORE
# RESULT= is ever printed — see the "Single-RESULT-line fix" tests below
# for why). The needs_fixes branch itself no longer calls
# _post_review_summary directly; it only exits 1 for whatever
# aggregate_result settled to after that shared persistence step.
_post_summary_precedes_case="$(awk '
  /_post_review_summary "\$aggregate_result" "\$aggregate_reason"/ {found_call=1}
  /^case "\$aggregate_result" in/ {print (found_call == 1) ? "yes" : "no"; exit}
' "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh")"
run_test "main_needs_fixes_summary_posted_before_case_statement" "yes" "$_post_summary_precedes_case"
_needs_fixes_case_block="$(awk '
  /^  needs_fixes\)/ {capture=1}
  capture {print}
  capture && /^    ;;/ {exit}
' "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh")"
if grep -qF 'exit 1' <<<"$_needs_fixes_case_block" \
    && ! grep -qF '_post_review_summary' <<<"$_needs_fixes_case_block"; then
  _needs_fixes_main_summary_count=1
else
  _needs_fixes_main_summary_count=0
fi
run_test "main_needs_fixes_exit_posts_summary" "1" "$_needs_fixes_main_summary_count"
unset _post_summary_precedes_case _needs_fixes_case_block _needs_fixes_main_summary_count

# Test 10.6: _post_review_summary source renders policy acknowledgement details.
if grep -qF '**Policy acknowledgements:**' \
    "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh" \
    && grep -qF 'platform_policy_status_notes' \
      "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh"; then
  _policy_status_summary_count=1
else
  _policy_status_summary_count=0
fi
run_test "summary_policy_acknowledgements_section" "1" "$_policy_status_summary_count"
unset _policy_status_summary_count

# Test 10.7: blocking, platform advisory, and project advisory findings remain
# visible in the summary in the required order.
_post_summary_source="$(awk '/^_post_review_summary\(\)/,/^}$/' \
  "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh")"
eval "$_post_summary_source"
# shellcheck disable=SC2329 # Invoked indirectly by the eval-loaded function.
repo_slug() { printf "owner/repo\n"; }
# shellcheck disable=SC2034 # Read by the eval-loaded _post_review_summary function.
compare_mode=1
# shellcheck disable=SC2034 # Read by the eval-loaded _post_review_summary function.
compare_verdicts=("coderabbit" "clean")
# shellcheck disable=SC2034 # Read by the eval-loaded _post_review_summary function.
platform_policy_status_notes=()
# shellcheck disable=SC2034 # Read by the eval-loaded _post_review_summary function.
pr_number=42
# shellcheck disable=SC2034 # Read by the eval-loaded _post_review_summary function.
branch_name="fix/42-summary"
if ! _summary_call_log="$(mktemp)"; then
  echo "ERROR: failed to allocate summary call log temp file" >&2
  exit 1
fi
if [ -z "$_summary_call_log" ]; then
  echo "ERROR: mktemp returned an empty summary call log path" >&2
  exit 1
fi
if ! _summary_body_capture="$(mktemp)"; then
  echo "ERROR: failed to allocate summary body capture temp file" >&2
  exit 1
fi
if [ -z "$_summary_body_capture" ]; then
  echo "ERROR: mktemp returned an empty summary body capture path" >&2
  exit 1
fi
export MOCK_GH_CALL_LOG="$_summary_call_log"
export MOCK_GH_BODY_CAPTURE="$_summary_body_capture"
MOCK_GH_EXIT=0
export MOCK_GH_EXIT
MOCK_GH_COMMENTS_OUTPUT='[]'
export MOCK_GH_COMMENTS_OUTPUT
_project_advisory_section="

**Advisory checks** _(informational - never blocks merge)_
- Project-specific note"
_post_review_summary "needs_fixes" "haystack_blocking_findings" "haystack (needs_fixes)" "1" "1" \
  "Rules violation@@@https://github.com/lhpaul/ai-dev-framework-template/pull/952#issuecomment-1" \
  "" "1" "haystack" "1" "0" "" "0" "$_project_advisory_section"
if [ -n "${_summary_body_capture:-}" ] && grep -q "1 blocking finding(s) require fixes" "$_summary_body_capture" \
    && grep -q "Advisory findings (non-blocking):" "$_summary_body_capture" \
    && grep -q "Rules violation" "$_summary_body_capture" \
    && grep -q "Advisory checks" "$_summary_body_capture" \
    && grep -q "Project-specific note" "$_summary_body_capture"; then
  _summary_advisory_split="yes"
else
  _summary_advisory_split="no"
fi
run_test "summary_advisory_split_visible" "yes" "$_summary_advisory_split"
_phase_line="$(grep -n "Ready reviewer phase" "$_summary_body_capture" | cut -d: -f1 | head -1)"
_compare_line="$(grep -n "Compare mode" "$_summary_body_capture" | cut -d: -f1 | head -1)"
_platform_advisory_line="$(grep -n "Advisory findings" "$_summary_body_capture" | cut -d: -f1 | head -1)"
_project_advisory_line="$(grep -n "Advisory checks" "$_summary_body_capture" | cut -d: -f1 | head -1)"
if [ -n "$_phase_line" ] && [ -n "$_compare_line" ] \
    && [ -n "$_platform_advisory_line" ] && [ -n "$_project_advisory_line" ] \
    && [ "$_phase_line" -lt "$_compare_line" ] \
    && [ "$_compare_line" -lt "$_platform_advisory_line" ] \
    && [ "$_platform_advisory_line" -lt "$_project_advisory_line" ]; then
  _summary_project_advisory_order="yes"
else
  _summary_project_advisory_order="no"
fi
run_test "summary_project_advisory_order" "yes" "$_summary_project_advisory_order"
rm -f "$_summary_call_log"
rm -f "$_summary_body_capture"

if ! _summary_read_failed_body_capture="$(mktemp)"; then
  echo "ERROR: failed to allocate read-failure summary body capture temp file" >&2
  exit 1
fi
if [ -z "$_summary_read_failed_body_capture" ]; then
  echo "ERROR: mktemp returned an empty read-failure summary body capture path" >&2
  exit 1
fi
export MOCK_GH_BODY_CAPTURE="$_summary_read_failed_body_capture"
MOCK_GH_EXIT=0
MOCK_GH_COMMENTS_EXIT=1
MOCK_GH_UPDATED_AT="2026-07-18T00:10:00Z"
export MOCK_GH_EXIT MOCK_GH_COMMENTS_EXIT MOCK_GH_UPDATED_AT
# _post_review_summary now returns non-zero on a read failure too (#1502
# dual-cap follow-up), even when the write succeeds — guard the bare call
# with `|| true` since this test only cares about the rendered body, not
# the return code (covered separately by the read-failure-return tests).
_post_review_summary "clean" "" "bugbot (clean)" "0" "0" || true
if [ -n "${_summary_read_failed_body_capture:-}" ] \
    && grep -q "comment_read_failed" "$_summary_read_failed_body_capture"; then
  _summary_read_failed_history="yes"
else
  _summary_read_failed_history="no"
fi
run_test "summary_comment_read_failure_history_unavailable" "yes" "$_summary_read_failed_history"
rm -f "$_summary_read_failed_body_capture"

# AC / regression (Codex finding on PR #1507: "preserve dispatches across
# unavailable-ledger recovery"): _post_review_summary must return non-zero
# on a READ failure even when the WRITE succeeds (MOCK_GH_EXIT=0 above), not
# only when the write itself fails. A read failure means this cycle's own
# entry may have been silently folded into an "unavailable" stub that never
# gets appended (append_safe=0), even though the stub POST succeeds — the
# write succeeding is not sufficient evidence the cycle is countable.
if ! _summary_read_failed_body_capture_2="$(mktemp)"; then
  echo "ERROR: failed to allocate second read-failure summary body capture temp file" >&2
  exit 1
fi
export MOCK_GH_BODY_CAPTURE="$_summary_read_failed_body_capture_2"
_post_summary_read_failure_exit=0
_post_review_summary "needs_fixes" "haystack_blocking_findings" "haystack (needs_fixes)" "1" "0"   || _post_summary_read_failure_exit=$?
run_test "summary_read_failure_returns_nonzero_even_when_write_succeeds" "1"   "$_post_summary_read_failure_exit"
rm -f "$_summary_read_failed_body_capture_2"
unset _summary_read_failed_body_capture_2 _post_summary_read_failure_exit
unset MOCK_GH_CALL_LOG MOCK_GH_BODY_CAPTURE MOCK_GH_EXIT MOCK_GH_COMMENTS_OUTPUT MOCK_GH_COMMENTS_EXIT MOCK_GH_UPDATED_AT
unset _summary_advisory_split _summary_project_advisory_order _post_summary_source
unset _summary_read_failed_body_capture _summary_read_failed_history
unset _phase_line _compare_line _platform_advisory_line _project_advisory_line
unset -f _post_review_summary
unset compare_mode compare_verdicts platform_policy_status_notes pr_number branch_name

# ---------------------------------------------------------------------------
# Area 10b: reviewer-loop history payload (#1243)
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 10b: reviewer-loop history payload ==="

# shellcheck disable=SC2034  # read by functions sourced from pr-review-loop.sh
pr_number=42
branch_name="fix/42-history"
# shellcheck disable=SC2034 # read via "${unresolved_thread_count:-0}" inside
# reviewer_loop_history_build_entry (pr-review-loop.sh), which ShellCheck
# cannot trace across the dynamic HARNESS_MODE=1 source above.
unresolved_thread_count=0
# shellcheck disable=SC2034 # same as unresolved_thread_count above.
late_thread_count=0
MOCK_GH_HEAD_SHA="abc-history-1"
MOCK_GH_UPDATED_AT="2026-07-18T00:00:00Z"
export MOCK_GH_HEAD_SHA MOCK_GH_UPDATED_AT

_history_payload="$(reviewer_loop_history_payload_from_existing "" \
  "clean" "" "bugbot (clean)" "0" "0" "1" "bugbot" "1" "0" "")"
run_test "history_first_entry_schema" "reviewer_loop_history.v1" \
  "$(printf '%s\n' "$_history_payload" | jq -r '.schema')"
run_test "history_first_entry_count" "1" \
  "$(printf '%s\n' "$_history_payload" | jq '(.entries // []) | length')"
run_test "history_first_entry_zero_retries" "0" \
  "$(printf '%s\n' "$_history_payload" | jq '((.entries // []) | length) - 1')"
run_test "history_first_entry_result" "clean" \
  "$(printf '%s\n' "$_history_payload" | jq -r '.entries[0].result')"

_history_existing_body="$(cat <<EOF_HISTORY
### Automated Reviewer Loop Summary

*Posted automatically by \`pr-review-loop.sh\`.*

<details>
<summary>Reviewer-loop history (1 iteration)</summary>

<!-- reviewer-loop-history:v1 -->
\`\`\`json
$(printf '%s\n' "$_history_payload" | jq '.')
\`\`\`
</details>
EOF_HISTORY
)"
MOCK_GH_HEAD_SHA="abc-history-2"
MOCK_GH_UPDATED_AT="2026-07-18T00:05:00Z"
_history_payload_2="$(reviewer_loop_history_payload_from_existing "$_history_existing_body" \
  "needs_fixes" "unresolved_review_threads" "bugbot (needs_fixes)" "1" "0" "1" "bugbot" "1" "1" "review_threads")"
run_test "history_append_entry_count" "2" \
  "$(printf '%s\n' "$_history_payload_2" | jq '(.entries // []) | length')"
run_test "history_append_second_iteration" "2" \
  "$(printf '%s\n' "$_history_payload_2" | jq '.entries[1].iteration')"
run_test "history_append_preserves_first_result" "clean" \
  "$(printf '%s\n' "$_history_payload_2" | jq -r '.entries[0].result')"
run_test "history_append_records_blocking_count" "1" \
  "$(printf '%s\n' "$_history_payload_2" | jq '.entries[1].blocking_count')"

_history_empty_entries_body=$'### Automated Reviewer Loop Summary\n\n<!-- reviewer-loop-history:v1 -->\n```json\n{\"schema\":\"reviewer_loop_history.v1\",\"history_status\":\"available\",\"entries\":[]}\n```\n'
_history_empty_entries_payload="$(reviewer_loop_history_payload_from_existing "$_history_empty_entries_body" \
  "clean" "" "bugbot (clean)" "0" "0")"
run_test "history_empty_entries_append_count" "1" \
  "$(printf '%s\n' "$_history_empty_entries_payload" | jq '(.entries // []) | length')"

_history_needs_rerun_payload="$(reviewer_loop_history_payload_from_existing "" \
  "needs_rerun" "" "pr-agent (needs_rerun)" "0" "0")"
run_test "history_needs_rerun_result" "needs_rerun" \
  "$(printf '%s\n' "$_history_needs_rerun_payload" | jq -r '.entries[0].result')"

_history_same_sha_body="$(cat <<EOF_HISTORY_SAME_SHA
### Automated Reviewer Loop Summary

<!-- reviewer-loop-history:v1 -->
\`\`\`json
$(printf '%s\n' "$_history_payload" | jq '.')
\`\`\`
EOF_HISTORY_SAME_SHA
)"
MOCK_GH_HEAD_SHA="abc-history-1"
_history_same_sha_payload="$(reviewer_loop_history_payload_from_existing "$_history_same_sha_body" \
  "clean" "transient_retry" "bugbot (clean)" "0" "0")"
run_test "history_same_sha_duplicate_appends" "2" \
  "$(printf '%s\n' "$_history_same_sha_payload" | jq '(.entries // []) | length')"

_history_file_limit_payload="$(reviewer_loop_history_payload_from_existing "" \
  "clean" "" "pr-agent (clean), haystack (skipped (analysis file limit))" "0" "0")"
run_test "history_file_limit_platform_display" "haystack (skipped (analysis file limit))" \
  "$(printf '%s\n' "$_history_file_limit_payload" | jq -r '.entries[0].platforms[] | select(startswith("haystack "))')"
_history_file_limit_body="$(cat <<EOF_HISTORY_FILE_LIMIT
### Automated Reviewer Loop Summary

<!-- reviewer-loop-history:v1 -->
\`\`\`json
$(printf '%s\n' "$_history_file_limit_payload" | jq '.')
\`\`\`
EOF_HISTORY_FILE_LIMIT
)"
_history_file_limit_rerun="$(reviewer_loop_history_payload_from_existing "$_history_file_limit_body" \
  "clean" "" "pr-agent (clean), haystack (skipped (analysis file limit))" "0" "0")"
run_test "history_file_limit_same_head_rerun_appends" "2" \
  "$(printf '%s\n' "$_history_file_limit_rerun" | jq '(.entries // []) | length')"

_history_latest_body="$(cat <<EOF_HISTORY_LATEST
### Automated Reviewer Loop Summary

<!-- reviewer-loop-history:v1 -->
\`\`\`json
{"schema":"reviewer_loop_history.v1","history_status":"available","entries":[{"iteration":1,"result":"old"}]}
\`\`\`

Some adjacent Markdown that must not be consumed.

<!-- reviewer-loop-history:v1 -->
\`\`\`json
{"schema":"reviewer_loop_history.v1","history_status":"available","entries":[{"iteration":1,"result":"latest"}]}
\`\`\`
Trailing summary text.
EOF_HISTORY_LATEST
)"
_history_latest_payload="$(reviewer_loop_history_payload_from_existing "$_history_latest_body" \
  "clean" "" "bugbot (clean)" "0" "0")"
run_test "history_latest_block_preserved" "latest" \
  "$(printf '%s\n' "$_history_latest_payload" | jq -r '.entries[0].result')"
run_test "history_fence_boundary_append_count" "2" \
  "$(printf '%s\n' "$_history_latest_payload" | jq '(.entries // []) | length')"

_history_summary_comments="$(cat <<EOF_HISTORY_COMMENTS
[
  {
    "id": 101,
    "created_at": "2026-07-18T00:00:00Z",
    "body": "### Automated Reviewer Loop Summary\n\n*Posted automatically by \`pr-review-loop.sh\`.*\n\n<!-- reviewer-loop-history:v1 -->\n\`\`\`json\n{\"schema\":\"reviewer_loop_history.v1\",\"history_status\":\"available\",\"entries\":[{\"iteration\":1,\"result\":\"needs_fixes\"}]}\n\`\`\`"
  },
  {
    "id": 102,
    "created_at": "2026-07-18T00:05:00Z",
    "body": "### Automated Reviewer Loop Summary\n\n*Posted automatically by \`pr-review-loop.sh\`.*\n\n<!-- reviewer-loop-history:v1 -->\n\`\`\`json\n{\"schema\":\"reviewer_loop_history.v1\",\"history_status\":\"unavailable\",\"history_unavailable_reason\":\"comment_read_failed\",\"entries\":[]}\n\`\`\`"
  }
]
EOF_HISTORY_COMMENTS
)"
_history_selected_record="$(printf '%s\n' "$_history_summary_comments" | reviewer_loop_history_select_summary_record)"
run_test "history_selector_targets_newest_comment" "102" \
  "$(printf '%s\n' "$_history_selected_record" | jq '.id')"
run_test "history_selector_preserves_available_history" "needs_fixes" \
  "$(printf '%s\n' "$_history_selected_record" | jq -r '.body' | reviewer_loop_history_extract_latest_json | jq -r '.entries[0].result')"

_history_malformed_body=$'### Automated Reviewer Loop Summary\n\n<!-- reviewer-loop-history:v1 -->\n```json\n{ not json\n```\n'
_history_malformed_payload="$(reviewer_loop_history_payload_from_existing "$_history_malformed_body" \
  "clean" "" "bugbot (clean)" "0" "0")"
run_test "history_malformed_unavailable" "unavailable" \
  "$(printf '%s\n' "$_history_malformed_payload" | jq -r '.history_status')"
run_test "history_malformed_reason" "malformed_history" \
  "$(printf '%s\n' "$_history_malformed_payload" | jq -r '.history_unavailable_reason')"

_history_wrong_schema_body=$'### Automated Reviewer Loop Summary\n\n<!-- reviewer-loop-history:v1 -->\n```json\n{\"schema\":\"other.v1\",\"entries\":[]}\n```\n'
_history_wrong_schema_payload="$(reviewer_loop_history_payload_from_existing "$_history_wrong_schema_body" \
  "clean" "" "bugbot (clean)" "0" "0")"
run_test "history_wrong_schema_reason" "unknown_schema" \
  "$(printf '%s\n' "$_history_wrong_schema_payload" | jq -r '.history_unavailable_reason')"

_history_prior_unavailable_body=$'### Automated Reviewer Loop Summary\n\n<!-- reviewer-loop-history:v1 -->\n```json\n{\"schema\":\"reviewer_loop_history.v1\",\"history_status\":\"unavailable\",\"history_unavailable_reason\":\"comment_read_failed\",\"entries\":[]}\n```\n'
_history_prior_unavailable_payload="$(reviewer_loop_history_payload_from_existing "$_history_prior_unavailable_body" \
  "clean" "" "bugbot (clean)" "0" "0")"
run_test "history_prior_unavailable_preserved" "comment_read_failed" \
  "$(printf '%s\n' "$_history_prior_unavailable_payload" | jq -r '.history_unavailable_reason')"

_history_read_failed_body="$(reviewer_loop_history_unavailable_stub_body comment_read_failed)"
_history_read_failed_payload="$(reviewer_loop_history_payload_from_existing "$_history_read_failed_body" \
  "clean" "" "bugbot (clean)" "0" "0")"
run_test "history_read_failure_unavailable" "unavailable" \
  "$(printf '%s\n' "$_history_read_failed_payload" | jq -r '.history_status')"
run_test "history_read_failure_reason" "comment_read_failed" \
  "$(printf '%s\n' "$_history_read_failed_payload" | jq -r '.history_unavailable_reason')"

_history_rendered_section="$(reviewer_loop_history_render_section "$_history_payload_2")"
if printf '%s\n' "$_history_rendered_section" | grep -qF "$REVIEWER_LOOP_HISTORY_MARKER" \
    && printf '%s\n' "$_history_rendered_section" | grep -qF "Reviewer-loop history (2 iterations)"; then
  _history_rendered_ok="yes"
else
  _history_rendered_ok="no"
fi
run_test "history_rendered_section" "yes" "$_history_rendered_ok"

unset _history_payload _history_existing_body _history_payload_2
unset _history_empty_entries_body _history_empty_entries_payload
unset _history_needs_rerun_payload
unset _history_same_sha_body _history_same_sha_payload
unset _history_file_limit_payload _history_file_limit_body _history_file_limit_rerun
unset _history_latest_body _history_latest_payload
unset _history_summary_comments _history_selected_record
unset _history_malformed_body _history_malformed_payload
unset _history_wrong_schema_body _history_wrong_schema_payload
unset _history_prior_unavailable_body _history_prior_unavailable_payload
unset _history_read_failed_body _history_read_failed_payload
unset _history_rendered_section _history_rendered_ok
unset MOCK_GH_HEAD_SHA MOCK_GH_UPDATED_AT
unset pr_number branch_name unresolved_thread_count late_thread_count

# ---------------------------------------------------------------------------
# Area 18: suite ergonomics and execution budget (issue #1562)
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 18: suite ergonomics and execution budget (#1562) ==="

_1562_suite="$REPO_ROOT/scripts/development-workflow/tests/test-pr-review-loop.sh"
_1562_loop="$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh"

# --- AC-1: a single area can be run without the full suite -------------------
_1562_areas="$(env -u TEST_PR_REVIEW_LOOP_SNAPSHOT PATH="$TEST_PR_REVIEW_LOOP_REAL_PATH" bash "$_1562_suite" --list-areas 2>/dev/null)"
run_test "area_filter_list_areas_lists_this_area" "yes" \
  "$(grep -F 'Area 18:' <<< "$_1562_areas" >/dev/null && echo yes || echo no)"

_1562_filtered="$(env -u TEST_PR_REVIEW_LOOP_SNAPSHOT PATH="$TEST_PR_REVIEW_LOOP_REAL_PATH" bash "$_1562_suite" --area 1 2>/dev/null || true)"
run_test "area_filter_runs_selected_area" "yes" \
  "$(printf '%s\n' "$_1562_filtered" | grep -q 'normalize_platform_verdict' && echo yes || echo no)"
# The point of the filter: other areas of the same suite must be absent. Area 0
# lives in this suite, so its absence proves the filter dropped it (Area 13,
# the slow one, now lives in the failure-paths suites — #1876).
run_test "area_filter_excludes_other_areas" "yes" \
  "$(printf '%s\n' "$_1562_filtered" | grep -q 'draft/ready lifecycle config parsing' && echo no || echo yes)"
# The summary footer carries the exit status and must survive every filter.
run_test "area_filter_keeps_summary_footer" "yes" \
  "$(printf '%s\n' "$_1562_filtered" | grep -q '^Tests: ' && echo yes || echo no)"

run_test "area_filter_unknown_area_exits_2" "2" \
  "$(env -u TEST_PR_REVIEW_LOOP_SNAPSHOT PATH="$TEST_PR_REVIEW_LOOP_REAL_PATH" bash "$_1562_suite" --area definitely-not-an-area >/dev/null 2>&1; echo $?)"
run_test "area_filter_missing_value_exits_2" "2" \
  "$(env -u TEST_PR_REVIEW_LOOP_SNAPSHOT PATH="$TEST_PR_REVIEW_LOOP_REAL_PATH" bash "$_1562_suite" --area >/dev/null 2>&1; echo $?)"
run_test "area_filter_unknown_flag_exits_2" "2" \
  "$(env -u TEST_PR_REVIEW_LOOP_SNAPSHOT PATH="$TEST_PR_REVIEW_LOOP_REAL_PATH" bash "$_1562_suite" --not-a-flag >/dev/null 2>&1; echo $?)"
# A bare number selects that area exactly, not every area containing the digit:
# --area 1 must not drag in Area 10 or 10b, which share this suite.
run_test "area_filter_bare_number_is_exact" "yes" \
  "$(printf '%s\n' "$_1562_filtered" | grep -Eq 'per-platform result tokens|reviewer-loop history payload' && echo no || echo yes)"

# --- AC-2: a mid-run edit cannot silently alter the result -------------------
run_test "suite_reexecs_from_snapshot" "yes" \
  "$(grep -q 'TEST_PR_REVIEW_LOOP_SNAPSHOT' "$_1562_suite" && echo yes || echo no)"
run_test "suite_snapshot_preserves_origin_for_repo_root" "yes" \
  "$(grep -q 'TEST_PR_REVIEW_LOOP_ORIGIN' "$_1562_suite" && echo yes || echo no)"
# The snapshot must be what actually runs. This process IS a snapshot run, so
# $0 is the temp copy rather than the checked-in path — which is also what
# makes running the harness from outside the repo work, since repo-root
# resolution follows TEST_PR_REVIEW_LOOP_ORIGIN instead of $0.
run_test "suite_runs_from_a_copy_not_the_original" "yes" \
  "$([ "$0" != "$_1562_suite" ] && echo yes || echo no)"
run_test "suite_origin_points_at_the_checked_in_file" "yes" \
  "$([ "${TEST_PR_REVIEW_LOOP_ORIGIN:-}" = "$_1562_suite" ] && echo yes || echo no)"
run_test "suite_repo_root_resolved_despite_snapshot" "yes" \
  "$([ -d "$REPO_ROOT/scripts/development-workflow" ] && echo yes || echo no)"
# Issue #1562 consequence 3: an out-of-tree copy used to fail with "fatal: not
# a git repository" because the root was resolved from the copy's location.
# A pre-set origin now makes that work.
_1562_copy="$(mktemp -t test-pr-review-loop-copy.XXXXXX)"
cat "$_1562_suite" > "$_1562_copy"
run_test "out_of_tree_copy_resolves_repo_root" "yes" \
  "$(env -u TEST_PR_REVIEW_LOOP_SNAPSHOT PATH="$TEST_PR_REVIEW_LOOP_REAL_PATH" \
      TEST_PR_REVIEW_LOOP_ORIGIN="$_1562_suite" \
      bash "$_1562_copy" --area 1 2>/dev/null | grep -q '^Tests: ' && echo yes || echo no)"
run_test "out_of_tree_copy_bad_origin_exits_2" "2" \
  "$(env -u TEST_PR_REVIEW_LOOP_SNAPSHOT PATH="$TEST_PR_REVIEW_LOOP_REAL_PATH" \
      TEST_PR_REVIEW_LOOP_ORIGIN=/nonexistent/suite.sh \
      bash "$_1562_copy" --area 1 >/dev/null 2>&1; echo $?)"
rm -f "$_1562_copy"
unset _1562_copy

# --- AC-3: a truncated run is never mistaken for a clean one ----------------
run_test "truncation_guard_defined" "yes" \
  "$(type -t _emit_truncation_guard >/dev/null 2>&1 && echo yes || echo no)"

# With no RESULT emitted, the guard supplies a terminal one and forces non-zero.
_RESULT_EMITTED=0
run_test "truncation_guard_forces_nonzero_from_success" "2" \
  "$(_emit_truncation_guard 0 >/dev/null 2>&1; echo $?)"
_RESULT_EMITTED=0
run_test "truncation_guard_emits_result_escalate" "RESULT=escalate" \
  "$(_emit_truncation_guard 0 2>/dev/null | grep '^RESULT=' || true)"
_RESULT_EMITTED=0
run_test "truncation_guard_emits_truncated_reason" "REASON=truncated_run" \
  "$(_emit_truncation_guard 0 2>/dev/null | grep '^REASON=' || true)"
_RESULT_EMITTED=0
run_test "truncation_guard_preserves_kill_status" "143" \
  "$(_emit_truncation_guard 143 >/dev/null 2>&1; echo $?)"

# When a verdict was reached, the guard must not add a second RESULT line.
_RESULT_EMITTED=1
run_test "truncation_guard_silent_after_a_verdict" "" \
  "$(_emit_truncation_guard 0 2>/dev/null | grep '^RESULT=' || true)"
_RESULT_EMITTED=1
run_test "truncation_guard_passes_status_through" "1" \
  "$(_emit_truncation_guard 1 >/dev/null 2>&1; echo $?)"

# print_kv is the choke point that sets the flag, covering all emission sites.
_RESULT_EMITTED=0
print_kv RESULT clean >/dev/null
run_test "print_kv_records_result_emission" "1" "$_RESULT_EMITTED"
_RESULT_EMITTED=0
print_kv REASON something >/dev/null
run_test "print_kv_ignores_non_result_keys" "0" "$_RESULT_EMITTED"
_RESULT_EMITTED=0

# --- AC-4: rate-limit ceiling reconciled with the execution budget ----------
run_test "budget_check_defined" "yes" \
  "$(type -t _check_execution_budget >/dev/null 2>&1 && echo yes || echo no)"

# Shipped defaults must satisfy the invariant: 4 x 900 = 3600 < 5400.
run_test "budget_defaults_satisfy_invariant" "BUDGET_INVARIANT=ok" \
  "$(_check_execution_budget 2>/dev/null | grep '^BUDGET_INVARIANT=' || true)"
run_test "budget_default_worst_case_is_3600" "BUDGET_WORST_CASE_RATE_LIMIT_WAIT_SECONDS=3600" \
  "$(_check_execution_budget 2>/dev/null | grep '^BUDGET_WORST_CASE' || true)"
run_test "budget_default_budget_is_5400" "BUDGET_EXECUTION_SECONDS=5400" \
  "$(_check_execution_budget 2>/dev/null | grep '^BUDGET_EXECUTION_SECONDS=' || true)"
run_test "budget_defaults_exit_zero" "0" \
  "$(_check_execution_budget >/dev/null 2>&1; echo $?)"

# A budget below the worst-case wait is a configuration error, reported before
# any waiting rather than discovered as a truncated run an hour later.
run_test "budget_too_small_is_violation" "BUDGET_INVARIANT=violated" \
  "$(PR_REVIEW_LOOP_EXECUTION_BUDGET=600 _check_execution_budget 2>/dev/null | grep '^BUDGET_INVARIANT=' || true)"
run_test "budget_too_small_exits_nonzero" "1" \
  "$(PR_REVIEW_LOOP_EXECUTION_BUDGET=600 _check_execution_budget >/dev/null 2>&1; echo $?)"
run_test "budget_too_small_escalates" "REASON=execution_budget_misconfigured" \
  "$(PR_REVIEW_LOOP_EXECUTION_BUDGET=600 _check_execution_budget 2>/dev/null | grep '^REASON=' || true)"
# Equality is a violation too: the wait must fit strictly inside the budget.
run_test "budget_equal_to_worst_case_is_violation" "BUDGET_INVARIANT=violated" \
  "$(PR_REVIEW_LOOP_EXECUTION_BUDGET=3600 _check_execution_budget 2>/dev/null | grep '^BUDGET_INVARIANT=' || true)"
# Raising the retries without raising the budget is caught.
run_test "budget_raised_retries_violates" "BUDGET_INVARIANT=violated" \
  "$(CODERABBIT_RATE_LIMIT_MAX_RETRIES=8 _check_execution_budget 2>/dev/null | grep '^BUDGET_INVARIANT=' || true)"
# Lowering the ceiling to match a tighter budget is the supported escape hatch.
run_test "budget_lowered_ceiling_is_ok" "BUDGET_INVARIANT=ok" \
  "$(PR_REVIEW_LOOP_EXECUTION_BUDGET=600 CODERABBIT_RATE_LIMIT_MAX_RETRIES=1 \
     CODERABBIT_RATE_LIMIT_WAIT=300 _check_execution_budget 2>/dev/null | grep '^BUDGET_INVARIANT=' || true)"
# Non-numeric input falls back to the shipped defaults rather than doing
# arithmetic on a string.
run_test "budget_non_numeric_retries_falls_back" "BUDGET_INVARIANT=ok" \
  "$(CODERABBIT_RATE_LIMIT_MAX_RETRIES=abc _check_execution_budget 2>/dev/null | grep '^BUDGET_INVARIANT=' || true)"
run_test "budget_non_numeric_wait_falls_back" "BUDGET_INVARIANT=ok" \
  "$(CODERABBIT_RATE_LIMIT_WAIT=abc _check_execution_budget 2>/dev/null | grep '^BUDGET_INVARIANT=' || true)"
run_test "budget_non_numeric_budget_falls_back" "BUDGET_INVARIANT=ok" \
  "$(PR_REVIEW_LOOP_EXECUTION_BUDGET=abc _check_execution_budget 2>/dev/null | grep '^BUDGET_INVARIANT=' || true)"

# Zero-padded values pass the all-digit guards, and bash reads a leading-zero
# operand inside $(( )) as octal. Before the 10# prefix these crashed the check
# that exists to replace a crash with a clean escalation.
run_test "budget_octal_retries_does_not_crash" "BUDGET_INVARIANT=violated" \
  "$(CODERABBIT_RATE_LIMIT_MAX_RETRIES=08 _check_execution_budget 2>/dev/null | grep '^BUDGET_INVARIANT=' || true)"
run_test "budget_octal_retries_no_arith_error" "" \
  "$(CODERABBIT_RATE_LIMIT_MAX_RETRIES=08 _check_execution_budget 2>&1 >/dev/null | grep 'error token' || true)"
run_test "budget_octal_wait_is_base_10" "BUDGET_WORST_CASE_RATE_LIMIT_WAIT_SECONDS=3600" \
  "$(CODERABBIT_RATE_LIMIT_WAIT=0900 _check_execution_budget 2>/dev/null | grep '^BUDGET_WORST_CASE' || true)"
run_test "budget_octal_budget_is_base_10" "BUDGET_EXECUTION_SECONDS=9000" \
  "$(PR_REVIEW_LOOP_EXECUTION_BUDGET=09000 _check_execution_budget 2>/dev/null | grep '^BUDGET_EXECUTION_SECONDS=' || true)"

# Oversized digit strings wrap 64-bit arithmetic. retries=99999999999999999
# multiplied out NEGATIVE, which compared as under budget and reported the
# invariant satisfied — the check accepting the unsafe configuration it exists
# to reject. Bounds are enforced before any arithmetic now.
run_test "budget_overflow_retries_rejected" "BUDGET_INVARIANT=violated" \
  "$(CODERABBIT_RATE_LIMIT_MAX_RETRIES=99999999999999999 _check_execution_budget 2>/dev/null | grep '^BUDGET_INVARIANT=' || true)"
run_test "budget_overflow_retries_not_negative" "" \
  "$(CODERABBIT_RATE_LIMIT_MAX_RETRIES=99999999999999999 _check_execution_budget 2>/dev/null | grep -- '-[0-9]' || true)"
run_test "budget_overflow_huge_digit_string_rejected" "BUDGET_INVARIANT=violated" \
  "$(CODERABBIT_RATE_LIMIT_MAX_RETRIES=999999999999999999999 _check_execution_budget 2>/dev/null | grep '^BUDGET_INVARIANT=' || true)"
run_test "budget_overflow_wait_rejected" "BUDGET_INVARIANT=violated" \
  "$(CODERABBIT_RATE_LIMIT_WAIT=99999999999999999 _check_execution_budget 2>/dev/null | grep '^BUDGET_INVARIANT=' || true)"
run_test "budget_overflow_budget_rejected" "BUDGET_INVARIANT=violated" \
  "$(PR_REVIEW_LOOP_EXECUTION_BUDGET=99999999999999999 _check_execution_budget 2>/dev/null | grep '^BUDGET_INVARIANT=' || true)"
run_test "budget_overflow_escalates" "REASON=execution_budget_misconfigured" \
  "$(CODERABBIT_RATE_LIMIT_MAX_RETRIES=99999999999999999 _check_execution_budget 2>/dev/null | grep '^REASON=' || true)"
run_test "budget_overflow_exits_nonzero" "1" \
  "$(CODERABBIT_RATE_LIMIT_MAX_RETRIES=99999999999999999 _check_execution_budget >/dev/null 2>&1; echo $?)"
# The bound must not reject values that are merely large but legitimate.
run_test "budget_large_but_valid_is_ok" "BUDGET_INVARIANT=ok" \
  "$(PR_REVIEW_LOOP_EXECUTION_BUDGET=604800 CODERABBIT_RATE_LIMIT_MAX_RETRIES=1000 \
     CODERABBIT_RATE_LIMIT_WAIT=600 _check_execution_budget 2>/dev/null | grep '^BUDGET_INVARIANT=' || true)"

# --area= with no value must not silently degrade to a full run.
run_test "area_filter_empty_equals_value_exits_2" "2" \
  "$(env -u TEST_PR_REVIEW_LOOP_SNAPSHOT PATH="$TEST_PR_REVIEW_LOOP_REAL_PATH" \
      bash "$_1562_suite" --area= >/dev/null 2>&1; echo $?)"
run_test "area_filter_empty_value_exits_2" "2" \
  "$(env -u TEST_PR_REVIEW_LOOP_SNAPSHOT PATH="$TEST_PR_REVIEW_LOOP_REAL_PATH" \
      bash "$_1562_suite" --area "" >/dev/null 2>&1; echo $?)"

unset _1562_suite _1562_loop _1562_filtered _1562_guard_out

# ---------------------------------------------------------------------------
# Area 1876: the harness stays split into small suites (issue #1876)
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 1876: harness split into small suites ==="

# ShellCheck's peak memory grows much faster than a file's line count: the
# single 21.6k-line suite needed ~17 GB and got the smaller runners private
# repositories use shut down mid-lint (7.5 GB at 16k lines). Every
# pr-review-loop suite, and the library they share, must stay under this cap.
# When a suite approaches it, move areas into a new
# test-pr-review-loop-<topic>.sh that sources the shared library — do not
# raise the cap.
_1876_max_lines=4000
_1876_tests_dir="$REPO_ROOT/scripts/development-workflow/tests"
_1876_lib="$_1876_tests_dir/lib/pr-review-loop-harness.sh"
_1876_count=0
_1876_oversized=""
_1876_unshared=""
_1876_uncovered=""
for _1876_suite in "$_1876_tests_dir"/test-pr-review-loop.sh "$_1876_tests_dir"/test-pr-review-loop-*.sh "$_1876_lib"; do
  [ -f "$_1876_suite" ] || continue
  _1876_name="$(basename "$_1876_suite")"
  _1876_lines="$(wc -l < "$_1876_suite" | tr -d ' ')"
  if [ "$_1876_lines" -gt "$_1876_max_lines" ]; then
    _1876_oversized="${_1876_oversized} ${_1876_name}:${_1876_lines}"
  fi
  [ "$_1876_suite" = "$_1876_lib" ] && continue
  _1876_count=$((_1876_count + 1))
  if ! grep -q '^source "\$_prl_harness" "\$@"$' "$_1876_suite"; then
    _1876_unshared="${_1876_unshared} ${_1876_name}"
  fi
  # Each suite must be selected when pr-review-loop.sh or the library changes.
  if ! head -n 60 "$_1876_suite" | grep -q '^# covers: scripts/development-workflow/pr-review-loop.sh$' \
     || ! head -n 60 "$_1876_suite" | grep -q '^# covers: scripts/development-workflow/tests/lib/pr-review-loop-harness.sh$'; then
    _1876_uncovered="${_1876_uncovered} ${_1876_name}"
  fi
done
run_test "1876_harness_is_split_across_suites" "yes" \
  "$([ "$_1876_count" -ge 2 ] && echo yes || echo no)"
run_test "1876_every_suite_under_line_cap" "" "$_1876_oversized"
run_test "1876_every_suite_sources_shared_harness" "" "$_1876_unshared"
run_test "1876_every_suite_covers_loop_and_harness" "" "$_1876_uncovered"

# The library is sourced, never run: running it directly is a usage error.
# Unset the origin as well: this run exported it, and without the guard a
# direct run would follow it and re-run this whole suite recursively.
run_test "1876_harness_refuses_direct_execution" "2" \
  "$(env -u TEST_PR_REVIEW_LOOP_SNAPSHOT -u TEST_PR_REVIEW_LOOP_ORIGIN \
      PATH="$TEST_PR_REVIEW_LOOP_REAL_PATH" bash "$_1876_lib" >/dev/null 2>&1; echo $?)"

# --list-areas and --area act on the calling suite, not on this one. Unset the
# origin too: this run exported it, and it would redirect the nested run here.
_1876_fp2="$_1876_tests_dir/test-pr-review-loop-failure-paths-2.sh"
run_test "1876_list_areas_reads_calling_suite" "yes" \
  "$(env -u TEST_PR_REVIEW_LOOP_SNAPSHOT -u TEST_PR_REVIEW_LOOP_ORIGIN \
      PATH="$TEST_PR_REVIEW_LOOP_REAL_PATH" bash "$_1876_fp2" --list-areas 2>/dev/null | grep -q 'Area 13: .*part 2 of 4' && echo yes || echo no)"
run_test "1876_area_filter_is_per_suite" "2" \
  "$(env -u TEST_PR_REVIEW_LOOP_SNAPSHOT -u TEST_PR_REVIEW_LOOP_ORIGIN \
      PATH="$TEST_PR_REVIEW_LOOP_REAL_PATH" bash "$_1876_fp2" --area 0a >/dev/null 2>&1; echo $?)"

# ShellCheck runs one process per file so its memory is bounded by the largest
# file, and the job is time-boxed.
_1876_sc_workflow="$REPO_ROOT/.github/workflows/shellcheck.yml"
run_test "1876_shellcheck_lints_one_file_per_process" "yes" \
  "$(grep -Eq 'xargs -0 -n 1 -P [0-9]+ shellcheck --severity=warning' "$_1876_sc_workflow" && echo yes || echo no)"
run_test "1876_shellcheck_job_has_timeout" "yes" \
  "$(grep -Eq '^    timeout-minutes: [0-9]+' "$_1876_sc_workflow" && echo yes || echo no)"

unset _1876_max_lines _1876_tests_dir _1876_lib _1876_count _1876_oversized _1876_unshared
unset _1876_uncovered _1876_suite _1876_name _1876_lines _1876_fp2 _1876_sc_workflow

echo "=== Area 1876 complete ==="

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Tests: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
