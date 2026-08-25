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
# A workflow file is a mapping. A top-level list or scalar would make the
# .get() below raise AttributeError outside the try, producing a traceback
# rather than the structured error every other malformed input gets — and a
# traceback is harder to act on and easier to mistake for a harness bug.
if not isinstance(doc, dict):
    print("ERROR: %s is not a YAML mapping (got %s)" % (sys.argv[1], type(doc).__name__), file=sys.stderr)
    sys.exit(4)

triggers = doc.get("on", doc.get(True, {}))
if not isinstance(triggers, dict):
    sys.exit(0)

for key in ("pull_request", "pull_request_target"):
    block = triggers.get(key)
    if not isinstance(block, dict):
        continue
    for entry in block.get("branches", []) or []:
        print("%s\t%s" % (key, entry))
    # branches-ignore is the restrictive form of the same filter, and GitHub
    # treats it as mutually exclusive with branches. Emitting it under a
    # distinct pseudo-trigger keeps every existing caller untouched while
    # making exclusions queryable: a workflow that excludes develop-** has no
    # integration-branch coverage, yet reports "no filter" to a reader that
    # only looks at branches.
    for entry in block.get("branches-ignore", []) or []:
        print("%s-ignore\t%s" % (key, entry))
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

# True when a branches-ignore list (one entry per line, as returned by
# branches_for_trigger with a "-ignore" pseudo-trigger) excludes an
# integration branch. Requires the dash: branches-ignore matches each entry
# exactly, with no implicit wildcard, so `branches-ignore: [develop]` excludes
# only the literal `develop` branch — the workflow still runs on
# `develop-<slug>` — and must NOT be flagged. `develop-**`, `develop-*`, and a
# literal `develop-<slug>` all do exclude integration-branch coverage and must
# be flagged. `developer-branch` must not match either: the dash anchors the
# boundary so `develop` cannot match as a prefix of an unrelated branch name.
# Does any of these branches-ignore patterns actually exclude an integration
# branch? Decided by *matching a representative branch name against the glob*
# rather than by inspecting the pattern's text. Pattern-shape matching kept
# getting this wrong in both directions: `^develop(-|$)` wrongly flagged a bare
# `develop` exclusion (which leaves develop-<slug> covered), and `^develop-`
# then missed `develop*` and `dev*`, both of which genuinely do exclude it.
# GitHub's branch filters are globs, so ask the glob.
# GitHub evaluates a branch-filter list in order, and a later `!pattern`
# overrides an earlier match. So `branches: [develop-**, '!develop-old']`
# advertises integration-branch coverage while leaving develop-old with none.
# Both helpers below therefore replay the list in order rather than asking
# whether any single entry matches.
#
# Samples: one ordinary integration branch, plus one that a negation is likely
# to name. A filter must cover BOTH to count as covering integration branches.
BF_SAMPLES="develop-example
develop-old
develop-team/thing"

# GitHub's branch-filter globs are not shell globs: `*` does not cross `/`,
# `**` does, and `?` matches one non-`/` character. Shell `case` crosses `/`
# for both stars, so it reports `develop-*` as covering `develop-team/thing`
# when GitHub would not. Translate to an anchored regex instead of asking the
# shell, so the guard answers the question GitHub actually asks.
bf_glob_matches() {
  local sample="$1" pat="$2" re="" i=0 c n
  while [ "$i" -lt "${#pat}" ]; do
    c="${pat:i:1}"; n="${pat:i+1:1}"
    case "$c" in
      '*')
        if [ "$n" = '*' ]; then re="${re}.*"; i=$((i+2)); continue; fi
        re="${re}[^/]*"; i=$((i+1)); continue ;;
      '?') re="${re}[^/]" ;;
      '.'|'['|']'|'('|')'|'{'|'}'|'+'|'^'|'$'|'|'|'\\') re="${re}\\$c" ;;
      *) re="${re}${c}" ;;
    esac
    i=$((i+1))
  done
  printf '%s' "$sample" | grep -qE "^${re}\$"
}

# Is <sample> included by a positive `branches:` list?
filter_includes() {
  local sample="$1" list="$2" pat neg included has_positive=0
  while IFS= read -r pat; do
    [ -n "$pat" ] || continue
    case "$pat" in '!'*) : ;; *) has_positive=1 ;; esac
  done <<< "$list"
  # With no positive pattern the list only subtracts, so everything starts in.
  if [ "$has_positive" -eq 1 ]; then included=0; else included=1; fi
  while IFS= read -r pat; do
    [ -n "$pat" ] || continue
    case "$pat" in
      '!'*)
        neg="${pat#!}"
        bf_glob_matches "$sample" "$neg" && included=0
        ;;
      *)
        bf_glob_matches "$sample" "$pat" && included=1
        ;;
    esac
  done <<< "$list"
  [ "$included" -eq 1 ]
}

# Does a positive `branches:` list cover every integration-branch sample?
covers_integration_branches() {
  local sample
  while IFS= read -r sample; do
    [ -n "$sample" ] || continue
    filter_includes "$sample" "$1" || return 1
  done <<< "$BF_SAMPLES"
  return 0
}

# Does a `branches-ignore:` list exclude any integration-branch sample? Same
# ordered replay; here a match means excluded, and `!` un-excludes.
ignores_integration_branch() {
  local sample pat neg excluded
  while IFS= read -r sample; do
    [ -n "$sample" ] || continue
    excluded=0
    while IFS= read -r pat; do
      [ -n "$pat" ] || continue
      case "$pat" in
        '!'*)
          neg="${pat#!}"
          bf_glob_matches "$sample" "$neg" && excluded=0
          ;;
        *)
          bf_glob_matches "$sample" "$pat" && excluded=1
          ;;
      esac
    done <<< "$1"
    [ "$excluded" -eq 1 ] && return 0
  done <<< "$BF_SAMPLES"
  return 1
}


if ! python3 -c 'import yaml' 2>/dev/null; then
  echo "FAIL: pyyaml_available - PyYAML is required to parse workflow triggers"
  fail=$((fail + 1))
  printf '\nResults: %d passed, %d failed\n' "$pass" "$fail"
  exit 1
fi

missing=""
checked=0
# Both extensions: GitHub honours .yaml as well as .yml, so a *.yml-only
# glob would let a .yaml workflow escape this guard entirely.
for wf in "$WF_DIR"/*.yml "$WF_DIR"/*.yaml; do
  [ -e "$wf" ] || continue
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
  ignores="$(branches_for_trigger "$wf" "${trigger}-ignore")"
  # An exclusion that names an integration branch removes coverage exactly as
  # an omission from a positive list does — a workflow with only
  # `branches-ignore: [develop-**]` runs on every base branch EXCEPT the one
  # #1525 is about. Judge it before the "no positive filter" early return,
  # which would otherwise let it through as "runs everywhere".
  if [ -n "$ignores" ]; then
    case "$(basename "$wf")" in
      update-tracker-on-merge.yml) : ;;
      *)
        if ignores_integration_branch "$ignores"; then
          checked=$((checked + 1))
          missing="${missing:+$missing }$(basename "$wf"):${trigger}-ignore"
          continue
        fi
        ;;
    esac
  fi
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
  # Replay the list the way GitHub does rather than looking for a literal
  # `develop-**` entry: an ordered filter can advertise the glob and then
  # withdraw part of it with a later negation.
  if ! covers_integration_branches "$block"; then
    missing="${missing:+$missing }$(basename "$wf"):$trigger"
  fi
done

run_test "some_workflows_gate_on_develop" "yes" "$([ "$checked" -gt 0 ] && echo yes || echo no)"
run_test "develop_gated_workflows_cover_integration_branches" "" "$missing"

# A hardcoded slug is not coverage: it reads as covered while the current
# integration branch is absent (the zeki-cl/zeki-platform trap in #1525).
hardcoded=""
# Both extensions: GitHub honours .yaml as well as .yml, so a *.yml-only
# glob would let a .yaml workflow escape this guard entirely.
for wf in "$WF_DIR"/*.yml "$WF_DIR"/*.yaml; do
  [ -e "$wf" ] || continue
  # Same scope as the coverage scan above: the rule Protocol 05b states is
  # about `pull_request` filters, so a stale slug is judged there — in the
  # exclusion list as well as the positive one. `branches-ignore:
  # [develop-oldslug]` is a hardcoded integration-branch reference exactly as
  # a positive `develop-oldslug` entry is, and rots the same way.
  while IFS= read -r entry; do
    case "$entry" in
      develop-\*\*|develop-\*) continue ;;
      develop-?*) hardcoded="${hardcoded:+$hardcoded }$(basename "$wf"):ignore:$entry" ;;
    esac
  done <<< "$(branches_for_trigger "$wf" pull_request-ignore)"
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
# branches-ignore is the restrictive form of the same filter. A workflow using
# it to exclude integration branches has no coverage there, but a parser that
# reads only `branches:` sees nothing and reports "runs everywhere" — so the
# exclusion escapes the guard entirely.
cat > "$FIXTURE_DIR/branches-ignore-excludes-integration.yml" <<'FIXTURE'
name: fixture
on:
  pull_request:
    branches-ignore:
      - develop-**
jobs:
  x:
    runs-on: ubuntu-latest
    steps:
      - run: echo hi
FIXTURE
run_test "branches_ignore_is_parsed_under_its_own_trigger" "develop-**" \
  "$(branches_for_trigger "$FIXTURE_DIR/branches-ignore-excludes-integration.yml" pull_request-ignore)"
# The positive list is empty, which is exactly why the old parser saw nothing.
run_test "branches_ignore_leaves_positive_list_empty" "" \
  "$(branches_for_trigger "$FIXTURE_DIR/branches-ignore-excludes-integration.yml" pull_request)"
# An exclusion that does not name an integration branch is fine: the workflow
# still runs on develop-<slug>.
cat > "$FIXTURE_DIR/branches-ignore-unrelated.yml" <<'FIXTURE'
name: fixture
on:
  pull_request:
    branches-ignore:
      - gh-pages
jobs:
  x:
    runs-on: ubuntu-latest
    steps:
      - run: echo hi
FIXTURE
run_test "branches_ignore_unrelated_exclusion_parsed" "gh-pages" \
  "$(branches_for_trigger "$FIXTURE_DIR/branches-ignore-unrelated.yml" pull_request-ignore)"

# `branches-ignore: [develop]` (no dash) excludes only the literal `develop`
# branch — not `develop-<slug>` — so the workflow still runs on integration
# branches. Flagging it would be a false positive: #1525 is about
# `develop-<slug>` coverage, not `develop` itself.
cat > "$FIXTURE_DIR/branches-ignore-bare-develop.yml" <<'FIXTURE'
name: fixture
on:
  pull_request:
    branches-ignore:
      - develop
jobs:
  x:
    runs-on: ubuntu-latest
    steps:
      - run: echo hi
FIXTURE
run_test "branches_ignore_bare_develop_is_not_flagged" "no" \
  "$(ignores_integration_branch "$(branches_for_trigger "$FIXTURE_DIR/branches-ignore-bare-develop.yml" pull_request-ignore)" && echo yes || echo no)"
# The actual guard predicate, not just the parser, must flag a develop-**
# exclusion and must not flag an unrelated one or a bare-`develop` one.
run_test "guard_predicate_flags_develop_slug_exclusion" "yes" \
  "$(ignores_integration_branch "$(branches_for_trigger "$FIXTURE_DIR/branches-ignore-excludes-integration.yml" pull_request-ignore)" && echo yes || echo no)"
run_test "guard_predicate_ignores_unrelated_exclusion" "no" \
  "$(ignores_integration_branch "$(branches_for_trigger "$FIXTURE_DIR/branches-ignore-unrelated.yml" pull_request-ignore)" && echo yes || echo no)"
# A different branch that merely starts with the same letters must not match:
# the dash anchors the boundary.
# The predicate asks the glob, not the pattern's shape. These are the cases
# that pattern-matching got wrong in both directions: `develop` alone leaves
# develop-<slug> covered, while `develop*` and `dev*` genuinely exclude it even
# though neither starts with the literal `develop-`.
_bf_excl() { if ignores_integration_branch "$1"; then printf 'excludes\n'; else printf 'no\n'; fi; }
# GitHub replays a branch-filter list in order and a later `!pattern` overrides
# an earlier match. A literal search for `develop-**` therefore passes a filter
# that advertises the glob and then withdraws part of it.
_bf_cov() { if covers_integration_branches "$1"; then printf 'covers\n'; else printf 'gap\n'; fi; }
run_test "guard_ordered_plain_glob_covers" "covers" "$(_bf_cov "$(printf 'develop\ndevelop-**\nmain')")"
run_test "guard_ordered_negation_withdraws_coverage" "gap" "$(_bf_cov "$(printf 'develop\ndevelop-**\n!develop-old')")"
run_test "guard_ordered_no_glob_is_a_gap" "gap" "$(_bf_cov "$(printf 'develop\nmain')")"
# Under GitHub's semantics a single star does not cross `/`, so `develop*`
# covers develop-example but NOT develop-team/thing. Only the double-star form
# covers a nested integration branch — which is exactly why Protocol 05b
# specifies `develop-**` rather than any glob that happens to match.
run_test "guard_ordered_develop_star_misses_nested" "gap" "$(_bf_cov 'develop*')"
run_test "guard_ordered_double_star_covers_nested" "covers" "$(_bf_cov "$(printf 'develop\ndevelop-**')")"
# Negation in an ignore list un-excludes, but only for what it names: the other
# integration-branch sample stays excluded, so the workflow is still short.
run_test "guard_ignore_negation_still_excludes_others" "excludes" \
  "$(if ignores_integration_branch "$(printf 'develop-**\n!develop-old')"; then printf 'excludes\n'; else printf 'no\n'; fi)"

# Still an exclusion: it matches develop-example even though it misses the
# nested sample, and excluding any integration branch is a coverage gap.
run_test "guard_glob_develop_star_excludes" "excludes" "$(_bf_excl 'develop*')"
run_test "guard_glob_dev_star_excludes" "excludes" "$(_bf_excl 'dev*')"
run_test "guard_glob_double_star_excludes" "excludes" "$(_bf_excl '**')"
run_test "guard_glob_bare_develop_does_not_exclude" "no" "$(_bf_excl 'develop')"
run_test "guard_glob_release_prefix_does_not_exclude" "no" "$(_bf_excl 'release/*')"
# A .yaml workflow must not escape the scan; GitHub honours both extensions.
cat > "$FIXTURE_DIR/dot-yaml-extension.yaml" <<'FIXTURE'
name: fixture
on:
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
# A top-level list or scalar is not a workflow. It must produce the structured
# parser error, not an AttributeError traceback that reads like a harness bug.
printf -- '- a\n- b\n' > "$FIXTURE_DIR/toplevel-list.yml"
printf 'just-a-scalar\n' > "$FIXTURE_DIR/toplevel-scalar.yml"
_bf_status() { local st=0; branch_filter_entries "$1" >/dev/null 2>&1 || st=$?; printf '%s\n' "$st"; }
run_test "toplevel_list_is_a_parser_error" "4" "$(_bf_status "$FIXTURE_DIR/toplevel-list.yml")"
run_test "toplevel_scalar_is_a_parser_error" "4" "$(_bf_status "$FIXTURE_DIR/toplevel-scalar.yml")"
# stderr captured to a variable first: the suite runs with `pipefail`, so
# piping straight from a function that exits non-zero makes the pipeline
# inherit that status and the assertion would measure the exit code instead of
# the message it claims to check.
_bf_says_not_mapping() {
  local out
  out="$(branch_filter_entries "$1" 2>&1 >/dev/null || true)"
  case "$out" in
    *"not a YAML mapping"*) printf 'yes\n' ;;
    *) printf 'no\n' ;;
  esac
}
run_test "toplevel_list_reports_on_stderr" "yes" \
  "$(_bf_says_not_mapping "$FIXTURE_DIR/toplevel-list.yml")"
# A hardcoded slug in an EXCLUSION rots exactly as one in a positive list does.
cat > "$FIXTURE_DIR/hardcoded-ignore-slug.yml" <<'FIXTURE'
name: fixture
on:
  pull_request:
    branches-ignore:
      - develop-oldslug
jobs:
  x:
    runs-on: ubuntu-latest
    steps:
      - run: echo hi
FIXTURE
run_test "hardcoded_slug_in_ignore_list_is_visible" "develop-oldslug" \
  "$(branches_for_trigger "$FIXTURE_DIR/hardcoded-ignore-slug.yml" pull_request-ignore)"

run_test "yaml_extension_is_parsed" "$(printf 'develop\nmain')" \
  "$(branches_for_trigger "$FIXTURE_DIR/dot-yaml-extension.yaml" pull_request)"

run_test "guard_predicate_does_not_match_developer_branch" "no" \
  "$(ignores_integration_branch "developer-branch" && echo yes || echo no)"

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
