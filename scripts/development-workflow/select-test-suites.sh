#!/usr/bin/env bash
#
# select-test-suites.sh — resolve which workflow test suites a change set needs.
#
# Issue #1537: CI previously ran a hard-coded list of six suites behind a path
# filter, so a PR that changed any other workflow script showed a fully green
# check rollup while its own suite never executed. This script replaces the
# hard-coded list with a mapping derived from the repository itself, so a newly
# added suite is wired up the moment it lands (AC-2).
#
# ── How a suite declares what it covers ─────────────────────────────────────
#
# 1. Self-declaration (authoritative). A suite may declare the paths it
#    exercises with `# covers:` header lines within its first
#    COVERS_HEADER_LINES lines:
#
#        # covers: scripts/development-workflow/batch-merge.sh
#        # covers: docs/workflow/development-workflow/protocols/94-*.md
#
#    Multiple lines accumulate, and one line may list several space-separated
#    patterns. The declaration lives next to the test rather than in a central
#    map, so it cannot drift out of sync with a file it no longer describes.
#
# 2. Naming convention (default). A suite with no `# covers:` header covers
#    scripts/development-workflow/<name>.sh and <name>.py for a suite named
#    test-<name>.sh. That covers most suites; the ones testing protocols, docs,
#    or cross-cutting hub contracts rather than one script need the header.
#
# In both cases a suite always covers its own file and its own fixture
# directory, so editing a test runs it.
#
# ── Pattern syntax ──────────────────────────────────────────────────────────
#
# Patterns are repository-root-relative and glob-like, matched precisely rather
# than by shell `case` semantics:
#
#     **  matches any characters, including '/'
#     *   matches any characters except '/'
#     ?   matches a single character except '/'
#
# So 'scripts/development-workflow/hub-*.sh' matches hub-status.sh but NOT
# tests/hub-thing.sh, and 'docs/workflow/**' matches at any depth below it.
#
# ── Usage ───────────────────────────────────────────────────────────────────
#
#   select-test-suites.sh --changed-files <path>   # '-' reads stdin
#   select-test-suites.sh --all
#   select-test-suites.sh --report-gaps
#   select-test-suites.sh --print-map
#
# Options:
#   --changed-files <path>  File with one changed repo-relative path per line.
#                           Emits the suites that change set requires.
#   --all                   Emit every suite (the scheduled full run).
#   --report-gaps           Emit the coverage-gap report (AC-3): workflow
#                           scripts with no suite, and suites that no PR change
#                           set can select. Always exits 0 — the report is
#                           visibility, not a gate.
#   --print-map             Emit 'suite<TAB>pattern' for each resolved mapping.
#   --format <lines|json>   Output format for suite lists. Default 'lines'.
#
# Output (lines format): repo-relative suite paths, one per line, sorted.
# Exit codes: 0 success, 2 usage error.
#
# Portability: written for bash 3.2 (the macOS system bash) — no mapfile,
# readarray, or associative arrays — because agents run this locally as well as
# in CI.

set -euo pipefail

die() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 2
}

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
if [ -n "${SELECT_TEST_SUITES_REPO_ROOT:-}" ]; then
  REPO_ROOT="$SELECT_TEST_SUITES_REPO_ROOT"
else
  REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null)" \
    || die "could not resolve the repository root from $SCRIPT_DIR (not a git checkout?); set SELECT_TEST_SUITES_REPO_ROOT to override"
fi
[ -d "$REPO_ROOT" ] || die "resolved repository root is not a directory: $REPO_ROOT"
TESTS_DIR="scripts/development-workflow/tests"
SCRIPTS_DIR="scripts/development-workflow"

# How far into a suite the `# covers:` header is honoured. Keeps the parse
# bounded and stops a `# covers:` mention deep inside test data from silently
# widening a suite's declared surface.
COVERS_HEADER_LINES=60

# Changing any of these invalidates the per-suite mapping itself, or is a shared
# dependency of most suites, so a change to one runs the full set rather than a
# selected subset. Deliberately conservative: the cost of over-running is wall
# clock, the cost of under-running is a green check that proves nothing.
FULL_RUN_TRIGGER_PATTERNS="$SCRIPTS_DIR/workflow-lib.sh
$SCRIPTS_DIR/select-test-suites.sh
$TESTS_DIR/fixtures/**
.github/workflows/workflow-tests.yml"

usage() {
  sed -n '3,66p' "$0" | sed 's/^# \{0,1\}//'
}

# ── Pattern matching ────────────────────────────────────────────────────────

# glob_to_regex <pattern> — convert a covers pattern to an anchored ERE.
glob_to_regex() {
  local pattern="$1" out="" i=0 ch next
  while [ "$i" -lt "${#pattern}" ]; do
    ch="${pattern:$i:1}"
    case "$ch" in
      '*')
        next="${pattern:$((i + 1)):1}"
        if [ "$next" = '*' ]; then
          out="${out}.*"
          i=$((i + 2))
          continue
        fi
        out="${out}[^/]*"
        ;;
      '?') out="${out}[^/]" ;;
      # Escape every ERE metacharacter that can legally appear in a path.
      '.' | '+' | '(' | ')' | '[' | ']' | '{' | '}' | '^' | '$' | '|' | '\')
        out="${out}\\$ch"
        ;;
      *) out="${out}${ch}" ;;
    esac
    i=$((i + 1))
  done
  printf '^%s$' "$out"
}

# path_matches <path> <pattern>
path_matches() {
  local path="$1" regex
  regex="$(glob_to_regex "$2")"
  [[ "$path" =~ $regex ]]
}

# ── Mapping ─────────────────────────────────────────────────────────────────

# list_suites — every suite, repo-relative, one per line, sorted.
list_suites() {
  ( cd "$REPO_ROOT" \
    && find "$TESTS_DIR" -maxdepth 1 -type f -name 'test-*.sh' \
    | LC_ALL=C sort )
}

# list_workflow_scripts — the scripts a suite could cover (excludes tests/).
list_workflow_scripts() {
  ( cd "$REPO_ROOT" \
    && find "$SCRIPTS_DIR" -maxdepth 1 -type f \( -name '*.sh' -o -name '*.py' \) \
    | LC_ALL=C sort )
}

# assert_suites_readable — verify every suite can be read, in the CURRENT
# shell, before anything starts consuming suite_patterns.
#
# This preflight exists because `die` cannot abort the program from where the
# headers are actually read. suite_patterns is consumed as
# `done < <(suite_patterns "$suite")`, and it reads each header the same way;
# a process substitution runs in a subshell, so an `exit` there ends only that
# subshell. The reading loop then simply sees EOF, treats the suite as having
# declared nothing, silently falls back to the naming convention, and the
# selector exits 0 — under-selecting suites while reporting success, which is
# the precise failure this script exists to end. Checking up front, in the
# parent shell, is what makes the failure fatal.
assert_suites_readable() {
  local suite
  while IFS= read -r suite; do
    [ -n "$suite" ] || continue
    [ -r "$REPO_ROOT/$suite" ] || die "cannot read test suite: $REPO_ROOT/$suite"
  done < <(list_suites)
}

# read_suite_header <suite-path> — the first COVERS_HEADER_LINES lines of a
# suite. Defense in depth behind assert_suites_readable: reaching the error
# here means the file became unreadable mid-run.
read_suite_header() {
  local suite="$1"
  [ -r "$REPO_ROOT/$suite" ] || die "cannot read test suite: $REPO_ROOT/$suite"
  head -n "$COVERS_HEADER_LINES" "$REPO_ROOT/$suite" \
    || die "failed to read the header of: $REPO_ROOT/$suite"
}

# suite_patterns <suite-path> — the patterns a suite covers, one per line.
suite_patterns() {
  local suite="$1" base declared=0 line rest pattern candidate
  base="$(basename "$suite" .sh)"
  base="${base#test-}"

  # A suite always covers itself and its own fixture directory.
  printf '%s\n' "$suite"
  printf '%s\n' "$TESTS_DIR/fixtures/$base/**"

  while IFS= read -r line; do
    case "$line" in
      '#'*covers:*)
        rest="${line#*covers:}"
        # Word-split the pattern list WITHOUT pathname expansion. Unquoted
        # expansion would otherwise glob each pattern against the working
        # directory: 'hub-*.sh' would silently become the files that happen to
        # exist right now, and '**' would collapse to a single '*' under bash
        # 3.2. Patterns must reach path_matches verbatim.
        set -f
        # shellcheck disable=SC2086  # deliberate word-splitting; globbing disabled above
        for pattern in $rest; do
          [ -n "$pattern" ] || continue
          declared=1
          printf '%s\n' "$pattern"
        done
        set +f
        ;;
    esac
    # A suite that cannot be read must fail loudly. Swallowing the error here
    # would drop its '# covers:' mapping and silently fall back to the naming
    # convention — under-selecting suites without any signal, which is the
    # exact failure mode this script exists to end.
  done < <(read_suite_header "$suite")

  if [ "$declared" -eq 0 ]; then
    for candidate in "$SCRIPTS_DIR/$base.sh" "$SCRIPTS_DIR/$base.py"; do
      [ -f "$REPO_ROOT/$candidate" ] && printf '%s\n' "$candidate"
    done
  fi
  return 0
}

# suite_has_mapping <suite> — true when the suite covers something beyond
# itself, i.e. some PR change set other than editing the test can select it.
suite_has_mapping() {
  local suite="$1" pattern found=0
  # Drain suite_patterns rather than returning on the first hit: returning
  # early closes the process substitution while the producer is still
  # writing, and its next printf fails with EPIPE/EINTR noise on stderr.
  while IFS= read -r pattern; do
    case "$pattern" in
      "$suite" | "$TESTS_DIR/fixtures/"*) ;;
      *) found=1 ;;
    esac
  done < <(suite_patterns "$suite")
  [ "$found" -eq 1 ]
}

# ── Output ──────────────────────────────────────────────────────────────────

# emit_suites <format> — reads a newline-delimited suite list on stdin.
emit_suites() {
  local format="$1" line escaped first=1
  if [ "$format" != json ]; then
    cat
    return 0
  fi
  printf '['
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    [ "$first" -eq 1 ] || printf ','
    first=0
    # Escape backslash first, then the quote, so a path containing either
    # still yields valid JSON. The workflow feeds this straight into
    # fromJSON(), where a malformed string would fail the whole run.
    escaped="${line//\\/\\\\}"
    escaped="${escaped//\"/\\\"}"
    printf '"%s"' "$escaped"
  done
  printf ']\n'
}

# ── Modes ───────────────────────────────────────────────────────────────────

mode_all() {
  list_suites | emit_suites "$1"
}

mode_changed() {
  local format="$1" source="$2"
  local changed_raw changed="" line pattern suite matched file

  if [ "$source" = '-' ]; then
    changed_raw="$(cat)"
  else
    [ -f "$source" ] || die "changed-files file not found: $source"
    changed_raw="$(cat "$source")"
  fi

  # Normalise: drop blanks and any leading './'.
  while IFS= read -r line; do
    line="${line#./}"
    [ -n "$line" ] || continue
    changed="$changed$line
"
  done <<EOF
$changed_raw
EOF

  # A full-run trigger short-circuits selection.
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    while IFS= read -r pattern; do
      [ -n "$pattern" ] || continue
      if path_matches "$file" "$pattern"; then
        printf 'INFO: full run triggered by %s (matches %s)\n' "$file" "$pattern" >&2
        mode_all "$format"
        return 0
      fi
    done <<EOF
$FULL_RUN_TRIGGER_PATTERNS
EOF
  done <<EOF
$changed
EOF

  {
    while IFS= read -r suite; do
      [ -n "$suite" ] || continue
      matched=0
      while IFS= read -r pattern; do
        [ -n "$pattern" ] || continue
        [ "$matched" -eq 1 ] && continue
        while IFS= read -r file; do
          [ -n "$file" ] || continue
          if path_matches "$file" "$pattern"; then
            matched=1
            break
          fi
        done <<EOF
$changed
EOF
      done < <(suite_patterns "$suite")
      if [ "$matched" -eq 1 ]; then
        printf '%s\n' "$suite"
      fi
    done < <(list_suites)
    # Guard the brace group's own exit status: 'set -o pipefail' would
    # otherwise surface a falsy last command here as a selector failure.
    true
  } | emit_suites "$format"
}

mode_report_gaps() {
  local all_patterns script suite pattern covered
  local uncovered="" unreachable=""
  local script_count=0 suite_count=0 uncovered_count=0 unreachable_count=0

  all_patterns="$(
    while IFS= read -r suite; do
      [ -n "$suite" ] || continue
      suite_patterns "$suite"
    done < <(list_suites)
  )"

  while IFS= read -r script; do
    [ -n "$script" ] || continue
    script_count=$((script_count + 1))
    covered=0
    while IFS= read -r pattern; do
      [ -n "$pattern" ] || continue
      if path_matches "$script" "$pattern"; then
        covered=1
        break
      fi
    done <<EOF
$all_patterns
EOF
    if [ "$covered" -eq 0 ]; then
      uncovered="$uncovered  $script
"
      uncovered_count=$((uncovered_count + 1))
    fi
  done < <(list_workflow_scripts)

  while IFS= read -r suite; do
    [ -n "$suite" ] || continue
    suite_count=$((suite_count + 1))
    if ! suite_has_mapping "$suite"; then
      unreachable="$unreachable  $suite
"
      unreachable_count=$((unreachable_count + 1))
    fi
  done < <(list_suites)

  printf '=== Test coverage gaps (issue #1537 AC-3) ===\n\n'
  printf 'Workflow scripts with no test suite: %s of %s\n' \
    "$uncovered_count" "$script_count"
  if [ "$uncovered_count" -gt 0 ]; then
    printf '%s' "$uncovered"
    printf '\nThese scripts can change without any suite running. Adding a\n'
    printf 'test-<name>.sh suite closes the gap with no workflow edit.\n'
  fi
  printf '\nSuites no change set can select: %s of %s\n' \
    "$unreachable_count" "$suite_count"
  if [ "$unreachable_count" -gt 0 ]; then
    printf '%s' "$unreachable"
    printf '\nThese run only in the scheduled full run or when the suite file\n'
    printf 'itself changes. Add a "# covers:" header to map one to its subject.\n'
  fi
  printf '\n'
  printf 'UNCOVERED_SCRIPT_COUNT=%s\n' "$uncovered_count"
  printf 'UNREACHABLE_SUITE_COUNT=%s\n' "$unreachable_count"
  printf 'TOTAL_SCRIPT_COUNT=%s\n' "$script_count"
  printf 'TOTAL_SUITE_COUNT=%s\n' "$suite_count"
}

mode_print_map() {
  local suite pattern
  while IFS= read -r suite; do
    [ -n "$suite" ] || continue
    while IFS= read -r pattern; do
      [ -n "$pattern" ] || continue
      printf '%s\t%s\n' "$suite" "$pattern"
    done < <(suite_patterns "$suite")
  done < <(list_suites)
}

# ── Entry point ─────────────────────────────────────────────────────────────

main() {
  local mode="" changed_source="" format="lines"

  while [ $# -gt 0 ]; do
    case "$1" in
      --changed-files)
        [ $# -ge 2 ] || die "--changed-files requires a value"
        mode="changed"
        changed_source="$2"
        shift 2
        ;;
      --all) mode="all"; shift ;;
      --report-gaps) mode="gaps"; shift ;;
      --print-map) mode="map"; shift ;;
      --format)
        [ $# -ge 2 ] || die "--format requires a value"
        format="$2"
        case "$format" in
          lines | json) ;;
          *) die "unsupported --format '$format' (expected lines or json)" ;;
        esac
        shift 2
        ;;
      -h | --help) usage; exit 0 ;;
      *) die "unknown argument '$1'" ;;
    esac
  done

  assert_suites_readable

  case "$mode" in
    all) mode_all "$format" ;;
    changed) mode_changed "$format" "$changed_source" ;;
    gaps) mode_report_gaps ;;
    map) mode_print_map ;;
    *) die "no mode selected (expected --changed-files, --all, --report-gaps, or --print-map)" ;;
  esac
}

main "$@"
