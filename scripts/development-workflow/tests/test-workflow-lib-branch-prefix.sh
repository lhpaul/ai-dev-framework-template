#!/usr/bin/env bash
# test-workflow-lib-branch-prefix.sh — branch_prefix / reviewer_for_branch mapping.
#
# Issue #1401: `feat/*` resolved to `unknown`, so such a branch was never
# cleaned up, got no reviewer assigned, and fell through next-action routing.
# `feat/` is an alias of `feature/`; other unrecognised prefixes stay unknown.
#
# Usage: bash scripts/development-workflow/tests/test-workflow-lib-branch-prefix.sh
# covers: scripts/development-workflow/workflow-lib.sh

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"

# shellcheck source=scripts/development-workflow/workflow-lib.sh
source "$REPO_ROOT/scripts/development-workflow/workflow-lib.sh"

PASS=0
FAIL=0

assert_eq() {
  local name="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    printf 'PASS: %s\n' "$name"
    PASS=$((PASS + 1))
  else
    printf "FAIL: %s - expected '%s', got '%s'\n" "$name" "$expected" "$actual"
    FAIL=$((FAIL + 1))
  fi
}

# branch_prefix: every recognised prefix, the feat/ alias, and unknown cases.
assert_eq "spec"                 "spec"                "$(branch_prefix spec/1-x)"
assert_eq "implementation-plan"  "implementation-plan" "$(branch_prefix implementation-plan/1-x)"
assert_eq "feature"              "feature"             "$(branch_prefix feature/1-x)"
assert_eq "feat alias"           "feature"             "$(branch_prefix feat/1-x)"
assert_eq "refactor"             "refactor"            "$(branch_prefix refactor/1-x)"
assert_eq "fix"                  "fix"                 "$(branch_prefix fix/1-x)"
assert_eq "hotfix"               "hotfix"              "$(branch_prefix hotfix/1-x)"
assert_eq "release"              "release"             "$(branch_prefix release/v1.0.0)"
assert_eq "chore stays unknown"  "unknown"             "$(branch_prefix chore/1-x)"
assert_eq "docs stays unknown"   "unknown"             "$(branch_prefix docs/1-x)"
assert_eq "cursor stays unknown" "unknown"             "$(branch_prefix cursor/1-x)"
assert_eq "haystack stays unknown" "unknown"           "$(branch_prefix haystack/1-x)"
assert_eq "bare feat is unknown" "unknown"             "$(branch_prefix feat)"
assert_eq "featx/ is unknown"    "unknown"             "$(branch_prefix featx/1-x)"
assert_eq "develop is unknown"   "unknown"             "$(branch_prefix develop)"

# #2158: backport/* is its own class (implementation-branch behavior), not an
# alias of hotfix/ or feature/. A bare or empty-remainder backport stays unknown.
assert_eq "backport"             "backport"            "$(branch_prefix backport/1-x)"
assert_eq "backport hotfix"      "backport"            "$(branch_prefix backport/hotfix/1-x)"
assert_eq "bare backport unknown" "unknown"            "$(branch_prefix backport)"
assert_eq "empty backport/ unknown" "unknown"          "$(branch_prefix backport/)"
assert_eq "backportx/ is unknown" "unknown"            "$(branch_prefix backportx/1-x)"

# reviewer_for_branch: feat/ must get a code reviewer like feature/.
assert_eq "reviewer feature"     "code-reviewer"       "$(reviewer_for_branch feature/1-x)"
assert_eq "reviewer feat alias"  "code-reviewer"       "$(reviewer_for_branch feat/1-x)"
assert_eq "reviewer backport"    "code-reviewer"       "$(reviewer_for_branch backport/1-x)"
assert_eq "reviewer spec"        "spec-reviewer"       "$(reviewer_for_branch spec/1-x)"
assert_eq "reviewer unknown"     "none"                "$(reviewer_for_branch chore/1-x)"

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
