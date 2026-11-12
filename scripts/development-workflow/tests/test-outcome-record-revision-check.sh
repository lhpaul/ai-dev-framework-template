#!/usr/bin/env bash
# test-outcome-record-revision-check.sh - disposable Git coverage for the
# plan-authoring rigor outcome record's one-push stamp lag (#1820).
#
# Acceptance cases from #1820:
#   - a push that only updates the record's stamp (or carries no change at all)
#     after the stamped revision is current, so no failed_for_head deadlock;
#   - a stamp older than one push, or one with substantive changes since the
#     stamped revision, still fails.
#
# covers: scripts/development-workflow/outcome-record-revision-check.sh
# covers: docs/workflow/development-workflow/plan-authoring-rigor-rules.md

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"
CHECK="$REPO_ROOT/scripts/development-workflow/outcome-record-revision-check.sh"
CANON="$REPO_ROOT/docs/workflow/development-workflow/plan-authoring-rigor-rules.md"
TMP_ROOT="$(mktemp -d)"
PASS_COUNT=0
FAIL_COUNT=0

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

run_test() {
  local name="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    printf 'PASS: %s\n' "$name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    printf "FAIL: %s - expected '%s', got '%s'\n" "$name" "$expected" "$actual"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

# check_result <stated> <head> -> "<exit>|<RESULT>|<REASON>"
check_result() {
  local status output result reason
  set +e
  output="$("$CHECK" --repo-root "$REPO" --stated "$1" --head "$2" 2>&1)"
  status=$?
  set -e
  result="$(printf '%s\n' "$output" | sed -n 's/^RESULT=//p')"
  reason="$(printf '%s\n' "$output" | sed -n 's/^REASON=//p')"
  printf '%s|%s|%s\n' "$status" "$result" "$reason"
}

git_q() {
  git -C "$REPO" "$@" >/dev/null
}

commit_all() {
  git_q add -A
  git_q commit -q --allow-empty -m "$1"
  git -C "$REPO" rev-parse HEAD
}

# Hermetic: ignore the caller's global and system git configuration.
export GIT_CONFIG_GLOBAL="$TMP_ROOT/global.gitconfig" GIT_CONFIG_NOSYSTEM=1
: > "$GIT_CONFIG_GLOBAL"

REPO="$TMP_ROOT/repo"
mkdir -p "$REPO"
git_q init -q
git_q config user.email "fixture@example.invalid"
git_q config user.name "Fixture"
git_q config commit.gpgsign false
git_q config core.hooksPath /dev/null

PLAN="$REPO/plan.md"
cat > "$PLAN" <<'EOF'
# Plan

Body of the plan.

## Document Quality Gate

Plan revision: `0000000` (live PR head at time of writing)

| Rule | Outcome |
| --- | --- |
| Rule 1 | Not applicable |
EOF
BASE_SHA="$(commit_all "plan: initial")"

printf '\nA substantive plan paragraph.\n' >> "$PLAN"
FIX_SHA="$(commit_all "plan: substantive fix")"
FIX_SHORT="$(git -C "$REPO" rev-parse --short=8 "$FIX_SHA")"

# --- Same head --------------------------------------------------------------
run_test "stated equals head is current" \
  "0|current|same_head" "$(check_result "$FIX_SHORT" "$FIX_SHA")"
run_test "backtick-quoted stated SHA is accepted" \
  "0|current|same_head" "$(check_result "\`$FIX_SHORT\`" "$FIX_SHA")"

# --- One-push stamp lag: empty push after a PR-body stamp update ------------
EMPTY_SHA="$(commit_all "chore: fresh head after body stamp update")"
run_test "empty push after the stamped revision is current (no failed_for_head)" \
  "0|current|stamp_lag_no_change" "$(check_result "$FIX_SHORT" "$EMPTY_SHA")"

# --- One-push stamp lag: commit that only rewrites the committed stamp -------
sed "s/^Plan revision: \`0000000\`/Plan revision: \`$FIX_SHORT\`/" "$PLAN" > "$PLAN.tmp"
mv "$PLAN.tmp" "$PLAN"
git_q reset -q --soft "$FIX_SHA"
STAMP_SHA="$(commit_all "docs: stamp outcome record revision")"
run_test "stamp-only push after the stamped revision is current" \
  "0|current|stamp_lag_stamp_only" "$(check_result "$FIX_SHORT" "$STAMP_SHA")"

# --- Older than one push -----------------------------------------------------
run_test "stamp two pushes behind the head fails" \
  "1|not_current|more_than_one_push" "$(check_result "$BASE_SHA" "$STAMP_SHA")"
NEXT_EMPTY_SHA="$(commit_all "chore: second empty push")"
run_test "stamp-only push followed by another push fails" \
  "1|not_current|more_than_one_push" "$(check_result "$FIX_SHORT" "$NEXT_EMPTY_SHA")"

# --- Substantive change since the stamped revision ----------------------------
git_q reset -q --hard "$FIX_SHA"
printf '\nAnother substantive paragraph.\n' >> "$PLAN"
SUBST_SHA="$(commit_all "plan: substantive change")"
run_test "substantive change in the push after the stamp fails" \
  "1|not_current|substantive_change" "$(check_result "$FIX_SHORT" "$SUBST_SHA")"

git_q reset -q --hard "$FIX_SHA"
sed "s/^Plan revision: \`0000000\`/Plan revision: \`$FIX_SHORT\`/" "$PLAN" > "$PLAN.tmp"
mv "$PLAN.tmp" "$PLAN"
printf '\nSmuggled claim alongside the stamp.\n' >> "$PLAN"
MIXED_SHA="$(commit_all "docs: stamp plus a claim")"
run_test "stamp update bundled with a substantive change fails" \
  "1|not_current|substantive_change" "$(check_result "$FIX_SHORT" "$MIXED_SHA")"

git_q reset -q --hard "$FIX_SHA"
sed "s/^Plan revision: \`0000000\` (live PR head at time of writing)/Plan revision: \`$FIX_SHORT\` (and Rule 1 is now Satisfied)/" "$PLAN" > "$PLAN.tmp"
mv "$PLAN.tmp" "$PLAN"
REWORD_SHA="$(commit_all "docs: stamp line with new wording")"
run_test "stamp line whose non-SHA text changes fails" \
  "1|not_current|substantive_change" "$(check_result "$FIX_SHORT" "$REWORD_SHA")"

git_q reset -q --hard "$FIX_SHA"
sed "s/^Plan revision: \`0000000\` (live PR head at time of writing)/Plan revision: \`0000000\` (evidence at cafe1234)/" "$PLAN" > "$PLAN.tmp"
mv "$PLAN.tmp" "$PLAN"
SECOND_HEX_BASE="$(commit_all "docs: stamp line cites another revision")"
SECOND_HEX_BASE_SHORT="$(git -C "$REPO" rev-parse --short=8 "$SECOND_HEX_BASE")"
sed "s/^Plan revision: \`0000000\` (evidence at cafe1234)/Plan revision: \`$SECOND_HEX_BASE_SHORT\` (evidence at beef5678)/" "$PLAN" > "$PLAN.tmp"
mv "$PLAN.tmp" "$PLAN"
SECOND_HEX_SHA="$(commit_all "docs: stamp plus a changed second revision")"
run_test "second hex token changed on the stamp line fails" \
  "1|not_current|substantive_change" "$(check_result "$SECOND_HEX_BASE_SHORT" "$SECOND_HEX_SHA")"
git_q reset -q --hard "$SECOND_HEX_BASE"
sed "s/^Plan revision: \`0000000\` (evidence at cafe1234)/Plan revision: \`$SECOND_HEX_BASE_SHORT\` (evidence at cafe1234)/" "$PLAN" > "$PLAN.tmp"
mv "$PLAN.tmp" "$PLAN"
SECOND_HEX_OK_SHA="$(commit_all "docs: stamp only, second revision unchanged")"
run_test "stamp-only change keeps an unchanged second hex token current" \
  "0|current|stamp_lag_stamp_only" "$(check_result "$SECOND_HEX_BASE_SHORT" "$SECOND_HEX_OK_SHA")"

git_q reset -q --hard "$FIX_SHA"
printf 'new file\n' > "$REPO/extra.md"
ADD_SHA="$(commit_all "docs: add a file")"
run_test "added file after the stamped revision fails" \
  "1|not_current|structural_change" "$(check_result "$FIX_SHORT" "$ADD_SHA")"

git_q reset -q --hard "$FIX_SHA"
chmod +x "$PLAN"
MODE_SHA="$(commit_all "docs: mode change")"
run_test "mode change after the stamped revision fails" \
  "1|not_current|structural_change" "$(check_result "$FIX_SHORT" "$MODE_SHA")"
chmod -x "$PLAN"

# A deleted line whose content is "-- x" renders as "--- x" and must not be
# mistaken for a file header.
git_q reset -q --hard "$FIX_SHA"
printf -- '-- dashed note\n' >> "$PLAN"
DASH_BASE_SHA="$(commit_all "plan: dashed note")"
sed "s/^Plan revision: \`0000000\`/Plan revision: \`$FIX_SHORT\`/" "$PLAN" | grep -v '^-- dashed note$' > "$PLAN.tmp"
mv "$PLAN.tmp" "$PLAN"
DASH_SHA="$(commit_all "docs: stamp plus deleted dashed line")"
run_test "stamp bundled with a deleted '-- x' line fails" \
  "1|not_current|substantive_change" "$(check_result "$DASH_BASE_SHA" "$DASH_SHA")"

# diff.noprefix must not change the verdict for a stamp-only push.
git_q reset -q --hard "$FIX_SHA"
sed "s/^Plan revision: \`0000000\`/Plan revision: \`$FIX_SHORT\`/" "$PLAN" > "$PLAN.tmp"
mv "$PLAN.tmp" "$PLAN"
NOPFX_SHA="$(commit_all "docs: stamp again")"
git_q config diff.noprefix true
run_test "stamp-only push is current under diff.noprefix" \
  "0|current|stamp_lag_stamp_only" "$(check_result "$FIX_SHORT" "$NOPFX_SHA")"
git_q config --unset diff.noprefix

# --- Merge head ---------------------------------------------------------------
git_q reset -q --hard "$FIX_SHA"
git_q checkout -q -b side "$BASE_SHA"
printf 'side\n' > "$REPO/side.md"
SIDE_SHA="$(commit_all "side")"
git_q checkout -q -
git_q merge -q --no-edit --no-ff "$SIDE_SHA"
MERGE_SHA="$(git -C "$REPO" rev-parse HEAD)"
run_test "merge commit head fails even when a parent is stamped" \
  "1|not_current|merge_head" "$(check_result "$FIX_SHORT" "$MERGE_SHA")"

# --- Stamp formatting variants stay stamp-only -------------------------------
for variant in nospace boldcode; do
  git_q reset -q --hard "$FIX_SHA"
  case "$variant" in
    nospace) fmt_old='Plan revision:`0000000`'; fmt_new="Plan revision:\`$FIX_SHORT\`" ;;
    boldcode) fmt_old='Plan revision: **`0000000`**'; fmt_new="Plan revision: **\`$FIX_SHORT\`**" ;;
  esac
  sed "s/^Plan revision: \`0000000\` (live PR head at time of writing)/$fmt_old (live PR head at time of writing)/" "$PLAN" > "$PLAN.tmp"
  mv "$PLAN.tmp" "$PLAN"
  variant_base="$(commit_all "docs: $variant stamp format")"
  variant_base_short="$(git -C "$REPO" rev-parse --short=8 "$variant_base")"
  fmt_new="${fmt_new//$FIX_SHORT/$variant_base_short}"
  awk -v old="$fmt_old" -v new="$fmt_new" 'index($0, old) == 1 { $0 = new substr($0, length(old) + 1) } { print }' "$PLAN" > "$PLAN.tmp"
  mv "$PLAN.tmp" "$PLAN"
  variant_head="$(commit_all "docs: $variant stamp update")"
  run_test "stamp-only update in $variant format is current" \
    "0|current|stamp_lag_stamp_only" "$(check_result "$variant_base_short" "$variant_head")"
done

# --- diff.relative must not hide changes outside --repo-root ----------------
# With diff.relative=true, git diff run from a subdirectory only reports paths
# under it; the substantive change to plan.md (repo root) must still count.
mkdir -p "$REPO/sub"
git_q config diff.relative true
set +e
relative_output="$("$CHECK" --repo-root "$REPO/sub" --stated "$FIX_SHORT" --head "$SUBST_SHA" 2>&1)"
relative_status=$?
set -e
git_q config --unset diff.relative
run_test "diff.relative from a subdirectory does not hide a substantive change" \
  "1|not_current|substantive_change" \
  "$relative_status|$(printf '%s\n' "$relative_output" | sed -n 's/^RESULT=//p')|$(printf '%s\n' "$relative_output" | sed -n 's/^REASON=//p')"

# --- diff.ignoreSubmodules must not hide a moved submodule pointer -----------
git_q reset -q --hard "$FIX_SHA"
git_q update-index --add --cacheinfo "160000,$BASE_SHA,mod"
# Commit directly: commit_all's `add -A` would drop a gitlink with no checkout.
git_q commit -q -m "chore: add gitlink"
GITLINK_BASE="$(git -C "$REPO" rev-parse HEAD)"
GITLINK_BASE_SHORT="$(git -C "$REPO" rev-parse --short=8 "$GITLINK_BASE")"
git_q update-index --cacheinfo "160000,$FIX_SHA,mod"
git_q commit -q -m "chore: move gitlink"
GITLINK_MOVED="$(git -C "$REPO" rev-parse HEAD)"
git_q config diff.ignoreSubmodules all
run_test "diff.ignoreSubmodules=all does not hide a moved submodule pointer" \
  "1|not_current|substantive_change" "$(check_result "$GITLINK_BASE_SHORT" "$GITLINK_MOVED")"
git_q config --unset diff.ignoreSubmodules

# --- Missing, malformed, unresolved, off-branch ---------------------------------
run_test "missing stated revision fails" \
  "1|not_current|missing" "$(check_result "" "$FIX_SHA")"
run_test "malformed stated revision fails" \
  "1|not_current|malformed" "$(check_result "live-head" "$FIX_SHA")"
malformed_output="$("$CHECK" --repo-root "$REPO" --stated "live-head" --head "$FIX_SHA" 2>&1 || true)"
run_test "malformed stated revision is echoed in STATED" \
  "live-head" "$(printf '%s\n' "$malformed_output" | sed -n 's/^STATED=//p')"
FIX_FULL_HEAD="$(printf '%s' "$FIX_SHA" | cut -c1-20)"
FIX_FULL_TAIL="$(printf '%s' "$FIX_SHA" | cut -c21-40)"
run_test "stated SHA split by inner whitespace is malformed" \
  "1|not_current|malformed" "$(check_result "$FIX_FULL_HEAD $FIX_FULL_TAIL" "$FIX_SHA")"
run_test "stated SHA split by an inner backtick is malformed" \
  "1|not_current|malformed" "$(check_result "$FIX_FULL_HEAD\`$FIX_FULL_TAIL" "$FIX_SHA")"
run_test "stated SHA wrapped across lines is malformed" \
  "1|not_current|malformed" "$(check_result "$FIX_FULL_HEAD
$FIX_FULL_TAIL" "$FIX_SHA")"
multiline_output="$("$CHECK" --repo-root "$REPO" --stated "$FIX_SHORT
RESULT=current" --head "$FIX_SHA" 2>&1 || true)"
run_test "multi-line stated value cannot inject output records" \
  "1" "$(printf '%s\n' "$multiline_output" | grep -c '^RESULT=')"
run_test "padded code span around the SHA is accepted" \
  "0|current|same_head" "$(check_result " \` $FIX_SHORT \` " "$FIX_SHA")"
run_test "SHA longer than 40 hex characters is malformed" \
  "1|not_current|malformed" "$(check_result "${FIX_SHA}0" "$FIX_SHA")"
run_test "nonexistent stated revision fails" \
  "1|not_current|unresolved" "$(check_result "deadbeefdeadbeef" "$FIX_SHA")"
run_test "stated revision not on the head's branch fails" \
  "1|not_current|not_on_branch" "$(check_result "$SIDE_SHA" "$FIX_SHA")"

# --- Usage errors ---------------------------------------------------------------
set +e
"$CHECK" --repo-root "$REPO" --stated "$FIX_SHORT" >/dev/null 2>&1
missing_head_status=$?
"$CHECK" --repo-root "$REPO" --stated "$FIX_SHORT" --head no-such-ref >/dev/null 2>&1
bad_head_status=$?
set -e
run_test "missing --head is a usage error" "2" "$missing_head_status"
run_test "unresolvable head is a tooling error" "2" "$bad_head_status"

# --- Canonical rule carries the bounded allowance ----------------------------
canon_has() {
  if grep -Fq -- "$1" "$CANON"; then printf 'yes\n'; else printf 'no\n'; fi
}
run_test "canonical rule defines the stated-revision currency section" \
  "yes" "$(canon_has "### When the outcome record's stated revision is current")"
run_test "canonical rule bounds the lag to the head's only parent" \
  "yes" "$(canon_has "a non-merge commit whose only parent is the stated revision")"
run_test "canonical rule still fails a stamp two or more commits behind" \
  "yes" "$(canon_has "two or more commits behind the head")"
run_test "canonical rule names the helper" \
  "yes" "$(canon_has "outcome-record-revision-check.sh")"

printf '\nResults: %s passed, %s failed\n' "$PASS_COUNT" "$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
