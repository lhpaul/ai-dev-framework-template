#!/usr/bin/env bash
# test-worktree-recipe.sh — the documented worktree recipes must not leave a
# branch tracking the integration branch (issue #1593).
# covers: docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md
# covers: docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md
# covers: docs/workflow/development-workflow/protocols/01-generate-spec-protocol.md
# covers: docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md
# covers: docs/workflow/development-workflow/protocols/03-implement-development-protocol.md
# covers: docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md
# covers: docs/workflow/development-workflow/guardrails.md
# covers: docs/workflow/development-workflow/guardrails-enforcement.md
# covers: docs/workflow/development-workflow/README.md
# covers: .ai-dev-workflow.yaml
#
# The recipes are EXTRACTED from the protocol and executed, rather than restated
# here: a test that copies the command would keep passing after the protocol
# regressed. Placeholders are substituted, everything else is run as written.
#
# Usage: bash scripts/development-workflow/tests/test-worktree-recipe.sh

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"
PROTOCOL_91="$REPO_ROOT/docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md"
PROTOCOL_90="$REPO_ROOT/docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md"
PROTOCOL_DIR="$REPO_ROOT/docs/workflow/development-workflow/protocols"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

PASS=0
FAIL=0

check() {
  local name="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $name expected=[$expected] actual=[$actual]"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== test-worktree-recipe (#1593) ==="

# --- Self-coverage: CI must select this suite for everything it exercises ----
# Diff-based CI runs a suite only when a changed path matches its `# covers:`
# declarations. A suite that exercises a file it does not declare is a suite CI
# will not run when that file changes alone — the gap this check closes.
COVERAGE_TMP="$TMP_DIR/coverage"
mkdir -p "$COVERAGE_TMP"
SELF_PATH="scripts/development-workflow/tests/test-worktree-recipe.sh"
for covered in \
    docs/workflow/development-workflow/protocols/01-generate-spec-protocol.md \
    docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md \
    docs/workflow/development-workflow/protocols/03-implement-development-protocol.md \
    docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md \
    docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md \
    docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md \
    docs/workflow/development-workflow/guardrails.md \
    docs/workflow/development-workflow/guardrails-enforcement.md \
    docs/workflow/development-workflow/README.md \
    .ai-dev-workflow.yaml; do
  printf '%s\n' "$covered" > "$COVERAGE_TMP/changed.txt"
  if bash "$REPO_ROOT/scripts/development-workflow/select-test-suites.sh" \
      --changed-files "$COVERAGE_TMP/changed.txt" | grep -Fq "$SELF_PATH"; then
    check "ci_selects_this_suite_for_$(basename "$covered")" yes yes
  else
    check "ci_selects_this_suite_for_$(basename "$covered")" yes "not selected for $covered"
  fi
done

# --- Extract the documented commands -----------------------------------------
# Case A is the one that creates a branch from a base branch, and the only one
# that can set an upstream pointing somewhere else.
extract_case() {
  # extract_case <file> <case-label>: prints the git worktree add command line.
  awk -v label="$1" '
    $0 ~ ("^# " label ":") { found = 1; next }
    found && /^git worktree add / { print; exit }
    found && /^$/ { next }
  ' "$2"
}

CASE_A_CMD="$(extract_case "Case A" "$PROTOCOL_91")"
CASE_C_CMD="$(extract_case "Case C" "$PROTOCOL_91")"

if [ -z "$CASE_A_CMD" ]; then
  echo "FAIL: could not extract Case A recipe from $PROTOCOL_91"
  exit 1
fi
echo "Case A recipe: $CASE_A_CMD"
echo "Case C recipe: $CASE_C_CMD"

# AC-1 read directly off the documented text, before running anything: the
# recipe that branches from a base ref must suppress tracking.
case "$CASE_A_CMD" in
  *--no-track*) check case_a_documents_no_track yes yes ;;
  *) check case_a_documents_no_track yes "no: $CASE_A_CMD" ;;
esac
# Case C branches from its own remote branch, where tracking is correct. Require
# it to exist first: an empty extraction would otherwise satisfy the pattern
# check below, so deleting Case C from the protocol would pass silently.
if [ -n "$CASE_C_CMD" ]; then
  check case_c_recipe_present yes yes
else
  check case_c_recipe_present yes "Case C recipe missing from $PROTOCOL_91"
fi
case "$CASE_C_CMD" in
  *--no-track*) check case_c_keeps_tracking yes "no: $CASE_C_CMD" ;;
  *) check case_c_keeps_tracking yes yes ;;
esac

# --- Run the extracted Case A recipe for real --------------------------------
setup_repo() {
  local root="$1"
  git init -q --bare "$root/remote.git"
  git init -q "$root/repo"
  (
    cd "$root/repo"
    git config user.email test@example.com
    git config user.name Test
    printf 'seed\n' > README.md
    git add README.md
    git commit -q -m seed
    git branch -M develop
    git remote add origin "$root/remote.git"
    git push -q -u origin develop
  )
}

run_case_a() {
  # run_case_a <root> <command>: substitutes placeholders and runs the recipe.
  local root="$1" command="$2" resolved
  resolved="${command//<worktree-path>/$root/wt}"
  resolved="${resolved//<branch-prefix>\/<slug>/fix/1593-example}"
  resolved="${resolved//<base-branch>/develop}"
  ( cd "$root/repo" && eval "$resolved" >/dev/null 2>&1 )
}

ROOT_DOC="$TMP_DIR/documented"
mkdir -p "$ROOT_DOC"
setup_repo "$ROOT_DOC"
run_case_a "$ROOT_DOC" "$CASE_A_CMD"
# `git config --get` exits 1 when the key is absent, which is the asserted state.
DOC_MERGE="$(git -C "$ROOT_DOC/wt" config --get branch.fix/1593-example.merge || true)"  # workflow-shell-guard: allow SH001 - absent key is the asserted state
check case_a_no_base_upstream "" "$DOC_MERGE"

# A bare push from that worktree must not be able to write to develop, whatever
# push.default says. This is harm #2 from the issue.
(
  cd "$ROOT_DOC/wt"
  printf 'work\n' > work.txt
  git add work.txt
  git commit -q -m work
  git -c push.default=upstream push >/dev/null 2>&1 || true  # workflow-shell-guard: allow SH001 - the push is expected to fail; that it cannot reach develop is the property under test
)
# Read the BARE REMOTE, not the local remote-tracking ref. The remote is the
# thing under test; whether the pushing clone's origin/develop happens to be
# refreshed is git-version and configuration dependent, and an assertion about
# harm to the integration branch should not rest on that. (Measured on git
# 2.50.1 the tracking ref did move, so the previous form was not wrong here —
# it was simply asserting the wrong object.)
DEVELOP_AFTER="$(git -C "$ROOT_DOC/remote.git" rev-parse develop)"
DEVELOP_SEED="$(git -C "$ROOT_DOC/repo" rev-parse develop)"
check bare_push_cannot_reach_develop "$DEVELOP_SEED" "$DEVELOP_AFTER"

# The documented explicit refspec does reach the branch's own remote ref.
(
  cd "$ROOT_DOC/wt"
  git push -q origin "fix/1593-example:fix/1593-example"
)
LOCAL_SHA="$(git -C "$ROOT_DOC/wt" rev-parse HEAD)"
REMOTE_SHA="$(git -C "$ROOT_DOC/repo" ls-remote origin refs/heads/fix/1593-example | cut -f1)"
check explicit_refspec_push_lands "$LOCAL_SHA" "$REMOTE_SHA"

# Run the extracted Case C recipe against a branch that exists only on the
# remote: its upstream must be its OWN remote branch, which is why Case C
# deliberately keeps tracking. Measured, not asserted from the command text.
run_case_c() {
  local root="$1" command="$2" resolved
  resolved="${command//<worktree-path>/$root/wt-c}"
  resolved="${resolved//<branch-prefix>\/<slug>/fix/1593-remote-only}"
  ( cd "$root/repo" && eval "$resolved" >/dev/null 2>&1 )
}
(
  cd "$ROOT_DOC/repo"
  git checkout -q -b fix/1593-remote-only develop
  git push -q origin fix/1593-remote-only
  git checkout -q develop
  git branch -q -D fix/1593-remote-only
  git fetch -q origin
)
run_case_c "$ROOT_DOC" "$CASE_C_CMD"
CASE_C_MERGE="$(git -C "$ROOT_DOC/wt-c" config --get branch.fix/1593-remote-only.merge || true)"  # workflow-shell-guard: allow SH001 - absent key would be a failure this check reports
check case_c_tracks_its_own_remote_branch "refs/heads/fix/1593-remote-only" "$CASE_C_MERGE"

# --- Planted violation: the recipe as it was before #1593 --------------------
# Proves the assertion above is what separates the fixed recipe from the defect,
# rather than passing either way.
PLANT_CMD="${CASE_A_CMD//--no-track /}"
check plant_differs_from_documented different \
  "$( [ "$PLANT_CMD" != "$CASE_A_CMD" ] && echo different || echo same )"

ROOT_PLANT="$TMP_DIR/planted"
mkdir -p "$ROOT_PLANT"
setup_repo "$ROOT_PLANT"
run_case_a "$ROOT_PLANT" "$PLANT_CMD"
PLANT_MERGE="$(git -C "$ROOT_PLANT/wt" config --get branch.fix/1593-example.merge || true)"  # workflow-shell-guard: allow SH001 - absent key is a possible asserted state
check plant_tracks_base_branch "refs/heads/develop" "$PLANT_MERGE"

# ...and a bare push from the planted worktree writes straight onto develop.
(
  cd "$ROOT_PLANT/wt"
  printf 'work\n' > work.txt
  git add work.txt
  git commit -q -m work
  git -c push.default=upstream push >/dev/null 2>&1 || true  # workflow-shell-guard: allow SH001 - the planted recipe pushes onto develop; that harm is the property under test
)
PLANT_LOCAL="$(git -C "$ROOT_PLANT/wt" rev-parse HEAD)"
PLANT_DEVELOP="$(git -C "$ROOT_PLANT/remote.git" rev-parse develop)"
check plant_bare_push_lands_on_develop "$PLANT_LOCAL" "$PLANT_DEVELOP"

# --- AC-5: protocol 90's recipe is audited too -------------------------------
if grep -q 'git worktree add <manifest-assigned-worktree-path> <branch>' "$PROTOCOL_90"; then
  check protocol_90_recipe_present yes yes
else
  check protocol_90_recipe_present yes no
fi
# It creates no tracking of its own, so the protocol must send the reader to the
# upstream verification instead of leaving the inherited upstream unchecked.
if grep -q 'Upstream verification' "$PROTOCOL_90"; then
  check protocol_90_references_upstream_check yes yes
else
  check protocol_90_references_upstream_check yes no
fi
if grep -q 'Upstream verification — mandatory' "$PROTOCOL_91"; then
  check protocol_91_documents_upstream_check yes yes
else
  check protocol_91_documents_upstream_check yes no
fi

# --- The documented upstream assertion, executed --------------------------
# Extracted and run, not restated: it is the guard AC-1 relies on for Case B and
# for any branch whose upstream was set before this rule.
extract_upstream_check() {
  python3 - "$PROTOCOL_91" <<'PYUPSTREAM'
import pathlib
import sys

text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
block, inside = [], False
for line in text.splitlines():
    if line.strip().startswith("```"):
        if inside:
            if any("UPSTREAM_MERGE" in row for row in block):
                print("\n".join(block))
                sys.exit(0)
            block, inside = [], False
        else:
            block, inside = [], True
        continue
    if inside:
        block.append(line)
PYUPSTREAM
}

UPSTREAM_CHECK="$(extract_upstream_check)"
if [ -n "$UPSTREAM_CHECK" ]; then
  check upstream_check_extracted yes yes
else
  check upstream_check_extracted yes no
fi
printf '%s\n' "$UPSTREAM_CHECK" > "$TMP_DIR/upstream-check.sh"

run_upstream_check() {
  # run_upstream_check <worktree>: prints "pass" or "reject".
  if ( cd "$1" && bash "$TMP_DIR/upstream-check.sh" >/dev/null 2>&1 ); then
    printf 'pass'
  else
    printf 'reject'
  fi
}

# The documented recipe's own worktree passes it.
check upstream_check_accepts_documented pass "$(run_upstream_check "$ROOT_DOC/wt")"
# The planted recipe's worktree — tracking refs/heads/develop — is rejected.
check upstream_check_rejects_base_tracking reject "$(run_upstream_check "$ROOT_PLANT/wt")"
# Case C's worktree tracks its OWN remote branch, which the check must accept:
# the guard rejects a wrong destination, not the presence of an upstream.
check upstream_check_accepts_case_c pass "$(run_upstream_check "$ROOT_DOC/wt-c")"

# Right branch name, WRONG REMOTE: a bare push would go somewhere the pull
# request never sees. The name alone is only half the destination.
git -C "$ROOT_DOC/repo" remote add backup "$ROOT_DOC/remote.git"
git -C "$ROOT_DOC/wt" config branch.fix/1593-example.remote backup
git -C "$ROOT_DOC/wt" config branch.fix/1593-example.merge refs/heads/fix/1593-example
check upstream_check_rejects_wrong_remote reject "$(run_upstream_check "$ROOT_DOC/wt")"
# Restore the state the recipe produced.
git -C "$ROOT_DOC/wt" branch --unset-upstream fix/1593-example 2>/dev/null || true  # workflow-shell-guard: allow SH001 - unsetting an absent upstream is not an error here
check upstream_check_accepts_after_unset pass "$(run_upstream_check "$ROOT_DOC/wt")"

# --- Named-stop contract (guardrails-enforcement.md section 5) ---------------
# Every stop this change introduces must name an exact stop condition from the
# table in section 4, the affected item, and a concrete human action. A stop
# that only prints ERROR leaves the operator with nothing to act on.
GUARDRAILS_DOC="$REPO_ROOT/docs/workflow/development-workflow/guardrails-enforcement.md"
check_named_stops() {
  # check_named_stops <file>: every `exit 1` in a block this change owns must
  # have its OWN STOP block. Evaluated per guard, not per block: a block with two
  # guards would otherwise pass on the strength of the first one's message.
  python3 - "$1" "$GUARDRAILS_DOC" <<'PYSTOPS'
import pathlib
import re
import sys

text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
known = set(re.findall(r"^\| `([a-z_]+)` \|", pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"), re.M))
blocks, block, inside = [], [], False
for line in text.splitlines():
    if line.strip().startswith("```"):
        if inside:
            blocks.append(block)
        block, inside = [], not inside
        continue
    if inside:
        block.append(line)

count = 0
for block in blocks:
    body = "\n".join(block)
    # Scope: the stops THIS change introduces — post-push verification and the
    # worktree upstream verification. Pre-existing stops elsewhere in these
    # protocols are a separate sweep and are out of scope for #1593.
    if ("REMOTE_SHA" not in body) and ("UPSTREAM_MERGE" not in body):
        continue
    guard = []
    for line in block:
        if re.match(r"^\s*exit 1\s*$", line):
            count += 1
            guard_body = "\n".join(guard)
            named = re.search(r"STOP: guardrail '([a-z_]+)'", guard_body)
            if not named:
                print("OFFENDER=guard with no named stop condition near: " + (guard[-1].strip()[:60] if guard else "<start of block>"))
            elif named.group(1) not in known:
                print("OFFENDER=unknown stop condition " + named.group(1))
            elif "Item:" not in guard_body:
                print("OFFENDER=no affected item: " + named.group(1))
            elif "Human action:" not in guard_body:
                print("OFFENDER=no human action: " + named.group(1))
            guard = []
            continue
        guard.append(line)
print("COUNT=" + str(count))
PYSTOPS
}

# The condition these stops name must be declared on EVERY normative surface a
# consumer repository reads, not on a hand-listed subset: the surfaces are
# DISCOVERED by looking for `stop_conditions:` lists and the enforcement table,
# so a fourth one added later is audited automatically instead of drifting.
STOP_CONDITION_NAME=push_verification_failed

audit_stop_surfaces() {
  # audit_stop_surfaces <docs-root> <config-file> [extra-table-file]
  # Prints COUNT=<n> and one MISSING=<file> per surface lacking the condition.
  local docs_root="$1" config_file="$2" extra="${3:-}" surfaces surface count=0
  surfaces="$(grep -rl '^[[:space:]]*stop_conditions:' "$docs_root" "$config_file" 2>/dev/null || true)"  # workflow-shell-guard: allow SH001 - grep exits 1 on zero matches, reported by COUNT
  if [ -n "$extra" ] && [ -f "$extra" ]; then
    surfaces="${surfaces}
$extra"
  fi
  while IFS= read -r surface; do
    [ -n "$surface" ] || continue
    count=$((count + 1))
    grep -Fq -- "$STOP_CONDITION_NAME" "$surface" || printf 'MISSING=%s\n' "$surface"
  done <<AUDIT_SURFACES
$surfaces
AUDIT_SURFACES
  printf 'COUNT=%s\n' "$count"
}

STOP_AUDIT="$(audit_stop_surfaces "$REPO_ROOT/docs/workflow" "$REPO_ROOT/.ai-dev-workflow.yaml" "$REPO_ROOT/docs/workflow/development-workflow/guardrails-enforcement.md")"
STOP_MISSING="$(printf '%s\n' "$STOP_AUDIT" | grep '^MISSING=' || true)"  # workflow-shell-guard: allow SH001 - grep exits 1 when nothing is missing, which is the passing state
STOP_SURFACE_COUNT="$(printf '%s\n' "$STOP_AUDIT" | awk -F= '/^COUNT=/{print $2; exit}')"
check stop_condition_declared_on_every_surface "" "$STOP_MISSING"
# Four surfaces today: the two guardrails documents, the workflow README's
# example config, and the shipped .ai-dev-workflow.yaml.
if [ "$STOP_SURFACE_COUNT" -ge 4 ]; then
  check stop_surface_discovery_not_vacuous yes yes
else
  check stop_surface_discovery_not_vacuous yes "only ${STOP_SURFACE_COUNT} surface(s) discovered"
fi

# Planted variant: a FIFTH surface that ships a stop_conditions list without the
# condition. Discovery must find it and the audit must report it, or a future
# surface could drift unnoticed — the exact failure that produced this check.
PLANT_SURFACE_ROOT="$TMP_DIR/planted-surfaces"
mkdir -p "$PLANT_SURFACE_ROOT/docs/workflow/development-workflow"
cp "$REPO_ROOT/docs/workflow/development-workflow/guardrails.md" \
   "$REPO_ROOT/docs/workflow/development-workflow/README.md" \
   "$REPO_ROOT/docs/workflow/development-workflow/guardrails-enforcement.md" \
   "$PLANT_SURFACE_ROOT/docs/workflow/development-workflow/"
cp "$REPO_ROOT/.ai-dev-workflow.yaml" "$PLANT_SURFACE_ROOT/.ai-dev-workflow.yaml"
cat > "$PLANT_SURFACE_ROOT/docs/workflow/development-workflow/consumer-example.md" <<'PLANTED_SURFACE'
```yaml
guardrails:
  stop_conditions:
    - unclear_requirements
    - failing_ci
```
PLANTED_SURFACE
PLANT_AUDIT="$(audit_stop_surfaces "$PLANT_SURFACE_ROOT/docs/workflow" "$PLANT_SURFACE_ROOT/.ai-dev-workflow.yaml" "$PLANT_SURFACE_ROOT/docs/workflow/development-workflow/guardrails-enforcement.md")"
PLANT_MISSING_COUNT="$(printf '%s\n' "$PLANT_AUDIT" | grep -c '^MISSING=' || true)"  # workflow-shell-guard: allow SH001 - grep exits 1 on zero matches, which this check reports
PLANT_SURFACE_COUNT="$(printf '%s\n' "$PLANT_AUDIT" | awk -F= '/^COUNT=/{print $2; exit}')"
check plant_fifth_surface_is_reported 1 "$PLANT_MISSING_COUNT"
check plant_fifth_surface_is_discovered 5 "$PLANT_SURFACE_COUNT"

# ...and the stops must actually use it, not the borrowed condition they used
# before this was a canonical name.
BORROWED_STOPS="$(grep -rl "STOP: guardrail 'unclear_requirements' halted this run" "$PROTOCOL_DIR" || true)"  # workflow-shell-guard: allow SH001 - grep exits 1 when there is no match, which is the passing state
check no_borrowed_stop_condition "" "$BORROWED_STOPS"

NAMED_STOP_PROTOCOLS="01-generate-spec-protocol 02-generate-implementation-plan-protocol 03-implement-development-protocol 91-orchestrate-work-protocol 93-automated-reviewer-loop-protocol"
STOP_COUNT_TOTAL=0
for stop_protocol in $NAMED_STOP_PROTOCOLS; do
  STOP_REPORT="$(check_named_stops "$PROTOCOL_DIR/${stop_protocol}.md")"
  STOP_OFFENDERS="$(printf '%s\n' "$STOP_REPORT" | grep '^OFFENDER=' || true)"  # workflow-shell-guard: allow SH001 - grep exits 1 when there is no offender, which is the passing state
  check "named_stops_${stop_protocol}" "" "$STOP_OFFENDERS"
  STOP_COUNT="$(printf '%s\n' "$STOP_REPORT" | awk -F= '/^COUNT=/{print $2; exit}')"
  STOP_COUNT_TOTAL=$((STOP_COUNT_TOTAL + STOP_COUNT))
done
# All five protocols contribute: 6 push blocks with 3 guards each (wrong branch,
# push failed, push did not land), 2 upstream guards, and 2 push-retry stops in
# protocol 93.
if [ "$STOP_COUNT_TOTAL" -ge 22 ]; then
  check named_stop_sweep_not_vacuous yes yes
else
  check named_stop_sweep_not_vacuous yes "only ${STOP_COUNT_TOTAL} guard(s) found"
fi

# Planted variant: strip the STOP lines from the SECOND upstream guard only. A
# per-block check would still pass on the first guard's message; a per-guard one
# reports it.
PLANT_STOPS_DIR="$TMP_DIR/planted-stops"
mkdir -p "$PLANT_STOPS_DIR"
cp "$PROTOCOL_DIR"/*.md "$PLANT_STOPS_DIR/"
python3 - "$PLANT_STOPS_DIR/91-orchestrate-work-protocol.md" <<'PYPLANTSTOP'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
old = """  echo "STOP: guardrail 'push_verification_failed' halted this run."
  echo "Item: branch ${BRANCH} in this worktree."
  echo "Cause: it tracks remote '${UPSTREAM_REMOTE}', not 'origin', so a bare"
  echo "  'git push' from here would not reach the pull request."
  echo "Human action: run 'git branch --unset-upstream' in this worktree, then re-run"
  echo "  this verification before any push."
"""
if old not in text:
    sys.exit("plant target not found")
path.write_text(text.replace(old, '  echo "ERROR: wrong remote."\n', 1), encoding="utf-8")
PYPLANTSTOP
PLANT_STOP_OFFENDERS="$(check_named_stops "$PLANT_STOPS_DIR/91-orchestrate-work-protocol.md" | grep -c '^OFFENDER=' || true)"  # workflow-shell-guard: allow SH001 - grep exits 1 on zero matches, which this check reports
check plant_second_guard_without_stop_is_reported 1 "$PLANT_STOP_OFFENDERS"

# --- AC-2 / AC-3: every documented branch push ------------------------------
# Each protocol that pushes an item branch must push with an explicit refspec
# and then compare the remote head to local. Checked by extraction, so a
# protocol that drops either half fails here.
extract_push_block() {
  # extract_push_block <file> <branch-placeholder>: prints the fenced block that
  # contains that branch's refspec push, and nothing else. Checking the whole
  # file would let one block satisfy another block's requirement.
  python3 - "$1" "$2" <<'PYBLOCK'
import pathlib
import sys

text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
branch = sys.argv[2]
needle = f'git push origin "{branch}:{branch}"'
block, inside = [], False
for line in text.splitlines():
    if line.strip().startswith("```"):
        if inside:
            if any(needle in row for row in block):
                print("\n".join(block))
                sys.exit(0)
            block, inside = [], False
        else:
            block, inside = [], True
        continue
    if inside:
        block.append(line)
PYBLOCK
}

check_push_step() {
  # check_push_step <protocol-file> <branch-placeholder> <label>
  local file="$1" branch="$2" label="$3" name block block_first_line
  name="$(basename "$file" .md)_${label}"
  block="$(extract_push_block "$file" "$branch")"
  if [ -z "$block" ]; then
    check "push_refspec_${name}" yes "no refspec block for ${branch}"
    check "push_verified_${name}" yes "no refspec block for ${branch}"
    check "push_exit_gate_${name}" yes "no refspec block for ${branch}"
    return 0
  fi
  check "push_refspec_${name}" yes yes
  # `set -euo pipefail` must be the FIRST line, so a failed `git add` or
  # `git commit` cannot fall through and push an older HEAD.
  # Blocks inside numbered list items are indented; compare the trimmed line.
  block_first_line="$(printf '%s\n' "$block" | sed -n '1s/^[[:space:]]*//p')"
  if [ "$block_first_line" = "set -euo pipefail" ]; then
    check "push_shell_options_first_${name}" yes yes
  else
    check "push_shell_options_first_${name}" yes "first line is: $block_first_line"
  fi
  # The ls-remote must name THIS branch, inside THIS block.
  if printf '%s\n' "$block" | grep -Fq "git ls-remote origin \"refs/heads/${branch}\""; then
    check "push_verified_${name}" yes yes
  else
    check "push_verified_${name}" yes "no remote-head comparison for ${branch} in its own block"
  fi
  # ...and the comparison must be a gate, in THIS block, not merely present
  # somewhere else in the same file.
  if printf '%s\n' "$block" | grep -Fq 'if [ "$LOCAL_SHA" != "$REMOTE_SHA" ]; then' &&
      printf '%s\n' "$block" | grep -Eq '^[[:space:]]*exit 1[[:space:]]*$'; then
    check "push_exit_gate_${name}" yes yes
  else
    check "push_exit_gate_${name}" yes "comparison is not a gate for ${branch}"
  fi
}
check_push_step "$PROTOCOL_DIR/01-generate-spec-protocol.md" 'spec/[branch-slug]' spec
check_push_step "$PROTOCOL_DIR/02-generate-implementation-plan-protocol.md" 'implementation-plan/[branch-slug]' plan
check_push_step "$PROTOCOL_DIR/03-implement-development-protocol.md" 'feature/[slug]' feature
check_push_step "$PROTOCOL_DIR/03-implement-development-protocol.md" 'fix/[branch-slug]' fix
check_push_step "$PROTOCOL_DIR/03-implement-development-protocol.md" 'refactor/[branch-slug]' refactor
check_push_step "$PROTOCOL_DIR/03-implement-development-protocol.md" 'hotfix/[branch-slug]' hotfix

# Every implementation path in protocol 03 must have a push step, and the sweep
# above only sees the ones that exist. A path that pushes in prose — as the
# Refactor path did — is invisible to it, so require one push block per path.
PATH_PUSH_COUNT=0
for path_branch in 'feature/[slug]' 'fix/[branch-slug]' 'refactor/[branch-slug]' 'hotfix/[branch-slug]'; do
  if [ -n "$(extract_push_block "$PROTOCOL_DIR/03-implement-development-protocol.md" "$path_branch")" ]; then
    PATH_PUSH_COUNT=$((PATH_PUSH_COUNT + 1))
  fi
done
check protocol_03_all_paths_have_push_block 4 "$PATH_PUSH_COUNT"

# --- The documented push block, executed ------------------------------------
# The wrong-branch guard is asserted structurally above; run it, so a guard that
# stops detecting the wrong branch fails here rather than keeping its STOP text.
GUARD_ROOT="$TMP_DIR/push-guard"
mkdir -p "$GUARD_ROOT"
setup_repo "$GUARD_ROOT"
GUARD_BRANCH=fix/1593-guard-demo
PUSH_BLOCK_RAW="$(extract_push_block "$PROTOCOL_DIR/03-implement-development-protocol.md" 'fix/[branch-slug]')"
# The fence also carries the `git add [files]` / `git commit` placeholders, which
# are not runnable; drop exactly those two lines and assert both were found, so
# the test cannot quietly skip more of the block than it means to.
PUSH_BLOCK="$(printf '%s\n' "$PUSH_BLOCK_RAW" | grep -vE '^[[:space:]]*git add \[files\][[:space:]]*$|^[[:space:]]*git commit -m ')"  # workflow-shell-guard: allow SH001 - grep -v exits 1 only if every line is dropped, reported by the count below
DROPPED_LINES=$(( $(printf '%s\n' "$PUSH_BLOCK_RAW" | wc -l) - $(printf '%s\n' "$PUSH_BLOCK" | wc -l) ))
check push_block_dropped_only_placeholders 2 "$DROPPED_LINES"
if [ -n "$PUSH_BLOCK" ]; then
  check push_block_executable_part_extracted yes yes
else
  check push_block_executable_part_extracted yes "empty after dropping placeholders"
fi
# NOT ${var//pattern/...}: bash treats `[branch-slug]` as a character class, so
# the placeholder would match one character rather than the literal text.
printf '%s\n' "$PUSH_BLOCK" | sed "s|fix/\[branch-slug\]|$GUARD_BRANCH|g" > "$GUARD_ROOT/push-block.sh"
if grep -Fq -- "$GUARD_BRANCH" "$GUARD_ROOT/push-block.sh" &&
    ! grep -Fq -- 'fix/[branch-slug]' "$GUARD_ROOT/push-block.sh"; then  # workflow-shell-guard: allow SH004 - literal placeholder text, not a branch-prefix match
  check push_block_placeholder_substituted yes yes
else
  check push_block_placeholder_substituted yes "placeholder still present"
fi
(
  cd "$GUARD_ROOT/repo"
  git checkout -q -b "$GUARD_BRANCH"
  printf 'work\n' > work.txt
  git add work.txt
  git commit -q -m work
)
run_push_block() {
  # run_push_block: prints the exit code; output lands in $TMP_DIR/last.out.
  local rc=0
  ( cd "$GUARD_ROOT/repo" && bash "$GUARD_ROOT/push-block.sh" ) > "$TMP_DIR/last.out" 2>&1 || rc=$?
  printf '%s' "$rc"
}

# On the right branch the documented block pushes and verifies.
check push_block_on_correct_branch_succeeds 0 "$(run_push_block)"
GUARD_LOCAL="$(git -C "$GUARD_ROOT/repo" rev-parse "$GUARD_BRANCH")"
GUARD_REMOTE="$(git -C "$GUARD_ROOT/remote.git" rev-parse "$GUARD_BRANCH")"
check push_block_landed_on_remote "$GUARD_LOCAL" "$GUARD_REMOTE"

# On another branch it stops before pushing, with the named condition.
git -C "$GUARD_ROOT/repo" checkout -q develop
check push_block_on_wrong_branch_stops 1 "$(run_push_block)"
if grep -q "push_verification_failed" "$TMP_DIR/last.out"; then
  check push_block_wrong_branch_names_condition yes yes
else
  check push_block_wrong_branch_names_condition yes "$(cat "$TMP_DIR/last.out")"
fi
# A push that FAILS must produce the contractual stop, not a bare `set -e` exit
# with no message. Point origin at a path that is not a repository.
git -C "$GUARD_ROOT/repo" checkout -q "$GUARD_BRANCH"
git -C "$GUARD_ROOT/repo" remote set-url origin "$GUARD_ROOT/not-a-repo"
printf 'work2\n' > "$GUARD_ROOT/repo/work2.txt"
git -C "$GUARD_ROOT/repo" add work2.txt
git -C "$GUARD_ROOT/repo" commit -q -m work2
check push_block_failed_push_stops 1 "$(run_push_block)"
if grep -q "push_verification_failed" "$TMP_DIR/last.out" && grep -q "git push failed" "$TMP_DIR/last.out"; then
  check push_block_failed_push_names_condition yes yes
else
  check push_block_failed_push_names_condition yes "$(cat "$TMP_DIR/last.out")"
fi
git -C "$GUARD_ROOT/repo" remote set-url origin "$GUARD_ROOT/remote.git"
git -C "$GUARD_ROOT/repo" checkout -q develop

# ...and it stopped BEFORE pushing: develop must not have moved.
GUARD_DEVELOP_AFTER="$(git -C "$GUARD_ROOT/remote.git" rev-parse develop)"
GUARD_DEVELOP_SEED="$(git -C "$GUARD_ROOT/repo" rev-parse develop)"
check push_block_wrong_branch_pushed_nothing "$GUARD_DEVELOP_SEED" "$GUARD_DEVELOP_AFTER"

# Each of those protocols must also carry

# Planted variant: displace `set -euo pipefail` in the feature path — a path the
# executed test above does not use — and confirm the per-block check reports it.
PLANT_OPTIONS_DIR="$TMP_DIR/planted-options"
mkdir -p "$PLANT_OPTIONS_DIR"
cp "$PROTOCOL_DIR/03-implement-development-protocol.md" "$PLANT_OPTIONS_DIR/"
python3 - "$PLANT_OPTIONS_DIR/03-implement-development-protocol.md" <<'PYPLANTOPTS'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
needle = 'git push origin "feature/[slug]:feature/[slug]"'
fence = text.rindex("```bash\n", 0, text.index(needle)) + len("```bash\n")
old = "set -euo pipefail\ngit add [files]\n"
if not text.startswith(old, fence):
    sys.exit("plant target not found")
path.write_text(text[:fence] + "git add [files]\nset -euo pipefail\n" + text[fence + len(old):], encoding="utf-8")
PYPLANTOPTS
PLANT_FIRST_LINE="$(extract_push_block "$PLANT_OPTIONS_DIR/03-implement-development-protocol.md" 'feature/[slug]' | sed -n '1p')"
check plant_displaced_shell_options_is_reported "git add [files]" "$PLANT_FIRST_LINE"

# Planted variant: put the Refactor path back in prose. The count must drop, or
# the check above would pass on a document that reintroduced the defect.
PLANT_PROSE_DIR="$TMP_DIR/planted-prose"
mkdir -p "$PLANT_PROSE_DIR"
cp "$PROTOCOL_DIR/03-implement-development-protocol.md" "$PLANT_PROSE_DIR/"
python3 - "$PLANT_PROSE_DIR/03-implement-development-protocol.md" <<'PYPLANTPROSE'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
needle = 'git push origin "refactor/[branch-slug]:refactor/[branch-slug]"'
if needle not in text:
    sys.exit("plant target not found")
start = text.rindex("8. Push with an explicit refspec", 0, text.index(needle))
end = text.index("```\n", text.index(needle)) + len("```\n")
path.write_text(text[:start] + "8. Push branch to remote\n" + text[end:], encoding="utf-8")
PYPLANTPROSE
PLANT_PATH_COUNT=0
for path_branch in 'feature/[slug]' 'fix/[branch-slug]' 'refactor/[branch-slug]' 'hotfix/[branch-slug]'; do
  if [ -n "$(extract_push_block "$PLANT_PROSE_DIR/03-implement-development-protocol.md" "$path_branch")" ]; then
    PLANT_PATH_COUNT=$((PLANT_PATH_COUNT + 1))
  fi
done
check plant_prose_refactor_path_is_reported 3 "$PLANT_PATH_COUNT"

# Sweep, so a push step added later cannot skip the rule: no documented push of
# an ITEM branch may be left bare or given a bare branch name. Base-branch
# pushes (develop-<slug>, release, tags) are deliberate and excluded — they are
# not reached from an item worktree.
BARE_PUSHES="$(grep -rn '^[[:space:]]*git push[[:space:]]*$' "$PROTOCOL_DIR" || true)"  # workflow-shell-guard: allow SH001 - grep exits 1 when there is no match, which is the passing state
check no_bare_push_in_protocols "" "$BARE_PUSHES"

ITEM_PUSHES="$(grep -rhE 'git push .*(spec|implementation-plan|feature|fix|hotfix|refactor)/' "$PROTOCOL_DIR" || true)"  # workflow-shell-guard: allow SH001 - grep exits 1 when there is no match, reported by the non-vacuity check below
MISSING_REFSPEC=""
ITEM_PUSH_COUNT=0
while IFS= read -r push_line; do
  [ -n "$push_line" ] || continue
  ITEM_PUSH_COUNT=$((ITEM_PUSH_COUNT + 1))
  case "$push_line" in
    *:*) : ;;
    *) MISSING_REFSPEC="${MISSING_REFSPEC}${push_line}"$'\n' ;;
  esac
done <<ITEM_PUSH_LINES
$ITEM_PUSHES
ITEM_PUSH_LINES
check every_item_push_uses_refspec "" "$MISSING_REFSPEC"

# Protocol 93's fixer pushes name the branch through a variable rather than a
# placeholder, so the prefix sweep above cannot see them. Every push in that
# protocol must still be a self-refspec — the initial one as much as the retry,
# since a bare initial push has already done the damage by the time the retry
# runs.
# A refspec is not enough: `git push origin "${FIX_BRANCH}:develop"` contains a
# colon and would satisfy any "has a refspec" check while reintroducing exactly
# the push onto the integration branch this issue removes. Every quoted refspec
# push in the protocols must have the SAME ref on both sides.
check_self_refspecs() {
  # check_self_refspecs <protocol-dir>: prints COUNT= and any OFFENDER= lines.
  # The directory is passed as an argument, not on stdin: the heredoc below IS
  # this python's stdin.
  python3 - "$1" <<'PYSELF'
import pathlib
import re
import sys

# Anchored at line start: prose and echo lines that QUOTE a push command are
# not push commands, and their escaped quotes parse into nonsense groups.
pattern = re.compile(r'^\s*(?:if ! )?git push [^"\n]*"([^"]+):([^"]+)"')
offenders = []
count = 0
for path in sorted(pathlib.Path(sys.argv[1]).glob("*.md")):
    for line in path.read_text(encoding="utf-8").splitlines():
        match = pattern.search(line)
        if not match:
            continue
        count += 1
        if match.group(1) != match.group(2):
            offenders.append(f"{path.name}: {line.strip()}")
print("COUNT=" + str(count))
for offender in offenders:
    print("OFFENDER=" + offender)
PYSELF
}

SELF_REFSPEC_REPORT="$(check_self_refspecs "$PROTOCOL_DIR")"
SELF_REFSPEC_OFFENDERS="$(printf '%s\n' "$SELF_REFSPEC_REPORT" | grep '^OFFENDER=' || true)"  # workflow-shell-guard: allow SH001 - grep exits 1 when there is no offender, which is the passing state
SELF_REFSPEC_COUNT="$(printf '%s\n' "$SELF_REFSPEC_REPORT" | awk -F= '/^COUNT=/{print $2; exit}')"
check every_refspec_is_self_refspec "" "$SELF_REFSPEC_OFFENDERS"
if [ "${SELF_REFSPEC_COUNT:-0}" -ge 10 ]; then
  check self_refspec_sweep_not_vacuous yes yes
else
  check self_refspec_sweep_not_vacuous yes "only ${SELF_REFSPEC_COUNT} refspec push(es) found"
fi

# Planted variant: retarget one push at develop and confirm it is reported.
PLANT_DIR="$TMP_DIR/planted-protocols"
mkdir -p "$PLANT_DIR"
cp "$PROTOCOL_DIR"/*.md "$PLANT_DIR/"
python3 - "$PLANT_DIR/93-automated-reviewer-loop-protocol.md" <<'PYPLANTPUSH'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
old = 'git push origin "${FIX_BRANCH}:${FIX_BRANCH}"'
if old not in text:
    sys.exit("plant target not found")
path.write_text(text.replace(old, 'git push origin "${FIX_BRANCH}:develop"', 1), encoding="utf-8")
PYPLANTPUSH
PLANT_REPORT="$(check_self_refspecs "$PLANT_DIR")"
PLANT_OFFENDERS="$(printf '%s\n' "$PLANT_REPORT" | grep -c '^OFFENDER=' || true)"  # workflow-shell-guard: allow SH001 - grep exits 1 on zero matches, which this check reports
check plant_retargeted_push_is_reported 1 "$PLANT_OFFENDERS"

# Protocol 93's fixer pushes name their branch through a variable rather than a
# placeholder, so `check_push_step` cannot reach them. Audit them separately:
# every push must be a self-refspec, and every multi-command block must set the
# shell options first, exactly as the six placeholder blocks do.
P93="$PROTOCOL_DIR/93-automated-reviewer-loop-protocol.md"
P93_PUSHES="$(grep -cE '^[[:space:]]*(if ! )?git push' "$P93" || true)"  # workflow-shell-guard: allow SH001 - grep exits 1 on zero matches, reported by the count assertion
P93_REFSPEC_PUSHES="$(grep -cE '^[[:space:]]*(if ! )?git push origin "[^"]+:[^"]+"' "$P93" || true)"  # workflow-shell-guard: allow SH001 - same zero-match case
check protocol_93_all_pushes_refspec "$P93_PUSHES" "$P93_REFSPEC_PUSHES"
if [ "${P93_PUSHES:-0}" -ge 4 ]; then
  check protocol_93_push_sweep_not_vacuous yes yes
else
  check protocol_93_push_sweep_not_vacuous yes "only ${P93_PUSHES} push(es) found"
fi

audit_p93_blocks() {
  # audit_p93_blocks <file>: prints TOTAL= and MISSING= for the multi-command,
  # state-mutating blocks. Defined as a function so the markdown fence backticks
  # inside the python are parsed once here, not inside a command substitution.
  python3 - "$1" <<'PYP93'
import pathlib
import sys

text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
blocks, block, inside = [], [], False
for line in text.splitlines():
    if line.strip().startswith("```"):
        if inside:
            blocks.append(block)
        block, inside = [], not inside
        continue
    if inside:
        block.append(line)
total = missing = 0
for block in blocks:
    body = "\n".join(block)
    if "FIX_BRANCH" not in body and "LOCAL_SHA" not in body:
        continue
    total += 1
    if not block or block[0].strip() != "set -euo pipefail":
        missing += 1
print(f"TOTAL={total}")
print(f"MISSING={missing}")
PYP93
}

P93_BLOCK_REPORT="$(audit_p93_blocks "$P93")"
check protocol_93_blocks_set_shell_options "0" "$(printf '%s\n' "$P93_BLOCK_REPORT" | awk -F= '/^MISSING=/{print $2; exit}')"
P93_BLOCK_TOTAL="$(printf '%s\n' "$P93_BLOCK_REPORT" | awk -F= '/^TOTAL=/{print $2; exit}')"
if [ "${P93_BLOCK_TOTAL:-0}" -ge 4 ]; then
  check protocol_93_block_sweep_not_vacuous yes yes
else
  check protocol_93_block_sweep_not_vacuous yes "only ${P93_BLOCK_TOTAL} block(s) found"
fi

# Every push in protocol 93 must handle its own failure, retries included: under
# `set -e` a bare failure aborts before the stop that was supposed to report it.
P93_UNGUARDED="$(grep -nE '^[[:space:]]*git push' "$P93" || true)"  # workflow-shell-guard: allow SH001 - grep exits 1 when every push is guarded, which is the passing state
check protocol_93_every_push_handles_failure "" "$P93_UNGUARDED"

# ...and each fixer push must confirm the checkout is on the PR's own head
# branch before pushing, not only that the refspec is self-consistent.
# Count the guards by their distinguishing message rather than by a variable
# name: the initial and retry guards use different variables, and a rename
# should not silently drop one of them from this audit.
P93_HEAD_GUARDS="$(grep -c "head branch is" "$P93" || true)"  # workflow-shell-guard: allow SH001 - grep exits 1 on zero matches, which this check reports
P93_PUSH_COUNT="$(grep -cE '^[[:space:]]*if ! git push' "$P93" || true)"  # workflow-shell-guard: allow SH001 - same zero-match case
check protocol_93_every_push_checks_pr_head_branch "$P93_PUSH_COUNT" "$P93_HEAD_GUARDS"
if [ "${P93_PUSH_COUNT:-0}" -ge 4 ]; then
  check protocol_93_head_guard_sweep_not_vacuous yes yes
else
  check protocol_93_head_guard_sweep_not_vacuous yes "only ${P93_PUSH_COUNT} guarded push(es)"
fi

# ...executed, not only asserted. Force the retry path (a stubbed `gh` reporting
# a remote head that differs from local) and then force the retry push to fail.
extract_p93_verification_block() {
  python3 - "$1" <<'PYP93VER'
import pathlib
import sys

text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
block, inside = [], False
for line in text.splitlines():
    if line.strip().startswith("```"):
        if inside:
            if any("retrying push" in row for row in block):
                print("\n".join(row[3:] if row.startswith("   ") else row for row in block))
                sys.exit(0)
            block, inside = [], False
        else:
            block, inside = [], True
        continue
    if inside:
        block.append(line)
PYP93VER
}

P93_VER_BLOCK="$(extract_p93_verification_block "$P93")"
if [ -n "$P93_VER_BLOCK" ]; then
  check p93_verification_block_extracted yes yes
else
  check p93_verification_block_extracted yes "no retry block found in $P93"
fi
P93_ROOT="$TMP_DIR/p93"
mkdir -p "$P93_ROOT/bin"
setup_repo "$P93_ROOT"
(
  cd "$P93_ROOT/repo"
  git checkout -q -b fix/1593-p93
  printf 'work\n' > work.txt
  git add work.txt
  git commit -q -m work
)
# A stubbed `gh` that answers both queries: the PR's head branch (so the
# checkout check agrees) and a head SHA that is not local HEAD (so the block
# enters its retry path). GH_STUB_BRANCH lets a later case disagree on purpose.
cat > "$P93_ROOT/bin/gh" <<'GH_STUB'
#!/usr/bin/env sh
case "$*" in
  *headRefName*) echo "${GH_STUB_BRANCH:-fix/1593-p93}" ;;
  *) echo 0000000000000000000000000000000000000000 ;;
esac
GH_STUB
chmod +x "$P93_ROOT/bin/gh"
printf '%s\n' "$P93_VER_BLOCK" | sed 's|<pr_number>|1700|g' > "$P93_ROOT/verify.sh"
git -C "$P93_ROOT/repo" remote set-url origin "$P93_ROOT/not-a-repo"
P93_RC=0
( cd "$P93_ROOT/repo" && PATH="$P93_ROOT/bin:$PATH" bash "$P93_ROOT/verify.sh" ) > "$TMP_DIR/last.out" 2>&1 || P93_RC=$?
check p93_retry_push_failure_stops 1 "$P93_RC"
if grep -q "push_verification_failed" "$TMP_DIR/last.out" && grep -q "retry" "$TMP_DIR/last.out"; then
  check p93_retry_push_failure_names_condition yes yes
else
  check p93_retry_push_failure_names_condition yes "$(cat "$TMP_DIR/last.out")"
fi

# The retry must also re-check the checkout: it runs after something already
# went wrong, which is exactly when the checkout may have moved. Make the stub
# report a different head branch and confirm it stops BEFORE pushing.
P93_RC2=0
( cd "$P93_ROOT/repo" && PATH="$P93_ROOT/bin:$PATH" GH_STUB_BRANCH=some/other-branch bash "$P93_ROOT/verify.sh" ) > "$TMP_DIR/last.out" 2>&1 || P93_RC2=$?
check p93_retry_wrong_checkout_stops 1 "$P93_RC2"
if grep -q "push_verification_failed" "$TMP_DIR/last.out" && grep -q "head branch is some/other-branch" "$TMP_DIR/last.out"; then
  check p93_retry_wrong_checkout_names_condition yes yes
else
  check p93_retry_wrong_checkout_names_condition yes "$(cat "$TMP_DIR/last.out")"
fi

# --- AC (issue #1515): architecture_decision escalation mirror audit --------
# audit_escalation_mirrors extends audit_stop_surfaces: that helper only
# discovers `stop_conditions:` surfaces and greps for `push_verification_failed`,
# so it cannot validate the canonical escalation page or detect a weakened
# mirror. This is a NEW, separate audit for issue #1515's escalation content
# requirement (axis decomposition, coverage verdicts, per-citation conformance
# declarations, and the requested decision scoped to open axes only).

_escalation_audit_file() {
  # _escalation_audit_file <file> <term1> [<term2> ...]
  # Prints one MISSING=<file>:<line>:<term> per required term not found inside
  # the file's architecture_decision anchor section (outside fenced code
  # blocks and HTML comments), or ANCHOR_MISSING=<file> when no line in the
  # file mentions `architecture_decision` at all (including an empty or
  # missing file). Matching is exact (case-sensitive, word-bounded).
  local file="$1"
  shift
  python3 - "$file" "$@" <<'PYEOF'
import re
import sys

path = sys.argv[1]
terms = sys.argv[2:]

ANCHOR_RE = re.compile(r'architecture_decision')
ATX_RE = re.compile(r'^(#{1,6})\s')

try:
    with open(path, 'r', encoding='utf-8', newline='') as fh:
        raw = fh.read()
except (FileNotFoundError, IsADirectoryError, OSError):
    raw = ""

if raw == "":
    print("ANCHOR_MISSING=" + path)
    sys.exit(0)

lines = raw.split('\n')
if lines and lines[-1] == '':
    lines = lines[:-1]
lines = [ln[:-1] if ln.endswith('\r') else ln for ln in lines]
n = len(lines)

in_fence = False
fence_char = ''
fence_len = 0
in_comment = False

line_excluded = [False] * n
line_visible = [None] * n
heading_level = [0] * n

for i in range(n):
    line = lines[i]
    stripped = line.strip()

    if not in_fence:
        open_m = re.match(r'^(`{3,}|~{3,})', stripped)
        if open_m and not in_comment:
            fence_char = open_m.group(1)[0]
            fence_len = len(open_m.group(1))
            in_fence = True
            line_excluded[i] = True
            continue
    else:
        close_m = re.match(r'^(' + re.escape(fence_char) + r'{' + str(fence_len) + r',})\s*$', stripped)
        line_excluded[i] = True
        if close_m:
            in_fence = False
        continue

    text = line
    if in_comment:
        end = text.find('-->')
        if end == -1:
            line_excluded[i] = True
            continue
        text = text[end + 3:]
        in_comment = False

    out = []
    pos = 0
    while True:
        start = text.find('<!--', pos)
        if start == -1:
            out.append(text[pos:])
            break
        out.append(text[pos:start])
        end = text.find('-->', start + 4)
        if end == -1:
            in_comment = True
            break
        pos = end + 3
    visible = ''.join(out)

    heading_m = ATX_RE.match(line)
    if heading_m:
        heading_level[i] = len(heading_m.group(1))

    line_visible[i] = visible

anchor_idx = None
for i in range(n):
    if line_excluded[i] or line_visible[i] is None:
        continue
    if ANCHOR_RE.search(line_visible[i]):
        anchor_idx = i
        break

if anchor_idx is None:
    print("ANCHOR_MISSING=" + path)
    sys.exit(0)

anchor_line_no = anchor_idx + 1

# The "section" is the enclosing heading's content, not merely a forward scan
# from the anchor line: a mirror file's required terms (the canonical link,
# the declaration vocabulary) routinely appear earlier in the same paragraph
# or bullet than the literal `architecture_decision` phrase itself. Using the
# nearest enclosing heading as the section start (rather than the anchor line)
# still excludes an out-of-section decoy under an unrelated heading, while
# correctly covering the whole bullet/paragraph the anchor lives in.
enclosing_heading_idx = None
enclosing_level = None
for i in range(anchor_idx, -1, -1):
    if heading_level[i] > 0:
        enclosing_heading_idx = i
        enclosing_level = heading_level[i]
        break

section_start = enclosing_heading_idx if enclosing_heading_idx is not None else 0

section_end = n
for i in range(anchor_idx + 1, n):
    if heading_level[i] > 0 and (enclosing_level is None or heading_level[i] <= enclosing_level):
        section_end = i
        break

# Join included lines with a single space so a multi-word term wrapped
# across a Markdown soft line break (e.g. "...`Not yet" / "implemented`...")
# still reads, and matches, the same way a human sees it rendered.
joined = ' '.join(
    line_visible[i].strip() for i in range(section_start, section_end)
    if not line_excluded[i] and line_visible[i] is not None
)
joined = re.sub(r'[ \t]+', ' ', joined)

found = set()
for term in terms:
    if re.search(r'(?<![A-Za-z0-9])' + re.escape(term) + r'(?![A-Za-z0-9])', joined):
        found.add(term)

for term in terms:
    if term not in found:
        print("MISSING=%s:%d:%s" % (path, anchor_line_no, term))
PYEOF
}

audit_escalation_mirrors() {
  # audit_escalation_mirrors <repo-root>
  # Prints COUNT=<n> then one MISSING=<file>:<line>:<term> or
  # ANCHOR_MISSING=<file> per violation, across the 21-file discovery scope:
  # the canonical page, Protocols 90/91/93, and the 17 lockstep mirrors.
  local repo_root="$1"
  local count=0
  local canonical_file vocab_file link_file
  canonical_file="docs/workflow/development-workflow/architecture-decision-escalation.md"
  local -a vocab_files
  vocab_files=(
    "docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md"
    "docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md"
    ".cursor/agents/developer.md"
    ".claude/agents/developer.md"
    ".codex/skills/workflow-implementer/SKILL.md"
    ".cursor/agents/code-reviewer.md"
    ".claude/agents/code-reviewer.md"
    ".codex/skills/workflow-code-reviewer/SKILL.md"
    ".cursor/agents/item-orchestrator.md"
    ".claude/agents/item-orchestrator.md"
    ".codex/skills/workflow-item-orchestrator/SKILL.md"
    ".agents/skills/run-item/SKILL.md"
  )
  local -a link_files
  link_files=(
    "docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md"
    ".cursor/agents/orchestrator.md"
    ".claude/agents/orchestrator.md"
    ".codex/skills/workflow-orchestrator/SKILL.md"
    ".cursor/agents/automated-reviewer-loop.md"
    ".claude/agents/automated-reviewer-loop.md"
    ".codex/skills/workflow-reviewer-loop/SKILL.md"
    ".agents/skills/run-items/SKILL.md"
  )

  count=$((count + 1))
  _escalation_audit_file "$repo_root/$canonical_file" "Recommendation" "Conforms" "Departs" "Not yet implemented"

  for vocab_file in "${vocab_files[@]}"; do
    count=$((count + 1))
    _escalation_audit_file "$repo_root/$vocab_file" "architecture-decision-escalation.md" "Conforms" "Departs" "Not yet implemented"
  done

  for link_file in "${link_files[@]}"; do
    count=$((count + 1))
    _escalation_audit_file "$repo_root/$link_file" "architecture-decision-escalation.md"
  done

  printf 'COUNT=%s\n' "$count"
}

ESCALATION_AUDIT="$(audit_escalation_mirrors "$REPO_ROOT")"
ESCALATION_MISSING="$(printf '%s\n' "$ESCALATION_AUDIT" | grep -E '^(MISSING|ANCHOR_MISSING)=' || true)"  # workflow-shell-guard: allow SH001 - grep exits 1 when nothing is missing, which is the passing state
ESCALATION_COUNT="$(printf '%s\n' "$ESCALATION_AUDIT" | awk -F= '/^COUNT=/{print $2; exit}')"
check escalation_mirrors_well_formed "" "$ESCALATION_MISSING"
check escalation_mirror_discovery_not_vacuous 21 "$ESCALATION_COUNT"

# Planted violation 1: delete the canonical link from a required mirror.
ESCALATION_PLANT_ROOT="$TMP_DIR/escalation-mirrors"
mkdir -p "$ESCALATION_PLANT_ROOT/.claude/agents" "$ESCALATION_PLANT_ROOT/.codex/skills/workflow-code-reviewer"
cp "$REPO_ROOT/.claude/agents/code-reviewer.md" "$ESCALATION_PLANT_ROOT/.claude/agents/code-reviewer.md"
cp "$REPO_ROOT/.codex/skills/workflow-code-reviewer/SKILL.md" "$ESCALATION_PLANT_ROOT/.codex/skills/workflow-code-reviewer/SKILL.md"
CODE_REVIEWER_CLAUDE="$ESCALATION_PLANT_ROOT/.claude/agents/code-reviewer.md"
python3 - "$CODE_REVIEWER_CLAUDE" <<'PYPLANTLINK'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
old = """When replying to a review thread and citing a workflow specification line as
support for the current behavior or a decision the reviewer will weigh,
attach the conformance declaration (`Conforms` / `Departs` / `Not yet
implemented`, or a plain undetermined statement) required by
`docs/workflow/development-workflow/architecture-decision-escalation.md`.
Where a finding would lead to a full `architecture_decision` escalation, point
to Protocol 91 and that canonical page rather than a lighter requirement.
"""
new = """When replying to a review thread and citing a workflow specification line as
support for the current behavior or a decision the reviewer will weigh,
attach the conformance declaration (`Conforms` / `Departs` / `Not yet
implemented`, or a plain undetermined statement) — this is an
`architecture_decision`-adjacent requirement.
"""
if old not in text:
    sys.exit("plant target not found")
path.write_text(text.replace(old, new, 1), encoding="utf-8")
PYPLANTLINK
CODE_REVIEWER_HEADING_LINE="$(grep -n 'architecture_decision' "$CODE_REVIEWER_CLAUDE" | head -1 | cut -d: -f1 || true)"  # workflow-shell-guard: allow SH001 - grep is expected to match here; guarded defensively
PLANT_LINK_AUDIT="$(_escalation_audit_file "$CODE_REVIEWER_CLAUDE" "architecture-decision-escalation.md" "Conforms" "Departs" "Not yet implemented")"
check plant_deleted_link_is_reported \
  "MISSING=$CODE_REVIEWER_CLAUDE:$CODE_REVIEWER_HEADING_LINE:architecture-decision-escalation.md" \
  "$(printf '%s\n' "$PLANT_LINK_AUDIT" | grep '^MISSING=' || true)"
RESTORED_LINK_AUDIT="$(_escalation_audit_file "$REPO_ROOT/.claude/agents/code-reviewer.md" "architecture-decision-escalation.md" "Conforms" "Departs" "Not yet implemented")"
check plant_restored_link_passes "" "$(printf '%s\n' "$RESTORED_LINK_AUDIT" | grep '^MISSING=' || true)"

# Planted violation 2: weaken the declaration vocabulary in a Codex mirror.
CODE_REVIEWER_CODEX="$ESCALATION_PLANT_ROOT/.codex/skills/workflow-code-reviewer/SKILL.md"
python3 - "$CODE_REVIEWER_CODEX" <<'PYPLANTVOCAB'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
old = ("attach the conformance declaration (`Conforms` / `Departs` / `Not\n"
       "    yet implemented`, or a plain undetermined statement) required by")
new = "attach a conformance declaration, as applicable, required by"
if old not in text:
    sys.exit("plant target not found")
path.write_text(text.replace(old, new, 1), encoding="utf-8")
PYPLANTVOCAB
PLANT_VOCAB_AUDIT="$(_escalation_audit_file "$CODE_REVIEWER_CODEX" "architecture-decision-escalation.md" "Conforms" "Departs" "Not yet implemented")"
PLANT_VOCAB_MISSING="$(printf '%s\n' "$PLANT_VOCAB_AUDIT" | grep '^MISSING=' || true)"  # workflow-shell-guard: allow SH001 - grep exits 1 only if nothing is missing, which this plant must not produce
check plant_weakened_vocab_reports_conforms 1 "$(printf '%s\n' "$PLANT_VOCAB_MISSING" | grep -c ":Conforms$" || true)"
check plant_weakened_vocab_reports_departs 1 "$(printf '%s\n' "$PLANT_VOCAB_MISSING" | grep -c ":Departs$" || true)"

# --- Parser-risk edge cases (protocol 02 Step 3 rules apply to this audit) --
ESCALATION_FIXTURE_DIR="$TMP_DIR/escalation-fixtures"
mkdir -p "$ESCALATION_FIXTURE_DIR"

write_fixture() {
  # write_fixture <name> <<'EOF' ... EOF
  local name="$1"
  cat > "$ESCALATION_FIXTURE_DIR/$name"
}

# 1. Term present only outside the escalation section (out-of-section decoy).
write_fixture case1.md <<'EOF'
Conforms mentioned here, before any escalation section exists.

## architecture_decision escalation

Nothing required lives here.
EOF
CASE1_AUDIT="$(_escalation_audit_file "$ESCALATION_FIXTURE_DIR/case1.md" "Conforms")"
check case1_out_of_section_decoy_reported 1 "$(printf '%s\n' "$CASE1_AUDIT" | grep -c '^MISSING=.*:Conforms$')"

# 2. Escalation heading absent.
write_fixture case2.md <<'EOF'
## Some unrelated heading

Nothing here mentions the trigger condition at all.
EOF
CASE2_AUDIT="$(_escalation_audit_file "$ESCALATION_FIXTURE_DIR/case2.md" "Conforms")"
check case2_anchor_missing "ANCHOR_MISSING=$ESCALATION_FIXTURE_DIR/case2.md" "$CASE2_AUDIT"

# 3. Term only inside a fenced code block within the section.
write_fixture case3.md <<'EOF'
## architecture_decision escalation

```text
Conforms
```
EOF
CASE3_AUDIT="$(_escalation_audit_file "$ESCALATION_FIXTURE_DIR/case3.md" "Conforms")"
check case3_fenced_term_reported 1 "$(printf '%s\n' "$CASE3_AUDIT" | grep -c '^MISSING=.*:Conforms$')"

# 4. Term only inside an HTML comment within the section.
write_fixture case4.md <<'EOF'
## architecture_decision escalation

<!-- Conforms -->
EOF
CASE4_AUDIT="$(_escalation_audit_file "$ESCALATION_FIXTURE_DIR/case4.md" "Conforms")"
check case4_comment_term_reported 1 "$(printf '%s\n' "$CASE4_AUDIT" | grep -c '^MISSING=.*:Conforms$')"

# 5. Two escalation headings — the first is scoped; a term only under the
#    second is reported.
write_fixture case5.md <<'EOF'
## architecture_decision escalation

First section names only Departs, never the other declaration term.

## architecture_decision escalation (second)

Conforms appears only here.
EOF
CASE5_AUDIT="$(_escalation_audit_file "$ESCALATION_FIXTURE_DIR/case5.md" "Conforms")"
check case5_second_heading_not_scoped 1 "$(printf '%s\n' "$CASE5_AUDIT" | grep -c '^MISSING=.*:Conforms$')"

# 6. Term with different case ("conforms") does not satisfy "Conforms".
write_fixture case6.md <<'EOF'
## architecture_decision escalation

conforms, lowercase, is not the same term.
EOF
CASE6_AUDIT="$(_escalation_audit_file "$ESCALATION_FIXTURE_DIR/case6.md" "Conforms")"
check case6_case_mismatch_reported 1 "$(printf '%s\n' "$CASE6_AUDIT" | grep -c '^MISSING=.*:Conforms$')"

# 7. CRLF line endings — a correct file still passes; line number unchanged.
printf '## architecture_decision escalation\r\n\r\nConforms is present here.\r\n' > "$ESCALATION_FIXTURE_DIR/case7.md"
CASE7_AUDIT="$(_escalation_audit_file "$ESCALATION_FIXTURE_DIR/case7.md" "Conforms")"
check case7_crlf_passes "" "$(printf '%s\n' "$CASE7_AUDIT" | grep '^MISSING=' || true)"

# 8. Empty file and deleted (missing) file — reported, not silently skipped.
: > "$ESCALATION_FIXTURE_DIR/case8-empty.md"
CASE8_EMPTY_AUDIT="$(_escalation_audit_file "$ESCALATION_FIXTURE_DIR/case8-empty.md" "Conforms")"
check case8_empty_file_reported "ANCHOR_MISSING=$ESCALATION_FIXTURE_DIR/case8-empty.md" "$CASE8_EMPTY_AUDIT"
CASE8_DELETED_AUDIT="$(_escalation_audit_file "$ESCALATION_FIXTURE_DIR/case8-does-not-exist.md" "Conforms")"
check case8_deleted_file_reported "ANCHOR_MISSING=$ESCALATION_FIXTURE_DIR/case8-does-not-exist.md" "$CASE8_DELETED_AUDIT"

# 9. Term twice on one line (in-section decoy + required rule) counted once;
#    a term only in a trailing decoy after an HTML comment opener is reported.
write_fixture case9.md <<'EOF'
## architecture_decision escalation

Conforms is required here, and Conforms is restated for emphasis.

Trailing decoy: <!-- opens here and Departs never closes on this line
EOF
CASE9_AUDIT="$(_escalation_audit_file "$ESCALATION_FIXTURE_DIR/case9.md" "Conforms" "Departs")"
check case9_repeated_term_counted_once "" "$(printf '%s\n' "$CASE9_AUDIT" | grep '^MISSING=.*:Conforms$' || true)"
check case9_trailing_comment_decoy_reported 1 "$(printf '%s\n' "$CASE9_AUDIT" | grep -c '^MISSING=.*:Departs$')"

# 10. Boundary characters: punctuation/backtick-adjacent terms match; a term
#     embedded in a longer word does not.
write_fixture case10.md <<'EOF'
## architecture_decision escalation

The word Nonconformsx should never satisfy the required declaration term.
The declaration is `Departs`, and separately **Not yet implemented** is shown.
EOF
CASE10_AUDIT="$(_escalation_audit_file "$ESCALATION_FIXTURE_DIR/case10.md" "Conforms" "Departs" "Not yet implemented")"
check case10_boundary_punctuation_matches "" "$(printf '%s\n' "$CASE10_AUDIT" | grep -E '^MISSING=.*:(Departs|Not yet implemented)$' || true)"
check case10_embedded_word_reported 1 "$(printf '%s\n' "$CASE10_AUDIT" | grep -c '^MISSING=.*:Conforms$')"

# 11. Nested constructs: a fenced block inside a list item, and an HTML
#     comment inside a fenced block — scoping stays correct in both.
write_fixture case11.md <<'EOF'
## architecture_decision escalation

- A list item with a nested fence:

  ```text
  <!-- Conforms -->
  ```

Departs is stated in normal prose outside any fence or comment.
EOF
CASE11_AUDIT="$(_escalation_audit_file "$ESCALATION_FIXTURE_DIR/case11.md" "Conforms" "Departs")"
check case11_nested_fence_comment_excluded 1 "$(printf '%s\n' "$CASE11_AUDIT" | grep -c '^MISSING=.*:Conforms$')"
check case11_prose_outside_nesting_found "" "$(printf '%s\n' "$CASE11_AUDIT" | grep '^MISSING=.*:Departs$' || true)"

# 12. CommonMark fence flexibility: closing fence longer than opener, a tilde
#     fence, and an unterminated fence (runs to end of file).
write_fixture case12.md <<'EOF'
## architecture_decision escalation

```text
Conforms
````

~~~text
Departs
~~~

The next fence never closes, and only its body carries the target phrase:
```text
Not yet implemented
EOF
CASE12_AUDIT="$(_escalation_audit_file "$ESCALATION_FIXTURE_DIR/case12.md" "Conforms" "Departs" "Not yet implemented")"
check case12_longer_closing_fence_excluded 1 "$(printf '%s\n' "$CASE12_AUDIT" | grep -c '^MISSING=.*:Conforms$')"
check case12_tilde_fence_excluded 1 "$(printf '%s\n' "$CASE12_AUDIT" | grep -c '^MISSING=.*:Departs$')"
check case12_unterminated_fence_excluded 1 "$(printf '%s\n' "$CASE12_AUDIT" | grep -c '^MISSING=.*:Not yet implemented$')"

# 13. Correct file — no MISSING= / ANCHOR_MISSING= lines, only a clean result,
#     asserted after each planted case above is restored (the audits against
#     $REPO_ROOT files throughout this block always read the real, unmodified
#     tree — only the $ESCALATION_PLANT_ROOT / $ESCALATION_FIXTURE_DIR copies
#     were mutated).
write_fixture case13.md <<'EOF'
## architecture_decision escalation

Conforms, Departs, and Not yet implemented are all present in-section.
EOF
CASE13_AUDIT="$(_escalation_audit_file "$ESCALATION_FIXTURE_DIR/case13.md" "Conforms" "Departs" "Not yet implemented")"
check case13_correct_file_passes "" "$(printf '%s\n' "$CASE13_AUDIT" | grep -E '^(MISSING|ANCHOR_MISSING)=' || true)"
FINAL_ESCALATION_AUDIT="$(audit_escalation_mirrors "$REPO_ROOT")"
check escalation_mirrors_still_clean_after_fixtures "" "$(printf '%s\n' "$FINAL_ESCALATION_AUDIT" | grep -E '^(MISSING|ANCHOR_MISSING)=' || true)"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
