#!/usr/bin/env bash
# test-workflow-tests-nightly-gate.sh - schedule gate + PR path filter for
# workflow-tests.yml (#1996, #1997).
# covers: .github/workflows/workflow-tests.yml
# covers: sync-manifest.yaml
#
# The nightly cron cannot be conditioned on `on.schedule`, so every job must
# skip schedule events in consumer repos unless WORKFLOW_TESTS_NIGHTLY_ENABLED
# compares equal to 'true' under GitHub Actions' case-insensitive `==`
# (true/True/TRUE opt in; any other value or absence keeps the nightly off).
# This suite parses the workflow YAML and evaluates the job `if:` expressions
# across event × repository × variable cases.
#
# #1997: pull_request must be path-filtered to exactly
# scripts/development-workflow/** and .github/workflows/workflow-tests.yml
# (branches unchanged; schedule / workflow_dispatch untouched). A docs-only
# change set must match no filter; covered scripts and this workflow must.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"
WORKFLOW_FILE="$REPO_ROOT/.github/workflows/workflow-tests.yml"
MANIFEST_FILE="$REPO_ROOT/sync-manifest.yaml"

pass=0
fail=0
run_test() {
  local name="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "PASS: $name"
    pass=$((pass + 1))
  else
    echo "FAIL: $name - expected '$expected', got '$actual'"
    fail=$((fail + 1))
  fi
}

if [ ! -r "$WORKFLOW_FILE" ]; then
  echo "FAIL: workflow missing: $WORKFLOW_FILE"
  exit 1
fi
if [ ! -r "$MANIFEST_FILE" ]; then
  echo "FAIL: sync-manifest missing: $MANIFEST_FILE"
  exit 1
fi

# ---------------------------------------------------------------------------
# Static: schedule trigger still present; PR/dispatch unchanged presence
# ---------------------------------------------------------------------------
if grep -qE '^[[:space:]]*schedule:' "$WORKFLOW_FILE"; then
  run_test "schedule_trigger_present" "yes" "yes"
else
  run_test "schedule_trigger_present" "yes" "no"
fi
if grep -qE '^[[:space:]]*- cron:' "$WORKFLOW_FILE"; then
  run_test "cron_entry_present" "yes" "yes"
else
  run_test "cron_entry_present" "yes" "no"
fi
if grep -qF "workflow_dispatch:" "$WORKFLOW_FILE"; then
  run_test "workflow_dispatch_present" "yes" "yes"
else
  run_test "workflow_dispatch_present" "yes" "no"
fi
if grep -qF "pull_request:" "$WORKFLOW_FILE"; then
  run_test "pull_request_present" "yes" "yes"
else
  run_test "pull_request_present" "yes" "no"
fi

# ---------------------------------------------------------------------------
# pull_request path filter (#1997): exactly two paths; branches unchanged
# ---------------------------------------------------------------------------
if ! python3 -c 'import yaml' 2>/dev/null; then
  echo "FAIL: PyYAML required to parse pull_request paths"
  fail=$((fail + 1))
  echo ""
  echo "Results: $pass passed, $fail failed"
  exit 1
fi

path_filter_out="$(python3 - "$WORKFLOW_FILE" <<'PYPATH'
import sys

try:
    import yaml
except ImportError:
    print("ERROR: PyYAML missing", file=sys.stderr)
    sys.exit(3)

path = sys.argv[1]
with open(path, encoding="utf-8") as fh:
    doc = yaml.safe_load(fh)

if not isinstance(doc, dict):
    print("ERROR: workflow is not a mapping", file=sys.stderr)
    sys.exit(4)

triggers = doc.get("on", doc.get(True, {}))
if not isinstance(triggers, dict):
    print("ERROR: on: missing", file=sys.stderr)
    sys.exit(4)

pr = triggers.get("pull_request")
if not isinstance(pr, dict):
    print("ERROR: pull_request block missing or not a mapping", file=sys.stderr)
    sys.exit(4)

expected_branches = ["develop", "develop-**", "main"]
branches = list(pr.get("branches") or [])
paths = list(pr.get("paths") or [])
expected_paths = [
    "scripts/development-workflow/**",
    ".github/workflows/workflow-tests.yml",
]

print("BRANCHES\t%s" % ("|".join(branches)))
print("BRANCHES_OK\t%s" % ("yes" if branches == expected_branches else "no"))
print("PATHS\t%s" % ("|".join(paths)))
print("PATHS_OK\t%s" % ("yes" if paths == expected_paths else "no"))
print("PATHS_COUNT\t%d" % len(paths))

# schedule / workflow_dispatch must remain present and not gain a paths key.
# A bare `workflow_dispatch:` parses as None; key presence is what matters.
sched_present = "schedule" in triggers
dispatch_present = "workflow_dispatch" in triggers
sched = triggers.get("schedule")
dispatch = triggers.get("workflow_dispatch")
print("SCHEDULE_OK\t%s" % ("yes" if sched_present else "no"))
print("DISPATCH_OK\t%s" % ("yes" if dispatch_present else "no"))

# Neither schedule nor workflow_dispatch should carry pull_request-style paths
# (schedule is a list of cron maps; dispatch is null or a mapping without paths).
sched_has_paths = False
if isinstance(sched, list):
    for item in sched:
        if isinstance(item, dict) and "paths" in item:
            sched_has_paths = True
elif isinstance(sched, dict) and "paths" in sched:
    sched_has_paths = True
dispatch_has_paths = isinstance(dispatch, dict) and "paths" in dispatch
print("SCHEDULE_NO_PATHS\t%s" % ("yes" if not sched_has_paths else "no"))
print("DISPATCH_NO_PATHS\t%s" % ("yes" if not dispatch_has_paths else "no"))

# Behavioral: GitHub path filters use fnmatch-style ** (minimatch).
# Model: a change set starts the workflow iff any changed path matches any
# filter pattern.
import fnmatch


def matches_any(changed_path, patterns):
    for pat in patterns:
        if fnmatch.fnmatch(changed_path, pat):
            return True
        # Exact file patterns also match when equal.
        if changed_path == pat:
            return True
    return False


docs_only = [
    "docs/workflow/x.md",
    "docs/specs/developments/a/b.md",
    "CHANGELOG.md",
]
covered = [
    "scripts/development-workflow/foo.sh",
    "scripts/development-workflow/tests/test-foo.sh",
    ".github/workflows/workflow-tests.yml",
]
other_workflow = [".github/workflows/shellcheck.yml"]
manifest_only = ["sync-manifest.yaml", ".ai-dev-workflow.yaml"]

docs_match = any(matches_any(p, expected_paths) for p in docs_only)
covered_match = all(matches_any(p, expected_paths) for p in covered)
other_wf_match = any(matches_any(p, expected_paths) for p in other_workflow)
manifest_match = any(matches_any(p, expected_paths) for p in manifest_only)

print("DOCS_ONLY_MATCH\t%s" % ("yes" if docs_match else "no"))
print("COVERED_MATCH\t%s" % ("yes" if covered_match else "no"))
print("OTHER_WF_MATCH\t%s" % ("yes" if other_wf_match else "no"))
print("MANIFEST_MATCH\t%s" % ("yes" if manifest_match else "no"))
PYPATH
)" || {
  echo "FAIL: path-filter parser exited non-zero"
  fail=$((fail + 1))
  echo "$path_filter_out"
  echo ""
  echo "Results: $pass passed, $fail failed"
  exit 1
}

kv() {
  printf '%s\n' "$path_filter_out" | awk -F'\t' -v k="$1" '$1 == k { print $2; exit }'
}

run_test "pr_branches_unchanged" "yes" "$(kv BRANCHES_OK)"
run_test "pr_paths_exact_two" "yes" "$(kv PATHS_OK)"
run_test "pr_paths_count" "2" "$(kv PATHS_COUNT)"
run_test "schedule_untouched_present" "yes" "$(kv SCHEDULE_OK)"
run_test "workflow_dispatch_untouched_present" "yes" "$(kv DISPATCH_OK)"
run_test "schedule_has_no_paths" "yes" "$(kv SCHEDULE_NO_PATHS)"
run_test "workflow_dispatch_has_no_paths" "yes" "$(kv DISPATCH_NO_PATHS)"
run_test "docs_only_matches_no_filter" "no" "$(kv DOCS_ONLY_MATCH)"
run_test "covered_scripts_match_filter" "yes" "$(kv COVERED_MATCH)"
run_test "other_workflow_matches_no_filter" "no" "$(kv OTHER_WF_MATCH)"
run_test "manifest_only_matches_no_filter" "no" "$(kv MANIFEST_MATCH)"

# ---------------------------------------------------------------------------
# sync-manifest note mentions the gate / opt-in variable and PR path filter
# ---------------------------------------------------------------------------
manifest_has_gate=no
if grep -qF "WORKFLOW_TESTS_NIGHTLY_ENABLED" "$MANIFEST_FILE" \
  && grep -qE 'schedule gate|job-level schedule gate' "$MANIFEST_FILE"; then
  manifest_has_gate=yes
fi
run_test "sync_manifest_note_mentions_gate" "yes" "$manifest_has_gate"

manifest_has_path_filter=no
if grep -qF "path filter" "$MANIFEST_FILE" \
  && grep -qF "scripts/development-workflow/**" "$MANIFEST_FILE"; then
  manifest_has_path_filter=yes
fi
run_test "sync_manifest_note_mentions_path_filter" "yes" "$manifest_has_path_filter"

migration_has_gate=no
if grep -qF 'version: "0.48.5"' "$MANIFEST_FILE" \
  && grep -qF "WORKFLOW_TESTS_NIGHTLY_ENABLED" "$MANIFEST_FILE" \
  && grep -qE 'path-filtered|path filter' "$MANIFEST_FILE"; then
  migration_has_gate=yes
fi
run_test "sync_manifest_migration_0_48_5" "yes" "$migration_has_gate"

# ---------------------------------------------------------------------------
# Behavioral: parse YAML and evaluate job ifs
# ---------------------------------------------------------------------------
if ! python3 -c 'import yaml' 2>/dev/null; then
  echo "FAIL: PyYAML required to evaluate workflow job if conditions"
  fail=$((fail + 1))
  echo ""
  echo "Results: $pass passed, $fail failed"
  exit 1
fi

eval_out="$(python3 - "$WORKFLOW_FILE" <<'PY'
import re
import sys

try:
    import yaml
except ImportError:
    print("ERROR: PyYAML missing", file=sys.stderr)
    sys.exit(3)

path = sys.argv[1]
with open(path, encoding="utf-8") as fh:
    doc = yaml.safe_load(fh)

if not isinstance(doc, dict):
    print("ERROR: workflow is not a mapping", file=sys.stderr)
    sys.exit(4)

triggers = doc.get("on", doc.get(True, {}))
if not isinstance(triggers, dict) or "schedule" not in triggers:
    print("ERROR: schedule trigger missing after parse", file=sys.stderr)
    sys.exit(4)

jobs = doc.get("jobs") or {}
required = ("select", "test", "result")
missing = [name for name in required if name not in jobs]
if missing:
    print("ERROR: missing jobs: %s" % ",".join(missing), file=sys.stderr)
    sys.exit(4)

TEMPLATE = "lhpaul/ai-dev-framework-template"
VAR = "WORKFLOW_TESTS_NIGHTLY_ENABLED"
ALLOW_NEEDLES = (
    "github.event_name != 'schedule'",
    "github.repository == 'lhpaul/ai-dev-framework-template'",
    "vars.WORKFLOW_TESTS_NIGHTLY_ENABLED == 'true'",
)


def normalize_if(expr):
    if expr is None:
        return ""
    text = str(expr)
    text = re.sub(r"\s+", " ", text).strip()
    return text


def actions_str_eq(left, right):
    """GitHub Actions string == / != is case-insensitive."""
    if isinstance(left, str) and isinstance(right, str):
        return left.casefold() == right.casefold()
    return left == right


job_ifs = {name: normalize_if(jobs[name].get("if")) for name in required}
all_job_ifs = {name: normalize_if((job or {}).get("if")) for name, job in jobs.items()}

# Every required job must carry the schedule allow-list.
for name, expr in job_ifs.items():
    for needle in ALLOW_NEEDLES:
        if needle not in expr:
            print("STRUCT\t%s\tmissing_needle\t%s" % (name, needle))
    if name == "result" and "always()" not in expr:
        print("STRUCT\tresult\tmissing_always")
    if name == "test" and "needs.select.outputs.count" not in expr:
        print("STRUCT\ttest\tmissing_count_gate")


def tokenize(expr):
    token_re = re.compile(
        r"\s*("
        r"always\(\)|"
        r"&&|\|\||"
        r"\(|\)|"
        r"!=|==|"
        r"'[^']*'|"
        r"[A-Za-z_][A-Za-z0-9_\.]*"
        r")"
    )
    pos = 0
    tokens = []
    while pos < len(expr):
        m = token_re.match(expr, pos)
        if not m:
            raise ValueError("unrecognized token near: %r" % expr[pos : pos + 40])
        tokens.append(m.group(1))
        pos = m.end()
    return tokens


class Parser:
    def __init__(self, tokens, ctx):
        self.tokens = tokens
        self.i = 0
        self.ctx = ctx

    def peek(self):
        return self.tokens[self.i] if self.i < len(self.tokens) else None

    def eat(self, expected=None):
        tok = self.peek()
        if tok is None:
            raise ValueError("unexpected end of expression")
        if expected is not None and tok != expected:
            raise ValueError("expected %r got %r" % (expected, tok))
        self.i += 1
        return tok

    def parse(self):
        value = self.parse_or()
        if self.peek() is not None:
            raise ValueError("trailing token %r" % self.peek())
        return value

    def parse_or(self):
        left = self.parse_and()
        while self.peek() == "||":
            self.eat("||")
            right = self.parse_and()
            left = left or right
        return left

    def parse_and(self):
        left = self.parse_cmp()
        while self.peek() == "&&":
            self.eat("&&")
            right = self.parse_cmp()
            left = left and right
        return left

    def parse_cmp(self):
        if self.peek() == "(":
            self.eat("(")
            value = self.parse_or()
            self.eat(")")
            return value
        left = self.parse_atom()
        op = self.peek()
        if op in ("==", "!="):
            self.eat(op)
            right = self.parse_atom()
            eq = actions_str_eq(left, right)
            if op == "==":
                return eq
            return not eq
        return bool(left)

    def parse_atom(self):
        tok = self.eat()
        if tok == "always()":
            return True
        if tok.startswith("'") and tok.endswith("'"):
            return tok[1:-1]
        if tok == "github.event_name":
            return self.ctx["event_name"]
        if tok == "github.repository":
            return self.ctx["repository"]
        if tok == "vars.WORKFLOW_TESTS_NIGHTLY_ENABLED":
            return self.ctx["var"]
        if tok == "needs.select.outputs.count":
            return self.ctx["select_count"]
        raise ValueError("unknown atom %r" % tok)


def eval_expr(expr, ctx):
    if not expr:
        return True
    return Parser(tokenize(expr), ctx).parse()


def var_opts_in(var_value):
    return actions_str_eq(var_value, "true")


# No job may run unconditionally on a consumer schedule without opt-in
# (blocks a schedule-only gate job that starts a runner in every repo).
consumer_schedule_ctx = {
    "event_name": "schedule",
    "repository": "acme/product-repo",
    "var": "",
    "select_count": "8",
}
for name, expr in all_job_ifs.items():
    if eval_expr(expr, consumer_schedule_ctx):
        print("STRUCT\t%s\tunconditional_on_consumer_schedule" % name)

cases = []
for event in ("schedule", "pull_request", "workflow_dispatch"):
    for repo in (TEMPLATE, "acme/product-repo"):
        for var_label, var_value in (
            ("unset", ""),
            ("true", "true"),
            ("True", "True"),
            ("TRUE", "TRUE"),
            ("false", "false"),
            ("yes", "yes"),
            ("1", "1"),
        ):
            cases.append((event, repo, var_label, var_value))

print("STRUCT\tok")
for event, repo, var_label, var_value in cases:
    ctx_base = {
        "event_name": event,
        "repository": repo,
        "var": var_value,
        "select_count": "8",
    }
    select_runs = eval_expr(job_ifs["select"], ctx_base)
    # Dependent jobs without always() do not start when select is skipped.
    test_ctx = dict(ctx_base)
    test_would = eval_expr(job_ifs["test"], test_ctx)
    test_runs = bool(select_runs and test_would)
    result_runs = eval_expr(job_ifs["result"], ctx_base)

    # Expected policy (Actions case-insensitive == for the opt-in var).
    schedule_allowed = repo == TEMPLATE or var_opts_in(var_value)
    if event != "schedule":
        expect_select = True
        expect_test = True  # count is non-zero in this matrix
        expect_result = True
    else:
        expect_select = schedule_allowed
        expect_test = schedule_allowed
        expect_result = schedule_allowed

    for job, actual, expect in (
        ("select", select_runs, expect_select),
        ("test", test_runs, expect_test),
        ("result", result_runs, expect_result),
    ):
        status = "ok" if bool(actual) == bool(expect) else "bad"
        print(
            "CASE\t%s\t%s\t%s\t%s\t%s\t%s\t%s"
            % (event, repo, var_label, job, expect, actual, status)
        )

    any_job = select_runs or test_runs or result_runs
    if event == "schedule" and repo != TEMPLATE and not var_opts_in(var_value):
        expect_any = False
    elif event == "schedule":
        expect_any = True
    else:
        expect_any = True
    status = "ok" if bool(any_job) == bool(expect_any) else "bad"
    print(
        "ANY\t%s\t%s\t%s\t%s\t%s\t%s"
        % (event, repo, var_label, expect_any, any_job, status)
    )
PY
)" || {
  echo "FAIL: python evaluator exited non-zero"
  fail=$((fail + 1))
  echo "$eval_out"
  echo ""
  echo "Results: $pass passed, $fail failed"
  exit 1
}

struct_ok="$(printf '%s\n' "$eval_out" | grep -c '^STRUCT	ok$' || true)"
run_test "yaml_jobs_carry_schedule_allow_list" "1" "$struct_ok"

# STRUCT ok line plus any failure lines; only ok should remain.
struct_lines="$(printf '%s\n' "$eval_out" | grep -c '^STRUCT	' || true)"
run_test "no_struct_failures" "1" "$struct_lines"

case_bad="$(printf '%s\n' "$eval_out" | grep -c '^CASE	.*	bad$' || true)"
run_test "if_matrix_all_cases" "0" "$case_bad"

any_bad="$(printf '%s\n' "$eval_out" | grep -c '^ANY	.*	bad$' || true)"
run_test "consumer_schedule_runs_no_jobs" "0" "$any_bad"

# Explicit spotlight cases for the acceptance / case-fold policy.
spotlight="$(printf '%s\n' "$eval_out" | python3 -c '
import sys
lines = sys.stdin.read().splitlines()
want = {
    ("schedule", "acme/product-repo", "unset"): False,
    ("schedule", "acme/product-repo", "false"): False,
    ("schedule", "acme/product-repo", "yes"): False,
    ("schedule", "acme/product-repo", "1"): False,
    ("schedule", "acme/product-repo", "true"): True,
    ("schedule", "acme/product-repo", "True"): True,
    ("schedule", "acme/product-repo", "TRUE"): True,
    ("schedule", "lhpaul/ai-dev-framework-template", "unset"): True,
    ("pull_request", "acme/product-repo", "unset"): True,
    ("workflow_dispatch", "acme/product-repo", "unset"): True,
}
seen = {}
for line in lines:
    if not line.startswith("ANY\t"):
        continue
    _, event, repo, var, expect, actual, status = line.split("\t")
    key = (event, repo, var)
    if key not in want:
        continue
    # ANY rows already encode expect vs actual; require both match and ok.
    seen[key] = status == "ok" and actual == str(want[key])
for key, expect in want.items():
    ok = seen.get(key) is True
    print("%s|%s|%s|%s|%s" % (key[0], key[1], key[2], expect, "yes" if ok else "no"))
')"

while IFS='|' read -r event repo var _expect ok; do
  run_test "spotlight_${event}_${repo##*/}_${var}" "yes" "$ok"
done <<< "$spotlight"

# pull_request / workflow_dispatch must not be schedule-gated away in consumers
pr_gated=no
if grep -q '^ANY	pull_request	acme/product-repo	unset	True	True	ok$' <<< "$eval_out"; then
  pr_gated=yes
fi
run_test "pull_request_not_gated_in_consumer" "yes" "$pr_gated"

dispatch_ok=no
if grep -q '^ANY	workflow_dispatch	acme/product-repo	unset	True	True	ok$' <<< "$eval_out"; then
  dispatch_ok=yes
fi
run_test "workflow_dispatch_not_gated_in_consumer" "yes" "$dispatch_ok"

echo ""
echo "Results: $pass passed, $fail failed"
if [ "$fail" -ne 0 ]; then
  echo "---- evaluator transcript (truncated) ----"
  head -80 <<< "$eval_out" || true
  exit 1
fi
exit 0
