#!/usr/bin/env bash
# test-worktree-recipe.sh — the documented worktree recipes must not leave a
# branch tracking the integration branch (issue #1593).
# covers: docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md
# covers: docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md
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
# Case C branches from its own remote branch, where tracking is correct.
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
DEVELOP_AFTER="$(git -C "$ROOT_DOC/repo" rev-parse origin/develop)"
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

# --- AC-2 / AC-3: every documented branch push ------------------------------
# Each protocol that pushes an item branch must push with an explicit refspec
# and then compare the remote head to local. Checked by extraction, so a
# protocol that drops either half fails here.
PROTOCOL_DIR="$REPO_ROOT/docs/workflow/development-workflow/protocols"
check_push_step() {
  # check_push_step <protocol-file> <branch-placeholder> <label>
  local file="$1" branch="$2" label="$3" name
  name="$(basename "$file" .md)_${label}"
  if grep -Fq "git push origin \"${branch}:${branch}\"" "$file"; then
    check "push_refspec_${name}" yes yes
  else
    check "push_refspec_${name}" yes "no refspec for ${branch}"
  fi
  if grep -Fq "git ls-remote origin \"refs/heads/${branch}\"" "$file"; then
    check "push_verified_${name}" yes yes
  else
    check "push_verified_${name}" yes "no remote-head comparison for ${branch}"
  fi
}
check_push_step "$PROTOCOL_DIR/01-generate-spec-protocol.md" 'spec/[branch-slug]' spec
check_push_step "$PROTOCOL_DIR/02-generate-implementation-plan-protocol.md" 'implementation-plan/[branch-slug]' plan
check_push_step "$PROTOCOL_DIR/03-implement-development-protocol.md" 'feature/[slug]' feature
check_push_step "$PROTOCOL_DIR/03-implement-development-protocol.md" 'fix/[branch-slug]' fix
check_push_step "$PROTOCOL_DIR/03-implement-development-protocol.md" 'hotfix/[branch-slug]' hotfix

# Each of those protocols must also carry the non-zero exit that makes the
# comparison a gate rather than an echo.
for push_protocol in 01-generate-spec-protocol 02-generate-implementation-plan-protocol 03-implement-development-protocol; do
  if grep -Fq 'if [ "$LOCAL_SHA" != "$REMOTE_SHA" ]; then' "$PROTOCOL_DIR/${push_protocol}.md"; then
    check "push_exit_gate_${push_protocol}" yes yes
  else
    check "push_exit_gate_${push_protocol}" yes no
  fi
done

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
# The sweep must have found the five documented item pushes, or it passes
# vacuously — the same failure mode #1658 exists to remove.
if [ "$ITEM_PUSH_COUNT" -ge 5 ]; then
  check item_push_sweep_not_vacuous yes yes
else
  check item_push_sweep_not_vacuous yes "only ${ITEM_PUSH_COUNT} item push(es) found"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
