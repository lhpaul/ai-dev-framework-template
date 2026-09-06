#!/usr/bin/env bash
# test-protocol-91-readiness-checklist.sh - Step 8a/8a.1 executable-snippet regression coverage.
#
# The Step 8a "Label Readiness Checklist (Hard Gate)" and the Step 8a.1
# re-check live only as fenced bash in the protocol; nothing else executes
# them. A run of /run-item hit both halves of the same defect at once:
#
#   1. The Step 8a GraphQL query carried one extra closing brace, so
#      `gh api graphql` failed with
#      `Expected one of SCHEMA, SCALAR, TYPE, ENUM, INPUT, UNION, INTERFACE,
#      actual: RCURLY ("}")` before it could look at a single thread.
#   2. Both snippets passed literal `-f owner="<owner>" -f repo="<repo>"`
#      placeholders that no step ever substituted, unlike PR_NUMBER and BRANCH
#      which the operator is told to fill in.
#
# The protocol calls this gate the ONLY authoritative check for review-thread
# resolution state, so an unrunnable gate invites an agent to skip it and label
# a PR ready with unresolved blocking findings — exactly what the surrounding
# warnings exist to prevent. These assertions run the snippets' shape, not
# their prose.
#
# covers: docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
PROTOCOL="$REPO_ROOT/docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md"

PASS_COUNT=0
FAIL_COUNT=0

run_test() {
  local name="$1"
  local expected="$2"
  local actual="$3"

  if [ "$expected" = "$actual" ]; then
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $name - expected '$expected', got '$actual'"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

[ -f "$PROTOCOL" ] || { echo "FAIL: protocol 91 not found at $PROTOCOL"; exit 1; }

# --- 1. Every embedded GraphQL query is brace-balanced -----------------------
# Extracts each `gh api graphql -f query='...'` argument and counts braces.
# An imbalance is the exact defect that produced the RCURLY parse error.
_balance_report="$(python3 - "$PROTOCOL" <<'PY'
import re
import sys

text = open(sys.argv[1], encoding="utf-8").read()
# The query argument runs from -f query=' to the next unescaped single quote.
pattern = re.compile(r"gh api graphql -f query='(?P<query>[^']*)'")
bad = []
count = 0
for match in pattern.finditer(text):
    count += 1
    query = match.group("query")
    line = text.count("\n", 0, match.start()) + 1
    depth = 0
    lowest = 0
    for char in query:
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            lowest = min(lowest, depth)
    if depth != 0 or lowest < 0:
        bad.append(f"line {line}: net brace depth {depth}, minimum {lowest}")

if count == 0:
    print("no-graphql-queries-found")
elif bad:
    print("; ".join(bad))
else:
    print(f"balanced:{count}")
PY
)"
run_test "graphql_queries_brace_balanced" "balanced:3" "$_balance_report"

# --- 2. No unsubstituted owner/repo placeholders in the runnable gates -------
# Step 8c's query is a documented fill-in template (its PR number is a
# placeholder too), so the placeholder form is only a defect when it appears in
# the `-f owner=` / `-f repo=` position of a snippet whose PR number comes from
# a shell variable — i.e. a snippet an agent is meant to execute verbatim.
_placeholder_count="$(grep -c -- '-f owner="<owner>" -f repo="<repo>" -F number="\$PR_NUMBER"' "$PROTOCOL" || true)"
run_test "no_placeholder_owner_repo_in_runnable_gates" "0" "$_placeholder_count"

# Both runnable gates must derive owner and repo from the checklist's own
# repository slug rather than from a hand-edited literal.
_derives_owner="$(grep -c 'GRAPHQL_OWNER="${TARGET_REPO%%/\*}"' "$PROTOCOL" || true)"
run_test "runnable_gates_derive_owner_from_target_repo" "2" "$_derives_owner"
_derives_repo="$(grep -c 'GRAPHQL_REPO="${TARGET_REPO#\*/}"' "$PROTOCOL" || true)"
run_test "runnable_gates_derive_repo_from_target_repo" "2" "$_derives_repo"

_uses_derived="$(grep -c -- '-f owner="\$GRAPHQL_OWNER" -f repo="\$GRAPHQL_REPO"' "$PROTOCOL" || true)"
run_test "runnable_gates_pass_derived_owner_repo" "2" "$_uses_derived"

# TARGET_REPO must actually be defined by the checklist that uses it.
if grep -q 'TARGET_REPO=$(repo_slug)' "$PROTOCOL"; then
  _target_repo_defined="yes"
else
  _target_repo_defined="no"
fi
run_test "target_repo_resolved_in_checklist" "yes" "$_target_repo_defined"

# --- 3. The Step 8a checklist parses as bash --------------------------------
# Extracts the fenced block that opens the label readiness checklist and runs
# `bash -n` on it. This would not have caught the GraphQL brace (it lives
# inside a single-quoted string), which is why check 1 above exists; it does
# catch the far more common structural breakage in a block this long.
_CHECKLIST="$(python3 - "$PROTOCOL" <<'PY'
import sys

lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
start = None
for index, line in enumerate(lines):
    if line.strip() == "PR_NUMBER=<pr_number>":
        start = index
        break
if start is None:
    sys.exit("checklist-not-found")
# Walk back to the opening fence, forward to the closing one.
opener = start
while opener > 0 and not lines[opener].startswith("```"):
    opener -= 1
closer = start
while closer < len(lines) and not lines[closer].startswith("```"):
    closer += 1
body = lines[opener + 1:closer]
# The two operator-filled placeholders are not shell; substitute them the way
# step 1 of the procedure tells the operator to.
body = [
    line.replace("PR_NUMBER=<pr_number>", "PR_NUMBER=1").replace(
        "BRANCH=<branch_name>", "BRANCH=feature/x"
    )
    for line in body
]
print("\n".join(body))
PY
)"

if [ -z "$_CHECKLIST" ]; then
  run_test "step_8a_checklist_extracted" "yes" "no"
else
  run_test "step_8a_checklist_extracted" "yes" "yes"
  _syntax_error="$(printf '%s\n' "$_CHECKLIST" | bash -n 2>&1 || true)"
  run_test "step_8a_checklist_parses_as_bash" "" "$_syntax_error"
fi

echo ""
echo "${PASS_COUNT} passed, ${FAIL_COUNT} failed"

if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi
