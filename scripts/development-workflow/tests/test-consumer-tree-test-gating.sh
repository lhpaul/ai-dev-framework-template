#!/usr/bin/env bash
# test-consumer-tree-test-gating.sh — Unit tests for the template-vs-consumer
# switches that keep workflow test suites green in downstream repositories.
#
# Issue #1631: several suites asserted this template's own shipped defaults —
# the placeholder deploy.yml / e2e-regression.yml, the presence of
# pr-policy.yml, the literal on_draft.github reviewer list. A consumer that
# synced the template and legitimately replaced those files got a red required
# check on an otherwise successful sync (mome-cl/mome-platform#2706). The two
# helpers exercised here are how those suites now tell "this is the template"
# from "this is a consumer", so a regression in either silently re-breaks every
# downstream sync.
#
# Usage: bash scripts/development-workflow/tests/test-consumer-tree-test-gating.sh
# covers: scripts/development-workflow/workflow-lib.sh
# covers: scripts/development-workflow/tests/test-reviewer-loop-guard-workflow.sh
# covers: scripts/development-workflow/tests/test-placeholder-workflows-opt-in.sh
# covers: scripts/development-workflow/tests/test-batch-merge-recheck-remaining.sh
# covers: scripts/development-workflow/tests/test-local-ai-reviewer-pr-review-loop-dispatch.sh

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"

TMP_ROOT="$(mktemp -d)"

_harness_exit() {
  local status=$?
  rm -rf "$TMP_ROOT"
  # A pipeline reader closing early sends SIGPIPE (141) to the writer; under
  # `set -o pipefail` that would otherwise surface as a spurious failure.
  case "$status" in
    141) exit 0 ;;
    *) exit "$status" ;;
  esac
}
trap _harness_exit EXIT

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
    echo "FAIL: $name - expected '${expected}', got '${actual}'"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

# shellcheck source=scripts/development-workflow/workflow-lib.sh
source "$REPO_ROOT/scripts/development-workflow/workflow-lib.sh"

# ---------------------------------------------------------------------------
# Area 1: workflow_template_is_template
#
# Every branch prints a literal "true"/"false" rather than relying on an exit
# status, so a caller comparing with `=` cannot be fooled by an empty value.
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 1: workflow_template_is_template ==="

write_config() {
  local path="$1"
  shift
  printf '%s\n' "$@" > "$path"
}

write_config "$TMP_ROOT/template.yaml" 'template:' '  is_template: true'
run_test "is_template_true" "true" \
  "$(workflow_template_is_template "$TMP_ROOT/template.yaml")"

write_config "$TMP_ROOT/consumer.yaml" 'template:' '  is_template: false'
run_test "is_template_false" "false" \
  "$(workflow_template_is_template "$TMP_ROOT/consumer.yaml")"

# Negative assertion: the helper must not treat any non-true value as true.
write_config "$TMP_ROOT/garbage.yaml" 'template:' '  is_template: maybe'
run_test "is_template_unrecognized_value_is_false" "false" \
  "$(workflow_template_is_template "$TMP_ROOT/garbage.yaml")"

# Boundary: the key is absent from an otherwise valid section.
write_config "$TMP_ROOT/no-key.yaml" 'template:' '  upstream: owner/repo'
run_test "is_template_missing_key_is_false" "false" \
  "$(workflow_template_is_template "$TMP_ROOT/no-key.yaml")"

# Boundary: the whole section is absent.
write_config "$TMP_ROOT/no-section.yaml" 'review:' '  on_draft:' '    github:' '      - codex-github'
run_test "is_template_missing_section_is_false" "false" \
  "$(workflow_template_is_template "$TMP_ROOT/no-section.yaml")"

# Empty input: a zero-length config file must not be read as a template.
: > "$TMP_ROOT/empty.yaml"
run_test "is_template_empty_file_is_false" "false" \
  "$(workflow_template_is_template "$TMP_ROOT/empty.yaml")"

# Whitespace-only input: non-empty but semantically blank.
printf '   \n\t\n\n' > "$TMP_ROOT/blank.yaml"
run_test "is_template_whitespace_only_file_is_false" "false" \
  "$(workflow_template_is_template "$TMP_ROOT/blank.yaml")"

# Missing file: must be false, not an abort, so a suite can gate on it safely.
run_test "is_template_absent_file_is_false" "false" \
  "$(workflow_template_is_template "$TMP_ROOT/does-not-exist.yaml")"

# Quoted and case-variant values are the same declaration.
write_config "$TMP_ROOT/quoted.yaml" 'template:' '  is_template: "true"'
run_test "is_template_quoted_true" "true" \
  "$(workflow_template_is_template "$TMP_ROOT/quoted.yaml")"

write_config "$TMP_ROOT/upper.yaml" 'template:' '  is_template: TRUE'
run_test "is_template_uppercase_true" "true" \
  "$(workflow_template_is_template "$TMP_ROOT/upper.yaml")"

# Trailing comment on the value line must not defeat the match.
write_config "$TMP_ROOT/commented.yaml" 'template:' '  is_template: true  # set by setup'
run_test "is_template_trailing_comment" "true" \
  "$(workflow_template_is_template "$TMP_ROOT/commented.yaml")"

# Path containing spaces and a glob character: quoting must hold.
mkdir -p "$TMP_ROOT/dir with spaces [x]"
write_config "$TMP_ROOT/dir with spaces [x]/cfg.yaml" 'template:' '  is_template: true'
run_test "is_template_path_with_spaces_and_glob" "true" \
  "$(workflow_template_is_template "$TMP_ROOT/dir with spaces [x]/cfg.yaml")"

# A trailing comment on the section header is valid YAML. Reading it as "not a
# template" would silently downgrade a template repository to consumer handling
# and skip the very assertions these gates protect.
write_config "$TMP_ROOT/commented-header.yaml" 'template: # framework settings' '  is_template: true'
run_test "is_template_commented_section_header" "true" \
  "$(workflow_template_is_template "$TMP_ROOT/commented-header.yaml")"

write_config "$TMP_ROOT/spaced-header.yaml" 'template:   #   framework settings' '  is_template: true'
run_test "is_template_spaced_commented_section_header" "true" \
  "$(workflow_template_is_template "$TMP_ROOT/spaced-header.yaml")"

# Negative: a commented header must not turn a consumer into a template either.
write_config "$TMP_ROOT/commented-consumer.yaml" 'template: # framework settings' '  is_template: false'
run_test "is_template_commented_header_consumer_stays_false" "false" \
  "$(workflow_template_is_template "$TMP_ROOT/commented-consumer.yaml")"

# The repository's own config is the live contract this template ships.
run_test "is_template_live_repo_config" "true" \
  "$(workflow_template_is_template "$REPO_ROOT/.ai-dev-workflow.yaml")"

# ---------------------------------------------------------------------------
# Area 2: workflow_config_review_github_reviewer_configured
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 2: workflow_config_review_github_reviewer_configured ==="

reviewer_configured() {
  local platform="$1"
  local config="$2"
  if workflow_config_review_github_reviewer_configured "$platform" "$config"; then
    printf 'yes\n'
  else
    printf 'no\n'
  fi
}

write_config "$TMP_ROOT/reviewers.yaml" \
  'review:' \
  '  on_draft:' \
  '    runner:' \
  '      - codex' \
  '    github:' \
  '      - local-ai-reviewer' \
  '      - pr-agent' \
  '  on_ready:' \
  '    github:' \
  '      - codex-github'

run_test "reviewer_on_draft_list_hit" "yes" \
  "$(reviewer_configured pr-agent "$TMP_ROOT/reviewers.yaml")"
run_test "reviewer_on_ready_list_hit" "yes" \
  "$(reviewer_configured codex-github "$TMP_ROOT/reviewers.yaml")"

# Negative assertion: a reviewer absent from both lists must not be reported.
run_test "reviewer_absent_is_not_configured" "no" \
  "$(reviewer_configured greptile "$TMP_ROOT/reviewers.yaml")"

# The `runner` list is a different surface (Step 7a) and must not satisfy a
# Step 7 GitHub-reviewer question.
run_test "reviewer_runner_entry_is_not_a_github_reviewer" "no" \
  "$(reviewer_configured codex "$TMP_ROOT/reviewers.yaml")"

# Boundary: exact-match only. A prefix of a configured name is not configured,
# which is what keeps `pr-agent` from matching `pr-agent-experimental`.
write_config "$TMP_ROOT/prefix.yaml" \
  'review:' \
  '  on_draft:' \
  '    github:' \
  '      - pr-agent-experimental'
run_test "reviewer_prefix_does_not_match" "no" \
  "$(reviewer_configured pr-agent "$TMP_ROOT/prefix.yaml")"

# The MOME shape from #1631: local-ai-reviewer without pr-agent.
write_config "$TMP_ROOT/mome.yaml" \
  'review:' \
  '  on_draft:' \
  '    github:' \
  '      - local-ai-reviewer' \
  '  on_ready:' \
  '    github:' \
  '      - codex-github'
run_test "reviewer_consumer_keeps_local_ai" "yes" \
  "$(reviewer_configured local-ai-reviewer "$TMP_ROOT/mome.yaml")"
run_test "reviewer_consumer_drops_pr_agent" "no" \
  "$(reviewer_configured pr-agent "$TMP_ROOT/mome.yaml")"

# Empty platform argument must be rejected rather than matching a blank line.
run_test "reviewer_empty_platform_is_not_configured" "no" \
  "$(reviewer_configured "" "$TMP_ROOT/reviewers.yaml")"

# Whitespace-only platform argument is likewise not a configured reviewer.
run_test "reviewer_whitespace_platform_is_not_configured" "no" \
  "$(reviewer_configured "   " "$TMP_ROOT/reviewers.yaml")"

# A config file with no review section at all.
write_config "$TMP_ROOT/no-review.yaml" 'template:' '  is_template: false'
run_test "reviewer_missing_review_section" "no" \
  "$(reviewer_configured pr-agent "$TMP_ROOT/no-review.yaml")"

# Absent config file must return "not configured" rather than aborting.
run_test "reviewer_absent_config_file" "no" \
  "$(reviewer_configured pr-agent "$TMP_ROOT/does-not-exist.yaml")"

# The helper must survive `set -o pipefail`: an early-closing reader inside it
# would surface as exit 141 and kill the calling suite (#1631 regression).
set +e
(
  set -euo pipefail
  # shellcheck source=scripts/development-workflow/workflow-lib.sh
  source "$REPO_ROOT/scripts/development-workflow/workflow-lib.sh"
  workflow_config_review_github_reviewer_configured pr-agent "$TMP_ROOT/reviewers.yaml"
) >/dev/null 2>&1
pipefail_status=$?
set -e
run_test "reviewer_helper_does_not_sigpipe_under_pipefail" "0" "$pipefail_status"

# ---------------------------------------------------------------------------
# Area 3: the pr-policy suite skips in a consumer tree instead of failing
#
# Runs the real suite against a fabricated repository root that has no
# pr-policy.yml. The suite derives its repo root from its own location, so
# copying it plus workflow-lib.sh into a temp tree is enough to exercise the
# genuine skip path end to end.
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 3: pr-policy suite skip path ==="

# A `case` statement inside `$(...)` confuses bash's parser (the pattern's
# closing paren reads as the end of the substitution), so match via a function.
output_contains() {
  local haystack="$1"
  local needle="$2"
  if [ "${haystack#*"$needle"}" != "$haystack" ]; then
    printf 'yes\n'
  else
    printf 'no\n'
  fi
}

build_fake_root() {
  local root="$1"
  local is_template="$2"

  mkdir -p "$root/scripts/development-workflow/tests" "$root/.github/workflows"
  cp "$REPO_ROOT/scripts/development-workflow/workflow-lib.sh" \
    "$root/scripts/development-workflow/workflow-lib.sh"
  printf '%s\n' 'template:' "  is_template: $is_template" > "$root/.ai-dev-workflow.yaml"
}

consumer_root="$TMP_ROOT/consumer-repo"
build_fake_root "$consumer_root" false
cp "$REPO_ROOT/scripts/development-workflow/tests/test-reviewer-loop-guard-workflow.sh" \
  "$consumer_root/scripts/development-workflow/tests/"

set +e
consumer_output="$(bash "$consumer_root/scripts/development-workflow/tests/test-reviewer-loop-guard-workflow.sh" 2>&1)"
consumer_status=$?
set -e
run_test "pr_policy_suite_consumer_exit_status" "0" "$consumer_status"
run_test "pr_policy_suite_consumer_skips" "yes" \
  "$(output_contains "$consumer_output" "SKIP: consolidated PR policy workflow static checks")"

# Negative assertion: the same missing file in a template repository is still a
# hard failure, so the gate cannot mask a real regression here.
template_root="$TMP_ROOT/template-repo"
build_fake_root "$template_root" true
cp "$REPO_ROOT/scripts/development-workflow/tests/test-reviewer-loop-guard-workflow.sh" \
  "$template_root/scripts/development-workflow/tests/"

set +e
template_output="$(bash "$template_root/scripts/development-workflow/tests/test-reviewer-loop-guard-workflow.sh" 2>&1)"
template_status=$?
set -e
run_test "pr_policy_suite_template_missing_file_fails" "1" "$template_status"
run_test "pr_policy_suite_template_reports_failure" "yes" \
  "$(output_contains "$template_output" "FAIL: workflow_exists")"

# ---------------------------------------------------------------------------
# Area 4: planted-violation proof that the gates are load-bearing
#
# Grepping a suite for the helper name proves nothing: the name matches from a
# comment or a dead branch, so moving a template-only assertion back outside
# its guard would reintroduce the consumer failure while this suite stayed
# green. Instead, run each affected suite twice against the same fabricated
# consumer tree — once as shipped, and once with the guard mechanically
# removed. The gate is load-bearing only if the first passes and the second
# fails. If the assertion ever drifts outside the guard, the "planted" run
# stops differing from the shipped one and this suite goes red.
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 4: planted-violation proof ==="

# Remove a guard block from a copy of a suite, so the guarded assertions run
# unconditionally — exactly the regression these gates exist to prevent.
#
#   drop-block   delete the `if` through its matching `fi` entirely (used where
#                the guard is an early skip/return)
#   unwrap-else  keep only the `else` body, dropping the `if` header and the
#                `fi` (used where the guard wraps the assertions themselves)
#
# The guard is located by a needle matched against the `if` line, not by the
# helper name, because a suite may compute the helper's value into a variable
# on an earlier line.
plant_violation() {
  local src="$1"
  local dest="$2"
  local mode="$3"
  local guard_needle="$4"

  python3 - "$src" "$dest" "$mode" "$guard_needle" <<'PLANT'
import io
import sys

src, dest, mode, needle = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
lines = io.open(src, encoding="utf-8").read().split("\n")

guards = [
    i for i, line in enumerate(lines)
    if needle in line and line.lstrip().startswith("if ")
]
if len(guards) != 1:
    sys.exit("expected exactly one guard matching %r, found %d" % (needle, len(guards)))

guard = guards[0]
depth = 0
closer = None
for j in range(guard, len(lines)):
    stripped = lines[j].strip()
    if stripped.startswith("if ") or stripped == "if":
        depth += 1
    elif stripped == "fi" or stripped.startswith("fi "):
        depth -= 1
        if depth == 0:
            closer = j
            break

if closer is None:
    sys.exit("could not find the guard's matching fi")

if mode == "drop-block":
    planted = lines[:guard] + lines[closer + 1:]
elif mode == "unwrap-else":
    body_start = None
    depth = 0
    for j in range(guard, closer):
        stripped = lines[j].strip()
        if stripped.startswith("if ") or stripped == "if":
            depth += 1
        elif stripped == "fi" or stripped.startswith("fi "):
            depth -= 1
        elif stripped == "else" and depth == 1:
            body_start = j + 1
            break
    if body_start is None:
        sys.exit("guard has no else branch to unwrap")
    planted = lines[:guard] + lines[body_start:closer] + lines[closer + 1:]
else:
    sys.exit("unknown mode %r" % mode)

io.open(dest, "w", encoding="utf-8").write("\n".join(planted))
PLANT
}

# --- test-reviewer-loop-guard-workflow.sh -----------------------------------
# Already proven to skip as shipped (Area 3). Now prove the guard is what does
# it: without the guard the suite must fail in the same consumer tree.
planted_pr_policy="$consumer_root/scripts/development-workflow/tests/planted-pr-policy.sh"
# Planted violation: drop the early-skip block entirely, so the suite runs its
# pr-policy.yml assertions in a tree that has no such file.
plant_violation \
  "$REPO_ROOT/scripts/development-workflow/tests/test-reviewer-loop-guard-workflow.sh" \
  "$planted_pr_policy" drop-block '! -f "$WORKFLOW"' 

set +e
bash "$planted_pr_policy" >/dev/null 2>&1
planted_pr_policy_status=$?
set -e
run_test "pr_policy_guard_is_load_bearing" "yes" \
  "$(if [ "$planted_pr_policy_status" -ne 0 ]; then printf 'yes\n'; else printf 'no\n'; fi)"

# --- test-placeholder-workflows-opt-in.sh -----------------------------------
# Needs the template-owned docs it asserts against; symlink the real ones so the
# fabricated tree differs from this repository only in the ways a consumer
# actually differs.
placeholder_root="$TMP_ROOT/placeholder-consumer"
build_fake_root "$placeholder_root" false
mkdir -p "$placeholder_root/docs/workflow/development-workflow"
ln -s "$REPO_ROOT/docs/workflow/development-workflow/integrations" \
  "$placeholder_root/docs/workflow/development-workflow/integrations"
ln -s "$REPO_ROOT/docs/workflow/development-workflow/protocols" \
  "$placeholder_root/docs/workflow/development-workflow/protocols"

# A consumer's real pipelines, not this template's placeholders.
printf '%s\n' 'name: Deploy' 'on:' '  push:' '    branches: [main]' \
  > "$placeholder_root/.github/workflows/deploy.yml"
printf '%s\n' 'name: E2E regression' 'on:' '  workflow_dispatch:' \
  > "$placeholder_root/.github/workflows/e2e-regression.yml"

cp "$REPO_ROOT/scripts/development-workflow/tests/test-placeholder-workflows-opt-in.sh" \
  "$placeholder_root/scripts/development-workflow/tests/"

set +e
placeholder_output="$(bash "$placeholder_root/scripts/development-workflow/tests/test-placeholder-workflows-opt-in.sh" 2>&1)"
placeholder_status=$?
set -e
run_test "placeholder_suite_consumer_exit_status" "0" "$placeholder_status"
run_test "placeholder_suite_consumer_skips" "yes" \
  "$(output_contains "$placeholder_output" "SKIP: placeholder deploy/e2e workflow assertions")"

planted_placeholder="$placeholder_root/scripts/development-workflow/tests/planted-placeholder.sh"
# Planted violation: unwrap the guard so the placeholder-shape assertions run
# against this consumer tree's real deploy/e2e workflows.
plant_violation \
  "$REPO_ROOT/scripts/development-workflow/tests/test-placeholder-workflows-opt-in.sh" \
  "$planted_placeholder" unwrap-else '"$IS_TEMPLATE" != "true"' 

set +e
bash "$planted_placeholder" >/dev/null 2>&1
planted_placeholder_status=$?
set -e
run_test "placeholder_guard_is_load_bearing" "yes" \
  "$(if [ "$planted_placeholder_status" -ne 0 ]; then printf 'yes\n'; else printf 'no\n'; fi)"

# --- the two suites too expensive to nest -----------------------------------
# test-batch-merge-recheck-remaining.sh mocks a full gh surface, and
# test-pr-review-loop.sh runs for roughly 13 minutes; re-running either inside
# this suite would dominate its cost. Assert structurally instead that the
# gated assertion sits *inside* the guard block, which a comment or a dead
# branch cannot satisfy. Both still run for real in CI, in both trees.
assertion_is_inside_guard() {
  local suite="$1"
  local guard_needle="$2"
  local assertion_needle="$3"

  python3 - "$REPO_ROOT/scripts/development-workflow/tests/$suite" \
    "$guard_needle" "$assertion_needle" <<'INSIDE'
import io
import sys

path, guard_needle, assertion_needle = sys.argv[1], sys.argv[2], sys.argv[3]
lines = io.open(path, encoding="utf-8").read().split("\n")

guards = [
    i for i, line in enumerate(lines)
    if guard_needle in line and line.lstrip().startswith("if ")
]
if len(guards) != 1:
    print("no")
    raise SystemExit(0)

guard = guards[0]
depth = 0
closer = None
for j in range(guard, len(lines)):
    stripped = lines[j].strip()
    if stripped.startswith("if ") or stripped == "if":
        depth += 1
    elif stripped == "fi" or stripped.startswith("fi "):
        depth -= 1
        if depth == 0:
            closer = j
            break

if closer is None:
    print("no")
    raise SystemExit(0)

hits = [i for i, line in enumerate(lines) if assertion_needle in line]
print("yes" if hits and all(guard < i < closer for i in hits) else "no")
INSIDE
}

# Self-check: the containment helper must be able to say "no". Without this, a
# helper that always printed "yes" would make both checks above vacuous — the
# same weakness that the planted-violation runs exist to remove.
run_test "containment_helper_rejects_ungated_assertion" "no" \
  "$(assertion_is_inside_guard test-batch-merge-recheck-remaining.sh \
      'workflow_template_is_template' 'SCRIPT_DIR=')"

run_test "batch_merge_assertion_inside_is_template_guard" "yes" \
  "$(assertion_is_inside_guard test-batch-merge-recheck-remaining.sh \
      'workflow_template_is_template' 'placeholder_e2e_workflow_name_synced')"
run_test "pr_review_loop_assertion_inside_reviewer_guard" "yes" \
  "$(assertion_is_inside_guard test-pr-review-loop.sh \
      'workflow_config_review_github_reviewer_configured' 'workflows/pr-agent.yml')"

# --- assertions that must not come back -------------------------------------
suite_contains() {
  local suite="$1"
  local pattern="$2"
  if grep -Fq -- "$pattern" "$REPO_ROOT/scripts/development-workflow/tests/$suite"; then
    printf 'yes\n'
  else
    printf 'no\n'
  fi
}

# The literal template reviewer list must not return as an assertion.
run_test "local_ai_suite_drops_hardcoded_reviewer_list" "no" \
  "$(suite_contains test-local-ai-reviewer-pr-review-loop-dispatch.sh '"local-ai-reviewer,pr-agent"')"

# The workflow harness must provision a pinned PyYAML before running suites
# that parse workflow YAML, and must not reintroduce the SC2016 sed program.
workflow_file="$REPO_ROOT/.github/workflows/workflow-tests.yml"
run_test "workflow_provisions_pyyaml" "yes" \
  "$(grep -Fq -- 'Provision PyYAML' "$workflow_file" && printf 'yes\n' || printf 'no\n')"
run_test "workflow_pins_pyyaml_version" "yes" \
  "$(grep -Eq -- 'PyYAML==\$\{PYYAML_VERSION\}' "$workflow_file" && printf 'yes\n' || printf 'no\n')"
run_test "workflow_has_no_sc2016_sed_summary" "0" \
  "$(grep -cF -- "sed 's/^/- " "$workflow_file" || true)"

echo ""
echo "=== Summary ==="
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"

if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi
