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
#   elif [[ "$BRANCH" == develop-* ]];         → BRANCH_TYPE="graduation"
#     (invokes graduation-closeout-from-merged-pr.sh closeout fallback)
#
# Usage:
#   bash scripts/development-workflow/check-tracker-merge-mapping.sh
#
# Exit codes:
#   0 — all six required mappings are correct and graduation fallback is wired
#   1 — one or more mappings are incorrect or missing

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../.." && pwd)"
WORKFLOW_FILE="${WORKFLOW_FILE_OVERRIDE:-$REPO_ROOT/.github/workflows/update-tracker-on-merge.yml}"

# shellcheck source=scripts/development-workflow/workflow-lib.sh
source "$SCRIPT_DIR/workflow-lib.sh"

if [ ! -f "$WORKFLOW_FILE" ]; then
  provider_config="$(workflow_effective_config_file || true)"
  provider="$(workflow_normalize_issue_tracker_provider "$(workflow_config_provider issue_tracker "$provider_config")")"
  case "$provider" in
    github|github_issues|github_projects)
      echo "ERROR: workflow file not found: $WORKFLOW_FILE"
      echo "GitHub-based tracker provider '${provider}' requires update-tracker-on-merge.yml."
      exit 1
      ;;
    *)
      echo "SKIP: workflow file not found: $WORKFLOW_FILE"
      echo "Non-GitHub tracker providers intentionally omit update-tracker-on-merge.yml."
      exit 0
      ;;
  esac
fi

ERRORS=0

# ---------------------------------------------------------------------------
# Helper: extract the TARGET_STATUS value assigned for a given branch prefix
# by scanning the TARGET_STATUS="..." assignment that follows the branch
# pattern in the detect step.
# ---------------------------------------------------------------------------
get_target_status() {
  local prefix="$1"
  # Anchor on "== ${prefix}/" to avoid substring false-positives
  # (e.g., "fix/*" is a substring of "hotfix/*"; anchoring on "== fix/"
  # prevents the hotfix line from satisfying a fix/* lookup).
  # Extract the block from the matching "== ${prefix}/" line up to (but not
  # including) the next branch clause (detected by "elif"), then search that
  # block for TARGET_STATUS. Using "elif" as the terminator is more explicit
  # and robust than the generic "== " pattern.
  awk "/== ${prefix}\\//{found=1; next} found && /elif/{exit} found{print}" "$WORKFLOW_FILE" \
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
# Graduation heads must invoke closeout fallback rather than silent untracked skip.
if grep -Eq 'BRANCH_TYPE="graduation"|branch_type=graduation' "$WORKFLOW_FILE" \
  && grep -Fq 'graduation-closeout-from-merged-pr.sh' "$WORKFLOW_FILE" \
  && grep -Eq '== develop-\*|develop-\*' "$WORKFLOW_FILE"; then
  echo "OK: branch 'develop-*' → graduation closeout fallback"
else
  echo "ERROR: branch 'develop-*' → expected graduation closeout fallback wiring (BRANCH_TYPE=graduation + graduation-closeout-from-merged-pr.sh)"
  ERRORS=$((ERRORS + 1))
fi

# Checkout for graduation closeout requires contents: read when permissions: is explicit.
if grep -Eq 'uses:[[:space:]]*actions/checkout@' "$WORKFLOW_FILE"; then
  if grep -Eq '^[[:space:]]*contents:[[:space:]]*read[[:space:]]*$' "$WORKFLOW_FILE"; then
    echo "OK: actions/checkout present with contents: read"
  else
    echo "ERROR: actions/checkout is used but permissions lack contents: read (checkout will 403)"
    ERRORS=$((ERRORS + 1))
  fi
fi

echo ""
if [ "$ERRORS" -eq 0 ]; then
  echo "All 6 mappings correct (+ graduation closeout fallback)."
  exit 0
else
  echo "$ERRORS mapping(s) failed."
  exit 1
fi
