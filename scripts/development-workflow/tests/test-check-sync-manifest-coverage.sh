#!/usr/bin/env bash
# test-check-sync-manifest-coverage.sh - tests for check-sync-manifest-coverage.py.
#
# Issue #1874: synced test suites read files sync-manifest.yaml did not ship
# (framework CI workflows, workflow runbooks), so a consumer that synced ran new
# tests against stale or missing files. This suite holds the template's own
# manifest to "every file a synced test reads is shipped, project-owned, or
# exempt with a reason", and pins the helper's extraction and
# required_additions rules on fixtures.
#
# covers: scripts/development-workflow/check-sync-manifest-coverage.py
# covers: scripts/development-workflow/select-sync-manifest-entries.py
# covers: sync-manifest.yaml
# covers: scripts/development-workflow/tests/test-*.sh
# covers: scripts/development-workflow/tests/test*.py

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"
CHECKER="$REPO_ROOT/scripts/development-workflow/check-sync-manifest-coverage.py"
SELECTOR="$REPO_ROOT/scripts/development-workflow/select-sync-manifest-entries.py"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

PASS_COUNT=0
FAIL_COUNT=0

run_test() {
  local name="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $name - expected '${expected}', got '${actual}'"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

# shellcheck source=scripts/development-workflow/workflow-lib.sh
source "$REPO_ROOT/scripts/development-workflow/workflow-lib.sh"

# run_checker <out-file> <args...>: prints the exit status; output goes to <out-file>.
run_checker() {
  local out="$1" status=0
  shift
  python3 "$CHECKER" "$@" >"$out" 2>&1 || status=$?
  printf '%s' "$status"
}

has_line() {
  # has_line <file> <fixed-string>: yes when a line contains the string.
  if grep -Fq -- "$2" "$1"; then echo yes; else echo no; fi
}

# ---------------------------------------------------------------------------
# Area 1: the template's own manifest covers every file its synced tests read
# ---------------------------------------------------------------------------
# A consumer's tree legitimately differs from the template's (its own tracked
# files, its own exemptions), so only the template asserts a clean result
# (#1631 pattern). The consumer-side use of the helper is the sync-template
# pre-flight diagnostic.
if [ "$(workflow_template_is_template "$REPO_ROOT/.ai-dev-workflow.yaml")" = "true" ]; then
  for role in single_repo workflow_hub product_repo; do
    out="$TMP_ROOT/real-$role.out"
    status="$(run_checker "$out" --repo-root "$REPO_ROOT" --role "$role")"
    run_test "template_manifest_covers_synced_test_reads_${role}" "0" "$status"
    if [ "$status" != "0" ]; then
      grep -E '^(UNCOVERED|ERROR)' "$out" | sed 's/^/    /' || true  # workflow-shell-guard: allow SH001 - diagnostic only
    fi
  done
  out="$TMP_ROOT/real-single.out"
  run_checker "$out" --repo-root "$REPO_ROOT" --role single_repo >/dev/null
  synced_count="$(awk -F= '/^SYNCED_TEST_COUNT=/{print $2; exit}' "$out")"
  if [ "${synced_count:-0}" -ge 50 ]; then
    run_test "template_scan_not_vacuous" "yes" "yes"
  else
    run_test "template_scan_not_vacuous" "yes" "only ${synced_count:-0} synced tests scanned"
  fi
  # The gaps #1874 reported stay closed.
  for path in \
    .github/workflows/pr-policy.yml \
    .github/workflows/shellcheck.yml \
    .github/workflows/workflow-tests.yml \
    .github/workflows/markdown-lint.yml \
    .github/workflows/closing-keyword-scope.yml \
    docs/testing/workflow/retrospective-protocol.smoke-test.md \
    docs/testing/workflow/tracker-type-field-classification.smoke-test.md; do
    run_test "manifest_ships_${path##*/}" "yes" \
      "$(python3 "$SELECTOR" --manifest "$REPO_ROOT/sync-manifest.yaml" --role single_repo | grep -Fq " path=$path " && echo yes || echo no)"
  done
else
  echo "SKIP: template manifest coverage (consumer repository; template.is_template is not true)"
fi

# ---------------------------------------------------------------------------
# Fixture template
# ---------------------------------------------------------------------------
FIX="$TMP_ROOT/template"
mkdir -p "$FIX/scripts/development-workflow/tests" "$FIX/.github/workflows" "$FIX/docs/runbooks" "$FIX/docs/data"
cp "$SELECTOR" "$FIX/scripts/development-workflow/"
cat >"$FIX/sync-manifest.yaml" <<'MANIFEST'
schema_version: 1

mode_scopes:
  shared:
    label: Shared
  hub_only:
    label: Hub only
  product_repo_injection:
    label: Product repository injection

categories:
  always_sync:
    - path: scripts/development-workflow/
      glob: "**/*"
      mode_scope: hub_only
    - path: docs/runbooks/shipped.md
      mode_scope: shared
  special_handling:
    - path: .github/workflows/shipped.yml
      mode_scope: shared
  project_specific:
    - path: AGENTS.md
      mode_scope: product_repo_injection
    - path: .ai-dev-workflow.yaml
      mode_scope: shared

required_additions:
  - path: .ai-dev-workflow.yaml
    when_pattern: '^\s*stop_conditions:'
    must_contain: push_verification_failed
    introduced_in: "0.45.0"
    read_by: scripts/development-workflow/tests/test-thing.sh
    description: >
      add the stop condition.

sync_coverage_exemptions:
  - path: docs/data/named-only.md
    reason: named as data only
MANIFEST
for f in .github/workflows/shipped.yml .github/workflows/unshipped.yml .github/workflows/via-var.yml \
  .github/workflows/comment-only.yml .github/workflows/covers-only.yml .github/workflows/json-only.yml \
  .github/workflows/list-second.yml .github/workflows/py-join.yml \
  docs/runbooks/shipped.md docs/data/named-only.md AGENTS.md .ai-dev-workflow.yaml; do
  printf 'x\n' >"$FIX/$f"
done

write_fixture_test() {
  cat >"$FIX/scripts/development-workflow/tests/test-thing.sh" <<'TEST'
#!/usr/bin/env bash
# covers: .github/workflows/covers-only.yml
# A comment naming .github/workflows/comment-only.yml is not a read.
REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
WF_DIR="$REPO_ROOT/.github/workflows"
grep -q x "$REPO_ROOT/.github/workflows/shipped.yml"
grep -q x "$WF_DIR/via-var.yml"
grep -q x docs/runbooks/shipped.md
grep -q x "$REPO_ROOT/AGENTS.md"
printf '%s\n' '{"path": ".github/workflows/json-only.yml"}'
printf '%s\n' '{"files": ["docs/data/named-only.md", ".github/workflows/list-second.yml"]}'
echo docs/data/named-only.md
TEST
  cat >"$FIX/scripts/development-workflow/tests/test_thing.py" <<'TEST'
from pathlib import Path
REPO_ROOT = Path(__file__).resolve().parents[3]
TEXT = (REPO_ROOT / ".github" / "workflows" / "py-join.yml").read_text()
TEST
}
write_fixture_test
git -C "$FIX" init -q
git -C "$FIX" add -A

# ---------------------------------------------------------------------------
# Area 2: extraction and classification
# ---------------------------------------------------------------------------
out="$TMP_ROOT/fixture.out"
status="$(run_checker "$out" --repo-root "$FIX" --role single_repo)"
run_test "uncovered_reads_exit_1" "1" "$status"
run_test "result_gaps_found" "yes" "$(has_line "$out" "RESULT=gaps_found")"
run_test "direct_repo_root_read_covered_not_reported" "no" "$(has_line "$out" "path=.github/workflows/shipped.yml ")"
run_test "variable_resolved_read_uncovered" "yes" "$(has_line "$out" "UNCOVERED path=.github/workflows/via-var.yml")"
run_test "covers_header_counts_as_read" "yes" "$(has_line "$out" "UNCOVERED path=.github/workflows/covers-only.yml")"
run_test "plain_comment_ignored" "no" "$(has_line "$out" "comment-only.yml")"
run_test "json_data_literal_ignored" "no" "$(has_line "$out" "json-only.yml")"
run_test "later_list_element_still_counted" "yes" "$(has_line "$out" "UNCOVERED path=.github/workflows/list-second.yml")"
run_test "python_path_join_read_detected" "yes" "$(has_line "$out" "UNCOVERED path=.github/workflows/py-join.yml read_by=test_thing.py")"
run_test "project_specific_any_scope_is_project_owned" "yes" "$(has_line "$out" "PROJECT_OWNED path=AGENTS.md entry=AGENTS.md")"
run_test "exemption_reported_as_exempt" "yes" "$(has_line "$out" "EXEMPT path=docs/data/named-only.md")"
run_test "uncovered_count" "yes" "$(has_line "$out" "UNCOVERED_COUNT=4")"

out="$TMP_ROOT/fixture-show.out"
run_checker "$out" --repo-root "$FIX" --role single_repo --show-covered >/dev/null
run_test "show_covered_lists_relative_read" "yes" "$(has_line "$out" "COVERED path=docs/runbooks/shipped.md entry=docs/runbooks/shipped.md")"

# A role that does not receive the tests has nothing to check.
out="$TMP_ROOT/fixture-product.out"
status="$(run_checker "$out" --repo-root "$FIX" --role product_repo)"
run_test "role_without_synced_tests_clean" "0" "$status"
run_test "role_without_synced_tests_count" "yes" "$(has_line "$out" "SYNCED_TEST_COUNT=0")"

# Shipping the gaps makes the fixture clean.
python3 - "$FIX/sync-manifest.yaml" <<'PY'
import sys
from pathlib import Path
path = Path(sys.argv[1])
text = path.read_text()
text = text.replace(
    "  project_specific:\n",
    "    - path: .github/workflows/via-var.yml\n      mode_scope: shared\n"
    "    - path: .github/workflows/covers-only.yml\n      mode_scope: shared\n"
    "    - path: .github/workflows/list-second.yml\n      mode_scope: shared\n"
    "    - path: .github/workflows/py-join.yml\n      mode_scope: shared\n"
    "  project_specific:\n",
)
path.write_text(text)
PY
out="$TMP_ROOT/fixture-fixed.out"
status="$(run_checker "$out" --repo-root "$FIX" --role single_repo)"
run_test "shipping_gaps_clears_result" "0" "$status"
run_test "shipping_gaps_result_clean" "yes" "$(has_line "$out" "RESULT=clean")"

# ---------------------------------------------------------------------------
# Area 3: required_additions against a consumer checkout
# ---------------------------------------------------------------------------
CONSUMER="$TMP_ROOT/consumer"
mkdir -p "$CONSUMER"
printf 'guardrails:\n  stop_conditions:\n    - failing_ci\n' >"$CONSUMER/.ai-dev-workflow.yaml"
out="$TMP_ROOT/consumer-missing.out"
status="$(run_checker "$out" --repo-root "$FIX" --role single_repo --consumer-root "$CONSUMER")"
run_test "missing_required_addition_exit_1" "1" "$status"
run_test "missing_required_addition_reported" "yes" "$(has_line "$out" "REQUIRED_ADDITION_MISSING path=.ai-dev-workflow.yaml must_contain=push_verification_failed introduced_in=0.45.0")"

printf 'guardrails:\n  stop_conditions:\n    - failing_ci\n    - push_verification_failed\n' >"$CONSUMER/.ai-dev-workflow.yaml"
out="$TMP_ROOT/consumer-present.out"
status="$(run_checker "$out" --repo-root "$FIX" --role single_repo --consumer-root "$CONSUMER")"
run_test "present_required_addition_exit_0" "0" "$status"
run_test "present_required_addition_reported" "yes" "$(has_line "$out" "REQUIRED_ADDITION_PRESENT path=.ai-dev-workflow.yaml")"

printf 'guardrails:\n  mode: advisory\n' >"$CONSUMER/.ai-dev-workflow.yaml"
out="$TMP_ROOT/consumer-na.out"
status="$(run_checker "$out" --repo-root "$FIX" --role single_repo --consumer-root "$CONSUMER")"
run_test "when_pattern_absent_not_applicable_exit_0" "0" "$status"
run_test "when_pattern_absent_reported" "yes" "$(has_line "$out" "REQUIRED_ADDITION_NOT_APPLICABLE path=.ai-dev-workflow.yaml must_contain=push_verification_failed introduced_in=0.45.0 reason=when_pattern_absent")"

rm "$CONSUMER/.ai-dev-workflow.yaml"
out="$TMP_ROOT/consumer-absent.out"
status="$(run_checker "$out" --repo-root "$FIX" --role single_repo --consumer-root "$CONSUMER")"
run_test "absent_file_not_applicable_exit_0" "0" "$status"
run_test "absent_file_reported" "yes" "$(has_line "$out" "reason=file_absent")"

# ---------------------------------------------------------------------------
# Area 4: input errors fail closed
# ---------------------------------------------------------------------------
printf 'categories:\n  always_sync:\n    - path: x\n      mode_scope: shared\n' >"$TMP_ROOT/bad-manifest.yaml"
out="$TMP_ROOT/bad.out"
status="$(run_checker "$out" --repo-root "$FIX" --manifest "$TMP_ROOT/bad-manifest.yaml")"
run_test "malformed_manifest_exit_2" "2" "$status"
run_test "malformed_manifest_error" "yes" "$(has_line "$out" "ERROR: manifest is missing mode_scopes")"

# An invalid when_pattern is an input error (exit 2), never "gaps found" (exit 1).
BAD_REGEX_MANIFEST="$TMP_ROOT/bad-regex-manifest.yaml"
sed "s/when_pattern: '.*'/when_pattern: '(unclosed'/" "$FIX/sync-manifest.yaml" >"$BAD_REGEX_MANIFEST"
printf 'guardrails:\n  stop_conditions:\n    - failing_ci\n' >"$CONSUMER/.ai-dev-workflow.yaml"
out="$TMP_ROOT/bad-regex.out"
status="$(run_checker "$out" --repo-root "$FIX" --manifest "$BAD_REGEX_MANIFEST" --consumer-root "$CONSUMER")"
run_test "invalid_when_pattern_exit_2" "2" "$status"
run_test "invalid_when_pattern_error" "yes" "$(has_line "$out" "has an invalid when_pattern")"

# A consumer root that does not exist must not pass as "nothing applies".
out="$TMP_ROOT/missing-consumer.out"
status="$(run_checker "$out" --repo-root "$FIX" --consumer-root "$TMP_ROOT/no-such-checkout")"
run_test "missing_consumer_root_exit_2" "2" "$status"
run_test "missing_consumer_root_error" "yes" "$(has_line "$out" "is not a directory")"

# An exemption silences a gap, so one without a reason is refused (exit 2).
NO_REASON_MANIFEST="$TMP_ROOT/no-reason-manifest.yaml"
grep -v '^    reason: named as data only$' "$FIX/sync-manifest.yaml" >"$NO_REASON_MANIFEST"
out="$TMP_ROOT/no-reason.out"
status="$(run_checker "$out" --repo-root "$FIX" --manifest "$NO_REASON_MANIFEST")"
run_test "exemption_without_reason_exit_2" "2" "$status"
run_test "exemption_without_reason_error" "yes" "$(has_line "$out" "needs a nonblank path and reason")"

# A section written as a mapping instead of a list must not parse as empty
# (which would turn the required-addition check off).
MAPPING_MANIFEST="$TMP_ROOT/mapping-manifest.yaml"
python3 - "$FIX/sync-manifest.yaml" "$MAPPING_MANIFEST" <<'PY'
import sys
from pathlib import Path
text = Path(sys.argv[1]).read_text()
needle = "required_additions:\n  - path: .ai-dev-workflow.yaml\n"
assert needle in text
Path(sys.argv[2]).write_text(text.replace(needle, "required_additions:\n  path: .ai-dev-workflow.yaml\n", 1))
PY
out="$TMP_ROOT/mapping.out"
status="$(run_checker "$out" --repo-root "$FIX" --manifest "$MAPPING_MANIFEST" --consumer-root "$CONSUMER")"
run_test "section_without_list_exit_2" "2" "$status"
run_test "section_without_list_error" "yes" "$(has_line "$out" "expected a list of '- key: value' entries")"
# The well-formed list still evaluates the addition (the failing/passing pair).
out="$TMP_ROOT/mapping-ok.out"
status="$(run_checker "$out" --repo-root "$FIX" --consumer-root "$CONSUMER")"
run_test "section_as_list_still_checked" "1" "$status"
run_test "section_as_list_reports_missing" "yes" "$(has_line "$out" "REQUIRED_ADDITION_MISSING path=.ai-dev-workflow.yaml")"

# An inline section value is refused; an explicit empty list is accepted.
for inline_case in "invalid:2" "[{path: x}]:2" "[]:0"; do
  inline_value="${inline_case%:*}"
  inline_expected="${inline_case##*:}"
  INLINE_MANIFEST="$TMP_ROOT/inline-manifest.yaml"
  python3 - "$FIX/sync-manifest.yaml" "$INLINE_MANIFEST" "$inline_value" <<'PY'
import sys
from pathlib import Path
text = Path(sys.argv[1]).read_text()
head, sep, tail = text.partition("required_additions:\n")
assert sep
# Drop the block entries up to the next top-level key, keep the rest.
rest = tail.split("\nsync_coverage_exemptions:", 1)[1]
Path(sys.argv[2]).write_text(head + f"required_additions: {sys.argv[3]}\n\nsync_coverage_exemptions:" + rest)
PY
  out="$TMP_ROOT/inline.out"
  status="$(run_checker "$out" --repo-root "$FIX" --manifest "$INLINE_MANIFEST" --consumer-root "$CONSUMER")"
  if [ "$inline_expected" = "0" ]; then
    # Empty list: nothing to check, and the fixture's coverage gaps are fixed
    # above, so the run is clean.
    run_test "inline_section_${inline_value}_accepted" "0" "$status"
  else
    run_test "inline_section_${inline_value}_refused" "2" "$status"
    run_test "inline_section_${inline_value}_error" "yes" "$(has_line "$out" "inline values are not supported")"
  fi
done

# A nested list inside an entry is refused rather than split into two entries.
NESTED_MANIFEST="$TMP_ROOT/nested-manifest.yaml"
python3 - "$FIX/sync-manifest.yaml" "$NESTED_MANIFEST" <<'PY'
import sys
from pathlib import Path
text = Path(sys.argv[1]).read_text()
needle = "    must_contain: push_verification_failed\n"
assert needle in text
Path(sys.argv[2]).write_text(text.replace(needle, needle + "    extra:\n      - nested\n"))
PY
out="$TMP_ROOT/nested.out"
status="$(run_checker "$out" --repo-root "$FIX" --manifest "$NESTED_MANIFEST")"
run_test "nested_list_entry_exit_2" "2" "$status"
run_test "nested_list_entry_error" "yes" "$(has_line "$out" "nested lists are not supported")"

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
