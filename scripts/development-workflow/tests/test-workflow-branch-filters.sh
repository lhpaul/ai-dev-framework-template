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

# branch_filter_block <file> — the pull_request / pull_request_target branch
# filter, one entry per line; empty when the workflow has no such filter (it
# then runs on every branch and there is nothing to assert).
#
# Uses a real YAML parse rather than line matching. A hand-rolled parser has to
# guess at indentation, flow-style lists (`branches: [a, b]`), and the quoted
# `"on":` key that YAML 1.1 loaders produce for the `on` token — and every one
# of those guesses fails OPEN, reporting "no filter" for a workflow that has
# one. Downstream repos copy these workflows and reformat them, so a parser
# that silently skips a differently-indented file defeats the guard.
# Emits one "<trigger>\t<branch>" line per configured branch filter.
#
# Keeping the trigger name attached matters: `pull_request` and
# `pull_request_target` are different triggers and only the former gates the
# PR checks #1525 is about. Flattening them into one list lets a workflow with
#   pull_request:        branches: [develop, main]
#   pull_request_target: branches: [develop, develop-**]
# read as covered, because `develop-**` appears *somewhere*, while its actual
# `pull_request` filter still omits it and PRs into develop-<slug> still run
# zero checks. That is precisely the gap this suite exists to catch, so the
# parser must not erase the distinction.
# Bash keeps only the most recently registered EXIT trap, so registering one
# per temp directory silently leaks every directory but the last. Both are
# declared and cleaned by a single handler instead.
FIXTURE_DIR=""
_fx=""
_bf_cleanup() {
  [ -n "${FIXTURE_DIR:-}" ] && rm -rf "$FIXTURE_DIR"
  [ -n "${_fx:-}" ] && rm -rf "$_fx"
  return 0
}
trap _bf_cleanup EXIT

branch_filter_entries() {
  if [ "$#" -ne 1 ]; then
    echo "ERROR: branch_filter_entries requires exactly 1 argument (workflow file), got $#" >&2
    return 2
  fi
  if [ ! -r "$1" ]; then
    echo "ERROR: branch_filter_entries: '$1' is not a readable file" >&2
    return 2
  fi
  python3 - "$1" <<'PYBF'
import sys
try:
    import yaml
except ImportError:  # pragma: no cover - PyYAML absent
    sys.exit(3)

try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        doc = yaml.safe_load(fh) or {}
except (OSError, yaml.YAMLError) as exc:
    # Report rather than emit a traceback: an unparseable workflow must fail
    # the guard loudly, not read as "no filter" and be skipped.
    print("ERROR: could not parse %s: %s" % (sys.argv[1], exc), file=sys.stderr)
    sys.exit(4)

# YAML 1.1 parses a bare `on:` key as the boolean True; PyYAML keeps `"on"`
# quoted as the string. Accept either spelling.
triggers = doc.get("on", doc.get(True, {}))
if not isinstance(triggers, dict):
    sys.exit(0)

for key in ("pull_request", "pull_request_target"):
    block = triggers.get(key)
    if not isinstance(block, dict):
        continue
    for entry in block.get("branches", []) or []:
        print("%s\t%s" % (key, entry))
PYBF
}

# Branches configured for one specific trigger.
branches_for_trigger() {
  if [ "$#" -ne 2 ]; then
    echo "ERROR: branches_for_trigger requires 2 arguments (workflow file, trigger), got $#" >&2
    return 2
  fi
  branch_filter_entries "$1" | awk -F'\t' -v t="$2" '$1 == t { print $2 }'
}

# Every configured branch, regardless of trigger. Used only where the question
# is genuinely trigger-agnostic (the hardcoded-slug scan).
branch_filter_block() {
  branch_filter_entries "$1" | awk -F'\t' '{ print $2 }'
}

if ! python3 -c 'import yaml' 2>/dev/null; then
  echo "FAIL: pyyaml_available - PyYAML is required to parse workflow triggers"
  fail=$((fail + 1))
  printf '\nResults: %d passed, %d failed\n' "$pass" "$fail"
  exit 1
fi

missing=""
checked=0
for wf in "$WF_DIR"/*.yml; do
  # Scoped to `pull_request` deliberately. Protocol 05b states the requirement
  # as "must include develop-** in their `pull_request` branch filters", and
  # that is the trigger whose checks a sub-item PR into develop-<slug> needs.
  # Enforcing it on `pull_request_target` too would fail a workflow whose PR
  # checks are fully covered but which deliberately gates its target-context
  # job on develop and main only — a finding the documented rule does not make.
  # The parser stays trigger-aware regardless: that is what stops a develop-**
  # under one trigger from vouching for another (see the pr-vs-pr-target
  # fixture below).
  trigger=pull_request
  block="$(branches_for_trigger "$wf" "$trigger")"
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
    missing="${missing:+$missing }$(basename "$wf"):$trigger"
  fi
done

run_test "some_workflows_gate_on_develop" "yes" "$([ "$checked" -gt 0 ] && echo yes || echo no)"
run_test "develop_gated_workflows_cover_integration_branches" "" "$missing"

# A hardcoded slug is not coverage: it reads as covered while the current
# integration branch is absent (the zeki-cl/zeki-platform trap in #1525).
hardcoded=""
for wf in "$WF_DIR"/*.yml; do
  # Same scope as the coverage scan above: the rule Protocol 05b states is
  # about `pull_request` filters, so a stale slug is judged there.
  while IFS= read -r entry; do
    case "$entry" in
      develop-\*\*|develop-\*) continue ;;
      develop-?*) hardcoded="${hardcoded:+$hardcoded }$(basename "$wf"):$entry" ;;
    esac
  done <<< "$(branches_for_trigger "$wf" pull_request)"
done
run_test "no_hardcoded_integration_branch_slugs" "" "$hardcoded"

# A `push:` filter's `branches:` list is a different trigger than
# `pull_request:` — PR checks are not gated by it. A parser that folds both
# lists together would report a workflow as covering integration branches
# because `develop-**` sits under `push:`, while its actual `pull_request:`
# filter still omits it and PRs into develop-<slug> still run zero checks.
FIXTURE_DIR="$(mktemp -d)"
cat > "$FIXTURE_DIR/push-vs-pull-request.yml" <<'FIXTURE'
name: fixture
on:
  push:
    branches:
      - develop
      - develop-**
      - main
  pull_request:
    branches:
      - develop
      - main
jobs:
  x:
    runs-on: ubuntu-latest
    steps:
      - run: echo hi
FIXTURE
fixture_block="$(branch_filter_block "$FIXTURE_DIR/push-vs-pull-request.yml")"
run_test "branch_filter_block_ignores_push_trigger" "$(printf 'develop\nmain')" "$fixture_block"

# The same confusion one level in: `pull_request` and `pull_request_target` are
# also different triggers. Flattening them lets this workflow read as covered
# because `develop-**` appears under pull_request_target, while the trigger
# that actually gates PR checks still omits it — the exact #1525 gap, passing
# the guard meant to catch it.
cat > "$FIXTURE_DIR/pr-vs-pr-target.yml" <<'FIXTURE'
name: fixture
on:
  pull_request:
    branches:
      - develop
      - main
  pull_request_target:
    branches:
      - develop
      - develop-**
jobs:
  x:
    runs-on: ubuntu-latest
    steps:
      - run: echo hi
FIXTURE
run_test "pull_request_branches_are_trigger_scoped" "$(printf 'develop\nmain')" \
  "$(branches_for_trigger "$FIXTURE_DIR/pr-vs-pr-target.yml" pull_request)"
run_test "pull_request_target_branches_are_trigger_scoped" "$(printf 'develop\ndevelop-**')" \
  "$(branches_for_trigger "$FIXTURE_DIR/pr-vs-pr-target.yml" pull_request_target)"
# Planted violation: the flattened view is what used to be checked, and it
# contains develop-**, so the old logic passed this workflow.
run_test "flattened_view_would_have_passed_this" "yes" \
  "$(branch_filter_block "$FIXTURE_DIR/pr-vs-pr-target.yml" | grep -qx 'develop-\*\*' && echo yes || echo no)"
# Trigger-scoped, the pull_request filter is correctly seen as missing it.
run_test "trigger_scoped_view_catches_the_gap" "no" \
  "$(branches_for_trigger "$FIXTURE_DIR/pr-vs-pr-target.yml" pull_request | grep -qx 'develop-\*\*' && echo yes || echo no)"

# Argument validation: a missing or unreadable file must be a reported error,
# not a shell failure or a Python traceback, and must not read as "no filter".
_bf_status() { local st=0; "$@" >/dev/null 2>&1 || st=$?; printf '%s\n' "$st"; }
run_test "branch_filter_entries_no_args" "2" "$(_bf_status branch_filter_entries)"
run_test "branch_filter_entries_two_args" "2" "$(_bf_status branch_filter_entries a b)"
run_test "branch_filter_entries_unreadable" "2" "$(_bf_status branch_filter_entries "$FIXTURE_DIR/does-not-exist.yml")"
run_test "branches_for_trigger_wrong_arity" "2" "$(_bf_status branches_for_trigger "$FIXTURE_DIR/pr-vs-pr-target.yml")"

# Formats a hand-rolled parser would miss, each failing OPEN (reporting "no
# filter" for a workflow that has one). Downstream repos reformat what they
# copy, so these are the realistic shapes, not exotica.
_fx="$(mktemp -d)"
cat > "$_fx/four-space.yml" <<'YFX'
name: Four Space
on:
    pull_request:
        branches:
            - develop
            - main
YFX
cat > "$_fx/flow-style.yml" <<'YFX'
name: Flow Style
on:
  pull_request:
    branches: [develop, "develop-**", 'main']
YFX
cat > "$_fx/quoted-on.yml" <<'YFX'
name: Quoted On
"on":
  pull_request_target:
    branches:
      - develop
YFX
run_test "parses_four_space_indentation" "develop main" \
  "$(branch_filter_block "$_fx/four-space.yml" | tr '\n' ' ' | sed 's/ $//')"
run_test "parses_flow_style_list" "develop develop-** main" \
  "$(branch_filter_block "$_fx/flow-style.yml" | tr '\n' ' ' | sed 's/ $//')"
run_test "parses_quoted_on_key" "develop" \
  "$(branch_filter_block "$_fx/quoted-on.yml" | tr '\n' ' ' | sed 's/ $//')"

printf '\nResults: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
