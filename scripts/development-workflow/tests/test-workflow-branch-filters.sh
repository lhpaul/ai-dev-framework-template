#!/usr/bin/env bash
# test-workflow-branch-filters.sh - integration-branch CI coverage.
# covers: .github/workflows/e2e-regression.yml
# covers: .github/workflows/markdown-lint.yml
# covers: .github/workflows/shellcheck.yml
# covers: .github/workflows/workflow-tests.yml
#
# Protocol 05b defines integration branches (develop-<slug>); an epic's
# sub-item PRs target them. A workflow whose pull_request filter lists
# `develop` but not `develop-**` therefore runs zero checks on that work, and
# the entire epic reaches its graduation PR untested (#1525). Downstream repos
# copy these files, so the gap propagates — and hardcoding one slug reads as
# coverage while the current integration branch is absent.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"
WF_DIR="$REPO_ROOT/.github/workflows"

pass=0
fail=0
run_test() {
  local name="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "PASS: $name"; pass=$((pass + 1))
  else
    echo "FAIL: $name - expected '$expected', got '$actual'"; fail=$((fail + 1))
  fi
}

# branch_filter_block <file> — the `branches:` list under `on:`, one entry per
# line, empty when the workflow has no branch filter (runs on every branch).
branch_filter_block() {
  awk '
    /^on:/ { in_on = 1; next }
    /^[^[:space:]#]/ { in_on = 0 }
    in_on && /^[[:space:]]+branches:[[:space:]]*$/ { in_br = 1; next }
    in_br && /^[[:space:]]+-[[:space:]]/ { sub(/^[[:space:]]*-[[:space:]]*/, ""); gsub(/[\047"]/, ""); print; next }
    # Comments and blank lines sit inside the list without ending it.
    in_br && /^[[:space:]]*#/ { next }
    in_br && /^[[:space:]]*$/ { next }
    in_br { in_br = 0 }
  ' "$1"
}

missing=""
checked=0
for wf in "$WF_DIR"/*.yml; do
  block="$(branch_filter_block "$wf")"
  # No filter at all → runs everywhere → nothing to assert.
  [ -n "$block" ] || continue
  # Only workflows that gate on `develop` are in scope; a main-only workflow
  # (release tagging) legitimately never runs on an integration branch.
  printf '%s\n' "$block" | grep -qx "develop" || continue
  # update-tracker-on-merge.yml is deliberately out of scope: it closes issues
  # and writes tracker status on merge, so extending it to integration branches
  # is a tracker-lifecycle decision (does a sub-item merged into develop-<slug>
  # close before the epic graduates?), not the CI-coverage gap #1525 reports.
  case "$(basename "$wf")" in
    update-tracker-on-merge.yml) continue ;;
  esac
  checked=$((checked + 1))
  if ! printf '%s\n' "$block" | grep -qx "develop-\*\*"; then
    missing="${missing:+$missing }$(basename "$wf")"
  fi
done

run_test "some_workflows_gate_on_develop" "yes" "$([ "$checked" -gt 0 ] && echo yes || echo no)"
run_test "develop_gated_workflows_cover_integration_branches" "" "$missing"

# A hardcoded slug is not coverage: it reads as covered while the current
# integration branch is absent (the zeki-cl/zeki-platform trap in #1525).
hardcoded=""
for wf in "$WF_DIR"/*.yml; do
  while IFS= read -r entry; do
    case "$entry" in
      develop-\*\*|develop-\*) continue ;;
      develop-?*) hardcoded="${hardcoded:+$hardcoded }$(basename "$wf"):$entry" ;;
    esac
  done <<< "$(branch_filter_block "$wf")"
done
run_test "no_hardcoded_integration_branch_slugs" "" "$hardcoded"

printf '\nResults: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
