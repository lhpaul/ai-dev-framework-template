#!/usr/bin/env bash
# test-run-advisory-checks.sh - coverage for run-advisory-checks.sh (#1572).
#
# run-advisory-checks.sh is a consumer extension point for pr-review-loop.sh:
# downstream projects may replace its no-op body with their own advisory
# checks. This suite therefore splits its assertions in two (#2168):
#
# - Caller contract, checked in every repository: a PR number is required, a
#   missing or empty one fails with usage on stderr and no stdout, and the
#   caller-shaped invocation (stderr discarded, exit status ignored) yields the
#   script's stdout unchanged. These hold for the shipped no-op and for any
#   replacement body.
# - Shipped no-op body, checked only in the template itself
#   (template.is_template: true): a successful run exits 0 and prints nothing.
#   A consumer whose body prints advisory stdout skips these checks.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"
SCRIPT_UNDER_TEST="$REPO_ROOT/scripts/development-workflow/run-advisory-checks.sh"
CONFIG_FILE="$REPO_ROOT/.ai-dev-workflow.yaml"
PASS_COUNT=0
FAIL_COUNT=0

# shellcheck source=scripts/development-workflow/workflow-lib.sh
source "$REPO_ROOT/scripts/development-workflow/workflow-lib.sh"

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf 'PASS: %s\n' "$1"
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf 'FAIL: %s\n' "$1" >&2
}

# run_script <args...> - sets STDOUT, STDERR and CODE separately.
run_script() {
  local err_file
  err_file="$(mktemp)"
  set +e
  STDOUT="$(bash "$SCRIPT_UNDER_TEST" "$@" 2>"$err_file")"
  CODE=$?
  set -e
  STDERR="$(cat "$err_file")"
  rm -f "$err_file"
}

# ---------------------------------------------------------------------------
# Caller contract (every repository)
# ---------------------------------------------------------------------------

run_script
if [ "$CODE" -ne 0 ]; then pass "missing PR number fails"; else fail "missing PR number fails"; fi
if grep -Fq "Usage:" <<<"$STDERR"; then pass "missing PR number prints usage on stderr"; else fail "missing PR number prints usage on stderr"; fi
if [ -z "$STDOUT" ]; then pass "missing PR number prints nothing on stdout"; else fail "missing PR number prints nothing on stdout"; fi

run_script ""
if [ "$CODE" -ne 0 ]; then pass "empty PR number fails"; else fail "empty PR number fails"; fi
if grep -Fq "Usage:" <<<"$STDERR"; then pass "empty PR number prints usage on stderr"; else fail "empty PR number prints usage on stderr"; fi

# pr-review-loop.sh runs the script with stderr discarded and its exit status
# ignored (run_project_advisory_checks, covered through the real caller in
# test-pr-review-loop.sh). Whatever the body prints or returns, that
# invocation shape must carry exactly the script's stdout: stderr never leaks
# into the advisory section, and stdout survives a non-zero exit.
run_script 1572
direct_stdout="$STDOUT"
direct_code="$CODE"
caller_output="$(bash "$SCRIPT_UNDER_TEST" 1572 2>/dev/null || true)"
if [ "$caller_output" = "$direct_stdout" ]; then pass "caller-shaped invocation yields the script's stdout only"; else fail "caller-shaped invocation yields the script's stdout only"; fi

# ---------------------------------------------------------------------------
# Shipped no-op body (template only)
# ---------------------------------------------------------------------------

if [ "$(workflow_template_is_template "$CONFIG_FILE")" = "true" ]; then
  if [ "$direct_code" -eq 0 ]; then pass "default body exits 0 with a PR number"; else fail "default body exits 0 with a PR number (exit=$direct_code)"; fi
  if [ -z "$direct_stdout" ]; then pass "default body prints no advisory output"; else fail "default body prints no advisory output"; fi
  if [ -z "$STDERR" ]; then pass "default body prints nothing to stderr"; else fail "default body prints nothing to stderr"; fi
  if [ -z "$caller_output" ]; then pass "default body yields an empty advisory section"; else fail "default body yields an empty advisory section"; fi
else
  printf 'SKIP: shipped no-op body checks - consumer-owned run-advisory-checks.sh\n'
fi

# ---------------------------------------------------------------------------
# Suite portability (template only; the nested runs set the guard below)
# ---------------------------------------------------------------------------

# Run a copy of this suite in a disposable repository so both sides of the
# split are proven: a consumer body that prints advisory stdout, writes stderr
# and exits non-zero passes the caller contract, and the same body under
# template mode fails the shipped no-op checks.
if [ "$(workflow_template_is_template "$CONFIG_FILE")" = "true" ] \
  && [ -z "${RUN_ADVISORY_CHECKS_SUITE_NESTED:-}" ]; then
  fixture_root="$(mktemp -d)"
  trap 'rm -rf "$fixture_root"' EXIT

  # make_fixture <dir> <is_template> - disposable repository with this suite,
  # workflow-lib.sh and a consumer-style advisory body.
  make_fixture() {
    local dir="$1"
    local is_template="$2"
    mkdir -p "$dir/scripts/development-workflow/tests"
    cp "$REPO_ROOT/scripts/development-workflow/workflow-lib.sh" "$dir/scripts/development-workflow/"
    cp "$SCRIPT_DIR/test-run-advisory-checks.sh" "$dir/scripts/development-workflow/tests/"
    printf 'schema_version: 2\n\ntemplate:\n  is_template: %s\n' "$is_template" > "$dir/.ai-dev-workflow.yaml"
    cat > "$dir/scripts/development-workflow/run-advisory-checks.sh" <<'EOF_CONSUMER_ADVISORY'
#!/usr/bin/env bash
set -euo pipefail
_pr_number="${1:?Usage: $0 <pr-number>}"
printf '\n\n**Advisory checks** _(informational - never blocks merge)_\n'
printf -- '- Dead exports for PR %s: none found\n' "$_pr_number"
printf 'consumer diagnostic\n' >&2
exit 3
EOF_CONSUMER_ADVISORY
  }

  make_fixture "$fixture_root/consumer" false
  set +e
  consumer_log="$(RUN_ADVISORY_CHECKS_SUITE_NESTED=1 bash "$fixture_root/consumer/scripts/development-workflow/tests/test-run-advisory-checks.sh" 2>&1)"
  consumer_code=$?
  set -e
  if [ "$consumer_code" -eq 0 ]; then pass "consumer body with advisory stdout passes the suite"; else fail "consumer body with advisory stdout passes the suite (exit=$consumer_code)"; printf '%s\n' "$consumer_log" >&2; fi
  if grep -Fq "SKIP: shipped no-op body checks" <<<"$consumer_log"; then pass "consumer run skips the shipped no-op body checks"; else fail "consumer run skips the shipped no-op body checks"; fi

  make_fixture "$fixture_root/template" true
  set +e
  template_log="$(RUN_ADVISORY_CHECKS_SUITE_NESTED=1 bash "$fixture_root/template/scripts/development-workflow/tests/test-run-advisory-checks.sh" 2>&1)"
  template_code=$?
  set -e
  if [ "$template_code" -ne 0 ]; then pass "template mode rejects a non-empty default body"; else fail "template mode rejects a non-empty default body"; fi
  if grep -Fq "FAIL: default body prints no advisory output" <<<"$template_log"; then pass "template mode names the pinned no-op check"; else fail "template mode names the pinned no-op check"; fi
  if grep -Eq "^FAIL: (missing|empty) PR number|^FAIL: caller-shaped" <<<"$template_log"; then fail "template mode keeps the caller contract green"; else pass "template mode keeps the caller contract green"; fi
fi

printf '\n%s passed, %s failed\n' "$PASS_COUNT" "$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
