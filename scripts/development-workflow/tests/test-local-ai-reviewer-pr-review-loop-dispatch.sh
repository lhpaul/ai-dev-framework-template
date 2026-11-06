#!/usr/bin/env bash
# Dispatch tests for the local AI reviewer pr-review-loop platform.
# covers: scripts/development-workflow/tests/lib/review-retry-fixture.sh
# covers: scripts/development-workflow/pr-review-loop.sh
# covers: scripts/development-workflow/local-ai-reviewer.sh
# covers: scripts/development-workflow/local-claude-review-command.sh

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel)"

PASS_COUNT=0
FAIL_COUNT=0

run_test() {
  local name="$1"
  local expected="$2"
  local actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $name - expected '$expected', got '$actual'"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

HARNESS_MODE=1 source "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh"

actual="$(bot_login_for_platform local-ai-reviewer)"
run_test "bot_login_for_platform_local_ai_reviewer_empty" "" "$actual"

# The invariant is that the parser surfaces local-ai-reviewer *first* in the
# repository's own draft list — not that the list equals the template default.
# A consumer that syncs this template legitimately configures a different set
# (MOME drops pr-agent), so asserting the literal template list turned a
# successful sync into a red required check (#1631). Read the live config and
# skip when this repository does not run local-ai-reviewer on draft PRs at all.
shared_config_copy="$(mktemp)"
cp "$REPO_ROOT/.ai-dev-workflow.yaml" "$shared_config_copy"
draft_reviewers="$(workflow_config_review_on_draft_github "$shared_config_copy")"
rm -f "$shared_config_copy"

# Here-strings rather than pipes into `grep -q` / `head`: this script runs
# under `set -euo pipefail`, where the reader closing the pipe early kills the
# writer with SIGPIPE and aborts the suite with 141.
if grep -Fxq -- "local-ai-reviewer" <<< "$draft_reviewers"; then
  read -r actual <<< "$draft_reviewers"
  run_test "default_draft_github_reviewers_start_with_local_ai" "local-ai-reviewer" "$actual"
else
  echo "SKIP: default_draft_github_reviewers_start_with_local_ai - local-ai-reviewer is not a configured on_draft.github reviewer in this repository"
fi

_2061_real_local_adapter="$(declare -f run_local_ai_reviewer_review)"
_local_ai_dispatch_called=0
run_local_ai_reviewer_review() {
  _local_ai_dispatch_called=1
  print_kv RESULT skipped
  print_kv REASON disabled_by_config
  print_kv COMMENT_COUNT 0
  print_kv BLOCKING_COUNT 0
  print_kv SUGGESTION_COUNT 0
}

run_platform_review "local-ai-reviewer" "999" "feature/test" "30" "120" >/dev/null 2>&1 || true
run_test "run_platform_review_routes_to_local_ai_reviewer" "1" "$_local_ai_dispatch_called"

if grep -q 'needs_rerun) print_kv RESULT needs_rerun' "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh"; then
  actual="present"
else
  actual="missing"
fi
run_test "local_ai_reviewer_preserves_needs_rerun_mapping" "present" "$actual"

unset -f run_local_ai_reviewer_review
eval "$_2061_real_local_adapter"
unset _2061_real_local_adapter

# Issue #1648: LOCAL_AI_* stdout contract for dispatch surfaces
_1648_ancestor_sha='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
_1648_live_sha='bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
platforms=(local-ai-reviewer)
platform_reviewed_heads=("local-ai-reviewer:$_1648_ancestor_sha")
loop_head_sha="$_1648_live_sha"
_1648_dispatch_out="$(mktemp)"
reviewer_loop_emit_local_ai_head_evidence_keys > "$_1648_dispatch_out"
run_test "1648_dispatch_stale_local_head_current" "LOCAL_AI_HEAD_CURRENT=0" \
  "$(grep '^LOCAL_AI_HEAD_CURRENT=' "$_1648_dispatch_out")"
run_test "1648_dispatch_stale_local_reviewed_head" "LOCAL_AI_REVIEWED_HEAD=$_1648_ancestor_sha" \
  "$(grep '^LOCAL_AI_REVIEWED_HEAD=' "$_1648_dispatch_out")"

platforms=(pr-agent)
platform_reviewed_heads=()
loop_head_sha="$_1648_live_sha"
reviewer_loop_emit_local_ai_head_evidence_keys > "$_1648_dispatch_out"
run_test "1648_dispatch_not_configured" "LOCAL_AI_CONFIGURED=0" \
  "$(grep '^LOCAL_AI_CONFIGURED=' "$_1648_dispatch_out")"

platforms=(local-ai-reviewer)
platform_reviewed_heads=("local-ai-reviewer:")
loop_head_sha="$_1648_live_sha"
reviewer_loop_emit_local_ai_head_evidence_keys > "$_1648_dispatch_out"
run_test "1648_dispatch_missing_reviewed_head" "LOCAL_AI_HEAD_CURRENT=" \
  "$(grep '^LOCAL_AI_HEAD_CURRENT=' "$_1648_dispatch_out")"
run_test "1648_dispatch_configured_no_head" "LOCAL_AI_CONFIGURED=1" \
  "$(grep '^LOCAL_AI_CONFIGURED=' "$_1648_dispatch_out")"

# shellcheck disable=SC2034  # read by sourced reviewer_loop_emit_local_ai_head_evidence_keys
platforms=(local-ai-reviewer)
# shellcheck disable=SC2034  # read by sourced reviewer_loop_emit_local_ai_head_evidence_keys
platform_reviewed_heads=("local-ai-reviewer:$_1648_live_sha")
# shellcheck disable=SC2034  # read by sourced reviewer_loop_emit_local_ai_head_evidence_keys
loop_head_sha="$_1648_live_sha"
reviewer_loop_emit_local_ai_head_evidence_keys > "$_1648_dispatch_out"
run_test "1648_dispatch_current_head" "LOCAL_AI_HEAD_CURRENT=1" \
  "$(grep '^LOCAL_AI_HEAD_CURRENT=' "$_1648_dispatch_out")"
rm -f "$_1648_dispatch_out"
unset _1648_ancestor_sha _1648_live_sha _1648_dispatch_out platforms platform_reviewed_heads loop_head_sha

# #2061: the real local adapter must forward compact proof metadata. This
# catches accidentally adding the keys to a different review adapter.
_2061_adapter_output="$(
  _2061_root="$(mktemp -d)"
  trap 'rm -rf "$_2061_root"' EXIT
  mkdir -p "$_2061_root/scripts/development-workflow"
  cat >"$_2061_root/scripts/development-workflow/local-ai-reviewer.sh" <<'SYNTHETIC_REVIEW'
#!/usr/bin/env bash
printf '%s\n' 'RESULT=clean' 'REVIEW_STAGE=implementation' 'REVIEW_STAGE_SOURCE=synthetic' 'REVIEW_CHECKLISTS=Code Review Checklist' 'REVIEWED_HEAD=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' 'EVIDENCE_SNAPSHOT_SHA256=synthetic-current' 'EVIDENCE_MANIFEST_JSON={"schema":"review_evidence_manifest.v1","comments":[{"id":20}]}' 'EVIDENCE_VERIFICATION_JSON={"schema":"review_evidence_verification.v1","status":"verified"}'
SYNTHETIC_REVIEW
  chmod +x "$_2061_root/scripts/development-workflow/local-ai-reviewer.sh"
  workflow_repo_root() { printf '%s\n' "$_2061_root"; }
  repo_slug() { printf 'synthetic/repo\n'; }
  require_gh() { :; }
  # shellcheck disable=SC2034 # Read by the sourced production local adapter.
  repo_root="$_2061_root"
  run_local_ai_reviewer_review 2061 feature/2061-test 1 1
)"
run_test "2061_real_local_adapter_forwards_snapshot" synthetic-current \
  "$(kv_value_default EVIDENCE_SNAPSHOT_SHA256 "$_2061_adapter_output" missing)"
run_test "2061_real_local_adapter_forwards_proof" verified \
  "$(kv_value_default EVIDENCE_VERIFICATION_JSON "$_2061_adapter_output" '{}' | jq -r .status)"
run_test "2103_real_local_adapter_forwards_manifest" 20 \
  "$(kv_value_default EVIDENCE_MANIFEST_JSON "$_2061_adapter_output" '{}' | jq -r '.comments[0].id')"
unset _2061_adapter_output

# #2061: exercise the production pre-dispatch preparation, real durable
# reservation, and dispatch stub through repeated identical-head retries.
# shellcheck source=scripts/development-workflow/tests/lib/review-retry-fixture.sh
source "$REPO_ROOT/scripts/development-workflow/tests/lib/review-retry-fixture.sh"
run_test "2061_dispatch_stops_at_run_cap_same_sha" \
  '2|max_cycles_exceeded|3 3 available' "$(_retry2061_exercise run)"
run_test "2061_dispatch_stops_at_lifetime_cap_new_runs" \
  '2|max_total_cycles_exceeded|3 0 available' "$(_retry2061_exercise lifetime)"
run_test "2061_dispatch_requires_verified_reservation" \
  '0|cycle_count_unavailable|2 2 available' "$(_retry2061_exercise uncertain_write)"
unset -f _retry2061_exercise

# #1957 T-L1 (AC-6): under the loop, the backend comes from the configuration
# the loop hands to the reviewer (the PR base branch snapshot in config_file),
# not from the working-tree .ai-dev-workflow.yaml, and an operator's
# AI_DEV_WORKFLOW_CONFIG_FILE still takes priority. The real adapter runs the
# real local-ai-reviewer.sh from a copied tooling tree (plan D7) whose root
# file selects claude; the two presets are stand-ins that record their name.
_1957_out="$(
  _1957_root="$(mktemp -d)"
  _1957_root="$(CDPATH='' cd -- "$_1957_root" && pwd -P)"
  trap 'rm -rf "$_1957_root"' EXIT
  unset AI_DEV_WORKFLOW_CONFIG_FILE LOCAL_AI_REVIEWER_BACKEND LOCAL_AI_REVIEWER_COMMAND LOCAL_AI_REVIEWER_DISABLE_DEFAULT
  export GIT_CONFIG_GLOBAL="$_1957_root/global.gitconfig" GIT_CONFIG_NOSYSTEM=1 LOCAL_AI_REVIEWER_GRAPH_STRATEGY=none
  : > "$GIT_CONFIG_GLOBAL"
  _1957_tools="$_1957_root/scripts/development-workflow"
  mkdir -p "$_1957_tools" "$_1957_root/bin"
  while IFS= read -r -d '' _1957_path; do
    case "$_1957_path" in
      scripts/development-workflow/*/*) ;;
      scripts/development-workflow/*.sh|scripts/development-workflow/*.py) cp -p "$REPO_ROOT/$_1957_path" "$_1957_root/$_1957_path" ;;
    esac
  done < <(git -C "$REPO_ROOT" ls-files -z -- scripts/development-workflow)
  for _1957_preset in codex claude; do
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" %s >> "$_1957_REC"\nprintf "{\\"result\\":\\"clean\\",\\"reviewed_head\\":\\"%%s\\",\\"findings\\":[]}\\n" "$REVIEWED_HEAD"\n' \
      "$_1957_preset" > "$_1957_tools/local-${_1957_preset}-review-command.sh"
    chmod +x "$_1957_tools/local-${_1957_preset}-review-command.sh"
  done
  printf 'review:\n  local_ai_reviewer:\n    backend: claude\n' > "$_1957_root/.ai-dev-workflow.yaml"
  printf '# Review contract\n' > "$_1957_root/REVIEW.md"
  git -C "$_1957_root" init -q -b main
  git -C "$_1957_root" config user.email fixture@example.test
  git -C "$_1957_root" config user.name Fixture
  git -C "$_1957_root" remote add origin git@github.com:owner/repo.git
  git -C "$_1957_root" add REVIEW.md .ai-dev-workflow.yaml
  git -C "$_1957_root" commit -qm fixture
  export _1957_HEAD
  _1957_HEAD="$(git -C "$_1957_root" rev-parse HEAD)"
  cat > "$_1957_root/bin/gh" <<'MOCK_GH'
#!/usr/bin/env bash
case "$*" in
  *"pr view 1957"*"--json baseRefName,headRefName,headRefOid"*)
    printf '{"baseRefName":"develop","headRefName":"feature/1957-x","headRefOid":"%s"}\n' "$_1957_HEAD" ;;
  *"pr diff 1957"*"--name-only"*) printf '%s\n' REVIEW.md ;;
  *) exit 1 ;;
esac
MOCK_GH
  chmod +x "$_1957_root/bin/gh"
  export PATH="$_1957_root/bin:$PATH"
  export _1957_REC="$_1957_root/presets.log"
  printf 'review:\n  on_ready:\n    github:\n      - local-ai-reviewer\n' > "$_1957_root/base-without-key.yaml"
  printf 'review:\n  local_ai_reviewer:\n    backend: claude\n' > "$_1957_root/base-with-claude.yaml"
  printf 'review:\n  local_ai_reviewer:\n    backend: codex\n' > "$_1957_root/operator-codex.yaml"
  workflow_repo_root() { printf '%s\n' "$_1957_root"; }
  repo_slug() { printf 'owner/repo\n'; }
  require_gh() { :; }
  # shellcheck disable=SC2034 # Read by the sourced production local adapter.
  repo_root="$_1957_root"
  _1957_case() {
    : > "$_1957_REC"
    run_local_ai_reviewer_review 1957 feature/1957-x 1 60 >/dev/null 2>&1 || true
    printf '%s=%s\n' "$1" "$(tr '\n' ',' < "$_1957_REC")"
  }
  # shellcheck disable=SC2034 # Read by the sourced production local adapter.
  config_file="$_1957_root/base-without-key.yaml"
  _1957_case base_without_key
  # shellcheck disable=SC2034 # Read by the sourced production local adapter.
  config_file="$_1957_root/base-with-claude.yaml"
  _1957_case base_with_claude
  export AI_DEV_WORKFLOW_CONFIG_FILE="$_1957_root/operator-codex.yaml"
  _1957_case operator_override
)"
run_test "1957_T-L1_base_without_key_runs_codex" "codex," \
  "$(sed -n 's/^base_without_key=//p' <<< "$_1957_out")"
run_test "1957_T-L1_base_with_claude_runs_claude" "claude," \
  "$(sed -n 's/^base_with_claude=//p' <<< "$_1957_out")"
run_test "1957_T-L1_operator_config_takes_priority" "codex," \
  "$(sed -n 's/^operator_override=//p' <<< "$_1957_out")"
unset _1957_out

if [ "$FAIL_COUNT" -ne 0 ]; then
  echo "FAIL: $FAIL_COUNT test(s) failed"
  exit 1
fi

echo "PASS: $PASS_COUNT test(s) passed"
