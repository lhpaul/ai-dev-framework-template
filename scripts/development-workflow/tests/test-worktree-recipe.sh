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
  local file="$1" branch="$2" label="$3" name block
  name="$(basename "$file" .md)_${label}"
  block="$(extract_push_block "$file" "$branch")"
  if [ -z "$block" ]; then
    check "push_refspec_${name}" yes "no refspec block for ${branch}"
    check "push_verified_${name}" yes "no refspec block for ${branch}"
    check "push_exit_gate_${name}" yes "no refspec block for ${branch}"
    return 0
  fi
  check "push_refspec_${name}" yes yes
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
# `set -euo pipefail` must be the FIRST line of the fence, so a failed `git add`
# or `git commit` cannot fall through and push an older HEAD.
PUSH_BLOCK_RAW="$(extract_push_block "$PROTOCOL_DIR/03-implement-development-protocol.md" 'fix/[branch-slug]')"
if [ "$(printf '%s\n' "$PUSH_BLOCK_RAW" | sed -n '1p')" = "set -euo pipefail" ]; then
  check push_block_sets_shell_options_first yes yes
else
  check push_block_sets_shell_options_first yes "first line is: $(printf '%s\n' "$PUSH_BLOCK_RAW" | sed -n '1p')"
fi
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

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
