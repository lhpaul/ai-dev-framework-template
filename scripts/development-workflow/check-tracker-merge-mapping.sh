#!/usr/bin/env bash
# check-tracker-merge-mapping.sh — AC-9 verification script
#
# Verifies that .github/workflows/update-tracker-on-merge.yml maps each supported
# branch prefix to the correct tracker status. Exits non-zero if any mapping is
# incorrect or missing.
#
# Required YAML structure (the "Detect branch type" step in the update-tracker job):
#   if [[ "$BRANCH" == spec/* ]];              → TARGET_STATUS="Spec Ready"
#   elif [[ "$BRANCH" == implementation-plan/* → TARGET_STATUS="Plan Ready"
#   elif [[ "$BRANCH" == feature/* || ...      → TARGET_STATUS="Merged"
#     (covers feature/*, fix/*, refactor/*, hotfix/*)
#
# Usage:
#   bash scripts/development-workflow/check-tracker-merge-mapping.sh
#
# Exit codes:
#   0 — all six required mappings are correct
#   1 — one or more mappings are incorrect or missing

set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
WORKFLOW_FILE="$REPO_ROOT/.github/workflows/update-tracker-on-merge.yml"

if [ ! -f "$WORKFLOW_FILE" ]; then
  echo "ERROR: workflow file not found: $WORKFLOW_FILE" >&2
  exit 1
fi

ERRORS=0

# ---------------------------------------------------------------------------
# Helper: extract the TARGET_STATUS value assigned for a given branch prefix
# by scanning the TARGET_STATUS="..." assignment that follows the branch
# pattern in the detect step.
# ---------------------------------------------------------------------------
get_target_status() {
  local prefix="$1"
  # Find lines containing the prefix pattern, then capture the TARGET_STATUS
  # assignment within the next 5 lines.
  grep -A5 "${prefix}/\*" "$WORKFLOW_FILE" \
    | grep 'TARGET_STATUS=' \
    | head -1 \
    | sed 's/.*TARGET_STATUS="\([^"]*\)".*/\1/' \
    || true
}

# ---------------------------------------------------------------------------
# Expected mappings (BR-1, BR-2, BR-3, BR-9)
# ---------------------------------------------------------------------------
check_mapping() {
  local prefix="$1"
  local expected="$2"
  local actual
  actual="$(get_target_status "$prefix")"

  if [ "$actual" = "$expected" ]; then
    echo "OK: branch '$prefix/*' → '$actual'"
  else
    echo "ERROR: branch '$prefix/*' → expected '$expected', got '${actual:-missing}'"
    ERRORS=$((ERRORS + 1))
  fi
}

echo "Checking branch-type → tracker-status mappings in:"
echo "  $WORKFLOW_FILE"
echo ""

check_mapping "spec"                "Spec Ready"
check_mapping "implementation-plan" "Plan Ready"
check_mapping "feature"             "Merged"
check_mapping "fix"                 "Merged"
check_mapping "refactor"            "Merged"
check_mapping "hotfix"              "Merged"

echo ""
if [ "$ERRORS" -eq 0 ]; then
  echo "All 6 mappings correct."
  exit 0
else
  echo "$ERRORS mapping(s) failed."
  exit 1
fi
