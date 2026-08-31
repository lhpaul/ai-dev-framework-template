#!/usr/bin/env bash
# test-reviewer-loop-commit-ancestry.sh — scenarios 4, 5, 5a, 5b for #1651.
# covers: scripts/development-workflow/pr-review-loop.sh
# covers: docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md
#
# shellcheck shell=bash disable=SC2034

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"

PASS_COUNT=0
FAIL_COUNT=0

run_test() {
  local name="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $name — expected '${expected}', got '${actual}'"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

export MOCK_REPO_ROOT="$REPO_ROOT"
# shellcheck source=scripts/development-workflow/pr-review-loop.sh
HARNESS_MODE=1 source "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh"

echo "=== test-reviewer-loop-commit-ancestry (#1651 scenarios 4/5) ==="

FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT

# Purpose-built fixture: root commit, two divergent branches of two commits each,
# plus one commit created then pruned for the absent-object case.
git -C "$FIXTURE" init -q
git -C "$FIXTURE" config user.email "test@example.com"
git -C "$FIXTURE" config user.name "Test"
echo root > "$FIXTURE/root.txt"
git -C "$FIXTURE" add root.txt
git -C "$FIXTURE" commit -qm root
ROOT="$(git -C "$FIXTURE" rev-parse HEAD)"

git -C "$FIXTURE" checkout -qb branch-a
echo a1 > "$FIXTURE/a.txt"
git -C "$FIXTURE" add a.txt
git -C "$FIXTURE" commit -qm a1
A1="$(git -C "$FIXTURE" rev-parse HEAD)"
echo a2 >> "$FIXTURE/a.txt"
git -C "$FIXTURE" add a.txt
git -C "$FIXTURE" commit -qm a2
A2="$(git -C "$FIXTURE" rev-parse HEAD)"

git -C "$FIXTURE" checkout -qb branch-b "$ROOT"
echo b1 > "$FIXTURE/b.txt"
git -C "$FIXTURE" add b.txt
git -C "$FIXTURE" commit -qm b1
B1="$(git -C "$FIXTURE" rev-parse HEAD)"
echo b2 >> "$FIXTURE/b.txt"
git -C "$FIXTURE" add b.txt
git -C "$FIXTURE" commit -qm b2
B2="$(git -C "$FIXTURE" rev-parse HEAD)"

# Deleted object for absent-commit case
git -C "$FIXTURE" checkout -qb doomed "$ROOT"
echo doomed > "$FIXTURE/doomed.txt"
git -C "$FIXTURE" add doomed.txt
git -C "$FIXTURE" commit -qm doomed
DOOMED="$(git -C "$FIXTURE" rev-parse HEAD)"
git -C "$FIXTURE" checkout -q branch-a
git -C "$FIXTURE" branch -D doomed >/dev/null
git -C "$FIXTURE" reflog expire --expire=now --all
git -C "$FIXTURE" prune --expire now

# Run ancestry checks inside the fixture repo
pushd "$FIXTURE" >/dev/null

# Scenario 4
run_test "1651_ancestry_same" "same" "$(reviewer_loop_commit_ancestry "$A2" "$A2")"
run_test "1651_ancestry_ancestor" "ancestor" "$(reviewer_loop_commit_ancestry "$A1" "$A2")"
run_test "1651_ancestry_descendant" "descendant" "$(reviewer_loop_commit_ancestry "$A2" "$A1")"
run_test "1651_ancestry_unrelated" "unrelated" "$(reviewer_loop_commit_ancestry "$A2" "$B2")"

# Scenario 5 — absent commit
run_test "1651_ancestry_absent" "undecidable" "$(reviewer_loop_commit_ancestry "$DOOMED" "$A2")"

# Scenario 5 — empty argument
run_test "1651_ancestry_empty" "undecidable" "$(reviewer_loop_commit_ancestry "" "$A2")"
run_test "1651_ancestry_empty_both" "undecidable" "$(reviewer_loop_commit_ancestry "" "")"

# Scenario 5b — two identical missing SHAs are undecidable, not same
MISSING="ffffffffffffffffffffffffffffffffffffffff"
run_test "1651_ancestry_identical_missing" "undecidable" \
  "$(reviewer_loop_commit_ancestry "$MISSING" "$MISSING")"

# Scenario 5 — git stub exit 128 for merge-base --is-ancestor
REAL_GIT="$(command -v git)"
STUB_BIN="$(mktemp -d)"
cat > "$STUB_BIN/git" <<STUB
#!/usr/bin/env bash
if [ "\${1:-}" = "merge-base" ] && [ "\${2:-}" = "--is-ancestor" ]; then
  exit 128
fi
exec "$REAL_GIT" "\$@"
STUB
chmod +x "$STUB_BIN/git"
PATH="$STUB_BIN:$PATH"
run_test "1651_ancestry_merge_base_error" "undecidable" \
  "$(reviewer_loop_commit_ancestry "$A1" "$A2")"
PATH="${PATH#"$STUB_BIN:"}"
rm -rf "$STUB_BIN"

# Scenario 5a — under set -euo pipefail, status 1 paths do not abort
set -euo pipefail
_ok=1
reviewer_loop_commit_ancestry "$A1" "$A2" >/dev/null || _ok=0
reviewer_loop_commit_ancestry "$A2" "$A1" >/dev/null || _ok=0
reviewer_loop_commit_ancestry "$A2" "$B2" >/dev/null || _ok=0
reviewer_loop_commit_ancestry "$A2" "$A2" >/dev/null || _ok=0
reviewer_loop_commit_ancestry "" "" >/dev/null || _ok=0
run_test "1651_ancestry_errexit_safe" "1" "$_ok"

popd >/dev/null

echo ""
echo "Tests: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
