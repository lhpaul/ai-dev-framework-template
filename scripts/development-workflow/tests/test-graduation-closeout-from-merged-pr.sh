#!/usr/bin/env bash
# test-graduation-closeout-from-merged-pr.sh - merge-time graduation closeout wrapper tests.
#
# covers: scripts/development-workflow/graduation-closeout-from-merged-pr.sh
# covers: scripts/development-workflow/graduation-closeout-lib.sh
#         (Linear tracker safety with graduation-closeout.sh)
#
# Usage: bash scripts/development-workflow/tests/test-graduation-closeout-from-merged-pr.sh

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"

TMP_ROOT="$(mktemp -d)"
MOCK_BIN="$TMP_ROOT/bin"
FIXTURE_REPO="$TMP_ROOT/repo"
MOCK_STATE_DIR="$TMP_ROOT/state"
CHILD_ARGV_LOG="$TMP_ROOT/child-argv.log"
MOCK_GH_LOG="$TMP_ROOT/gh-invocations.log"
GFM_FIXTURE_DIR="$REPO_ROOT/scripts/development-workflow/tests/fixtures/graduation-closeout-gfm"
export GFM_FIXTURE_DIR
MOCK_GRAPHQL_LOG="$TMP_ROOT/graphql.log"
PASS_COUNT=0
FAIL_COUNT=0

cleanup() {
  local status=$?
  rm -rf "$TMP_ROOT"
  case "$status" in
    141) exit 0 ;;
    *) exit "$status" ;;
  esac
}
trap cleanup EXIT

mkdir -p "$MOCK_BIN" "$FIXTURE_REPO/scripts/development-workflow" "$MOCK_STATE_DIR"

cp "$REPO_ROOT/scripts/development-workflow/graduation-closeout-from-merged-pr.sh" \
  "$FIXTURE_REPO/scripts/development-workflow/graduation-closeout-from-merged-pr.sh"
cp "$REPO_ROOT/scripts/development-workflow/closing-keyword-lib.sh" \
  "$FIXTURE_REPO/scripts/development-workflow/closing-keyword-lib.sh"
cp "$REPO_ROOT/scripts/development-workflow/graduation-closeout-lib.sh" \
  "$FIXTURE_REPO/scripts/development-workflow/graduation-closeout-lib.sh"
chmod +x "$FIXTURE_REPO/scripts/development-workflow/graduation-closeout-from-merged-pr.sh"

# Stub child reconciler — assert argv, do not re-test full closeout matrix.
cat > "$FIXTURE_REPO/scripts/development-workflow/graduation-closeout.sh" <<'CHILD'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" > "${CHILD_ARGV_LOG:?}"
if [ "${MOCK_CHILD_FAIL:-0}" = "1" ]; then
  echo "GRADUATION_CLOSEOUT_RESULT=failed"
  exit 1
fi
echo "GRADUATION_CLOSEOUT_RESULT=pass"
echo "EPIC_RESULT=closed"
exit 0
CHILD
chmod +x "$FIXTURE_REPO/scripts/development-workflow/graduation-closeout.sh"

# Real workflow-lib for shared + closeout-local provider resolution.
cp "$REPO_ROOT/scripts/development-workflow/workflow-lib.sh" \
  "$FIXTURE_REPO/scripts/development-workflow/workflow-lib.sh"
cat >> "$FIXTURE_REPO/scripts/development-workflow/workflow-lib.sh" <<'FIXTURE_OVERRIDES'

# --- fixture overrides ---
repo_slug() {
  printf 'lhpaul/ai-dev-framework-template\n'
}
FIXTURE_OVERRIDES

cat > "$MOCK_BIN/gh" <<'MOCK_GH'
#!/usr/bin/env bash
printf 'gh %s\n' "$*" >> "${MOCK_GH_LOG:?}"
case "$*" in
  "auth status")
    exit 0
    ;;

  api\ markdown*|markdown\ --input*)
    if [ "${MOCK_MARKDOWN_FAIL:-0}" = "1" ]; then
      printf 'mock markdown API failure\n' >&2
      exit 43
    fi
    GFM_DIR="${GFM_FIXTURE_DIR:?}"
    # Read JSON body before any heredoc steals stdin.
    MOCK_MD_PAYLOAD="$(cat)"
    printf '%s' "$MOCK_MD_PAYLOAD" | python3 -c '
import html, json, pathlib, re, sys
root = pathlib.Path(sys.argv[1])
raw = sys.stdin.read()
try:
    text = json.loads(raw).get("text", "")
except Exception:
    text = raw
for md_path in sorted(root.glob("*.md")):
    if md_path.read_text().rstrip("\n") == text.rstrip("\n"):
        sys.stdout.write(md_path.with_suffix(".html").read_text())
        sys.exit(0)
if "```" in text or "~~~" in text or re.search(r"(?m)^ {4,}\S", text) or "\n\n    " in text:
    sys.stderr.write("mock markdown: no GFM fixture for code-like text\n")
    sys.exit(45)
sys.stdout.write("<p dir=\"auto\">" + html.escape(text).replace("\n", "<br>\n") + "</p>")
sys.exit(0)
' "$GFM_DIR"
    ;;

  pr\ view\ *\ --json\ number,state,mergedAt,baseRefName,headRefName,title,body,merged)
    pr="$3"
    file="$MOCK_STATE_DIR/pr-${pr}.json"
    if [ ! -f "$file" ]; then
      printf 'missing fixture for pr #%s\n' "$pr" >&2
      exit 44
    fi
    cat "$file"
    ;;
  issue\ list\ --label\ integration-branch:*\ --state\ all\ --limit\ 1000\ --json\ number)
    label_mode="${MOCK_LABEL_PARENT_MODE:-ok}"
    case "$label_mode" in
      fail)
        printf 'mock label list failure\n' >&2
        exit 47
        ;;
      empty)
        printf '[]\n'
        ;;
      diverge)
        printf '[{"number":101},{"number":102}]\n'
        ;;
      *)
        printf '[{"number":101},{"number":102}]\n'
        ;;
    esac
    ;;
  api\ graphql*)
    # Parent lookup for label-discovered children.
    child=""
    idx=1
    while [ "$idx" -le "$#" ]; do
      if [ "${!idx}" = "-F" ]; then
        next=$((idx + 1))
        val="${!next:-}"
        case "$val" in
          number=*)
            child="${val#number=}"
            printf '%s\n' "$child" >> "${MOCK_GRAPHQL_LOG:?}"
            ;;
        esac
      fi
      idx=$((idx + 1))
    done
    parent="${MOCK_PARENT_DEFAULT:-900}"
    if [ "${MOCK_LABEL_PARENT_MODE:-ok}" = "diverge" ]; then
      if [ "$child" = "101" ]; then
        parent=900
      else
        parent=901
      fi
    fi
    if [ "${MOCK_LABEL_PARENT_MODE:-ok}" = "missing_parents" ]; then
      printf '{"data":{"repository":{"issue":{"parent":null}}}}\n'
      exit 0
    fi
    printf '{"data":{"repository":{"issue":{"parent":{"number":%s}}}}}\n' "$parent"
    ;;
  issue\ view\ *\ --json\ labels\ --jq\ *)
    issue="$3"
    file="$MOCK_STATE_DIR/issue-${issue}-labels.txt"
    if [ -f "$file" ]; then
      # Emulate jq join(",", labels) — no trailing newline.
      tr -d '\n' < "$file"
    else
      printf ''
    fi
    printf '\n'
    ;;
  *)
    printf 'unexpected gh invocation: gh %s\n' "$*" >&2
    exit 64
    ;;
esac
MOCK_GH
chmod +x "$MOCK_BIN/gh"

export PATH="$MOCK_BIN:$PATH"
export WORKFLOW_FIXTURE_REPO="$FIXTURE_REPO"
export MOCK_STATE_DIR CHILD_ARGV_LOG MOCK_GH_LOG MOCK_GRAPHQL_LOG

run_test() {
  local name="$1"
  local expected="$2"
  local actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $name - expected '${expected}', got '${actual}'"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

run_contains() {
  local name="$1"
  local expected="$2"
  local actual="$3"
  if grep -Fq -- "$expected" <<< "$actual"; then
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $name - expected output to contain '${expected}'"
    printf 'Actual output:\n%s\n' "$actual"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

run_not_contains() {
  local name="$1"
  local unexpected="$2"
  local actual="$3"
  if grep -Fq -- "$unexpected" <<< "$actual"; then
    echo "FAIL: $name - output unexpectedly contained '${unexpected}'"
    printf 'Actual output:\n%s\n' "$actual"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  else
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  fi
}

write_pr() {
  local number="$1"
  local head="$2"
  local base="$3"
  local merged="$4"
  local title="$5"
  local body="$6"
  # Title/body can exceed Linux MAX_ARG_STRLEN (~128KiB) for multibyte UTF-8.
  # Never pass them as python3 argv — use temp files.
  local title_file body_file
  title_file="$(mktemp "$TMP_ROOT/pr-title.XXXXXX")"
  body_file="$(mktemp "$TMP_ROOT/pr-body.XXXXXX")"
  printf '%s' "$title" > "$title_file"
  printf '%s' "$body" > "$body_file"
  python3 - "$MOCK_STATE_DIR/pr-${number}.json" "$number" "$head" "$base" "$merged" "$title_file" "$body_file" <<'PY'
import json, sys
path, number, head, base, merged, title_path, body_path = sys.argv[1:8]
title = open(title_path, encoding="utf-8").read()
body = open(body_path, encoding="utf-8").read()
payload = {
    "number": int(number),
    "state": "MERGED" if merged == "true" else "OPEN",
    "mergedAt": "2026-07-21T12:00:00Z" if merged == "true" else None,
    "merged": merged == "true",
    "baseRefName": base,
    "headRefName": head,
    "title": title,
    "body": body,
}
json.dump(payload, open(path, "w"))
PY
  rm -f "$title_file" "$body_file"
}

# write_pr_from_body_file <number> <head> <base> <merged> <title> <body_file>
# Prefer this when the body is large (avoids expanding a huge string into argv
# of intermediate helpers). Title stays short.
write_pr_from_body_file() {
  local number="$1"
  local head="$2"
  local base="$3"
  local merged="$4"
  local title="$5"
  local body_file="$6"
  local title_file
  title_file="$(mktemp "$TMP_ROOT/pr-title.XXXXXX")"
  printf '%s' "$title" > "$title_file"
  python3 - "$MOCK_STATE_DIR/pr-${number}.json" "$number" "$head" "$base" "$merged" "$title_file" "$body_file" <<'PY'
import json, sys
path, number, head, base, merged, title_path, body_path = sys.argv[1:8]
title = open(title_path, encoding="utf-8").read()
body = open(body_path, encoding="utf-8").read()
payload = {
    "number": int(number),
    "state": "MERGED" if merged == "true" else "OPEN",
    "mergedAt": "2026-07-21T12:00:00Z" if merged == "true" else None,
    "merged": merged == "true",
    "baseRefName": base,
    "headRefName": head,
    "title": title,
    "body": body,
}
json.dump(payload, open(path, "w"))
PY
  rm -f "$title_file"
}

write_tracker_config() {
  local provider="$1"
  cat > "$FIXTURE_REPO/.ai-dev-workflow.yaml" <<EOF
issue_tracker:
  provider: ${provider}
EOF
}

reset_fixture() {
  rm -f "$MOCK_STATE_DIR"/* "$CHILD_ARGV_LOG" "$MOCK_GH_LOG" "$MOCK_GRAPHQL_LOG"
  rm -f "$FIXTURE_REPO/.ai-dev-workflow.yaml"
  : > "$MOCK_GH_LOG"
  : > "$MOCK_GRAPHQL_LOG"
  unset MOCK_LABEL_PARENT_MODE MOCK_PARENT_DEFAULT MOCK_CHILD_FAIL
  export MOCK_LABEL_PARENT_MODE=empty
}

run_wrapper() {
  local output status
  set +e
  output="$(cd "$FIXTURE_REPO" && ./scripts/development-workflow/graduation-closeout-from-merged-pr.sh "$@" 2>&1)"
  status=$?
  set -e
  printf '%s\n%s\n' "$status" "$output"
}

last_body() { tail -n +2 <<< "$1"; }
last_status() { head -n 1 <<< "$1"; }

echo ""
echo "=== wrapper: valid slug + Epic ref delegates to reconciler ==="
reset_fixture
write_pr 77 "develop-my.feature_1" "develop" "true" "Graduate my.feature_1" "Epic #900\nCloses nothing else."
export MOCK_LABEL_PARENT_MODE=empty
result="$(run_wrapper --graduation-pr 77)"
body="$(last_body "$result")"
run_test "valid_slug_exit_zero" "0" "$(last_status "$result")"
run_contains "valid_slug_extracted" "SLUG=my.feature_1" "$body"
run_contains "epic_from_pr" "EPIC_ISSUE=900" "$body"
run_contains "epic_source_pr" "EPIC_SOURCE=pr_reference" "$body"
run_contains "child_argv_slug" "--slug my.feature_1" "$(cat "$CHILD_ARGV_LOG")"
run_contains "child_argv_epic" "--epic 900" "$(cat "$CHILD_ARGV_LOG")"
run_contains "child_argv_pr" "--graduation-pr 77" "$(cat "$CHILD_ARGV_LOG")"
run_contains "pass_result" "GRADUATION_CLOSEOUT_FROM_MERGED_PR_RESULT=pass" "$body"

echo ""
echo "=== wrapper: invalid slug chars fail closed ==="
reset_fixture
write_pr 78 "develop-my feature" "develop" "true" "Bad slug" "Epic #900"
result="$(run_wrapper --graduation-pr 78)"
body="$(last_body "$result")"
run_test "invalid_slug_exit_one" "1" "$(last_status "$result")"
run_contains "invalid_slug_reason" "invalid_graduation_slug" "$body"
run_test "invalid_slug_no_child" "missing" "$( [ -f "$CHILD_ARGV_LOG" ] && echo present || echo missing )"

echo ""
echo "=== wrapper: non-graduation head fails closed ==="
reset_fixture
write_pr 79 "feature/develop-123-x" "develop" "true" "Not graduation" "Epic #900"
result="$(run_wrapper --graduation-pr 79)"
body="$(last_body "$result")"
run_test "non_grad_exit_one" "1" "$(last_status "$result")"
run_contains "non_grad_reason" "head_not_graduation_branch" "$body"
run_test "non_grad_no_child" "missing" "$( [ -f "$CHILD_ARGV_LOG" ] && echo present || echo missing )"

echo ""
echo "=== wrapper: multiple closing refs fail closed without convergent parent ==="
reset_fixture
export MOCK_LABEL_PARENT_MODE=empty
write_pr 80 "develop-test-1281" "develop" "true" "Closes #10 and Closes #11" "Closes #10\nCloses #11"
result="$(run_wrapper --graduation-pr 80)"
body="$(last_body "$result")"
run_test "multi_ref_exit_one" "1" "$(last_status "$result")"
run_contains "multi_ref_reason" "ambiguous_epic_candidates" "$body"

echo ""
echo "=== wrapper: nested/related refs ignored; Epic # wins ==="
reset_fixture
export MOCK_LABEL_PARENT_MODE=empty
write_pr 81 "develop-test-1281" "develop" "true" "Graduate" $'see #12\nCloses issue #12\nEpic #900\nowner/repo#395'
result="$(run_wrapper --graduation-pr 81)"
body="$(last_body "$result")"
# Closing keyword Closes issue #12 and Epic #900 → two candidates → ambiguous without parents
# Unless Epic # and closing keyword both present - that's ambiguous. Use only Epic line:
write_pr 81 "develop-test-1281" "develop" "true" "Graduate" "$(cat "$GFM_FIXTURE_DIR/epic_with_fenced_999.md")"
result="$(run_wrapper --graduation-pr 81)"
body="$(last_body "$result")"
run_test "fence_ignored_exit_zero" "0" "$(last_status "$result")"
run_contains "fence_ignored_epic" "EPIC_ISSUE=900" "$body"
run_contains "fence_example_not_used" "EPIC_SOURCE=pr_reference" "$body"

echo ""
echo "=== wrapper: Parent # accepted ==="
reset_fixture
export MOCK_LABEL_PARENT_MODE=empty
write_pr 82 "develop-test-1281" "develop" "true" "Graduate" "Parent #901"
result="$(run_wrapper --graduation-pr 82)"
body="$(last_body "$result")"
run_test "parent_ref_exit_zero" "0" "$(last_status "$result")"
run_contains "parent_ref_epic" "EPIC_ISSUE=901" "$body"

echo ""
echo "=== wrapper: converging label parents discover epic ==="
reset_fixture
export MOCK_LABEL_PARENT_MODE=ok
export MOCK_PARENT_DEFAULT=900
write_pr 83 "develop-test-1281" "develop" "true" "Graduate" "No epic line here"
result="$(run_wrapper --graduation-pr 83)"
body="$(last_body "$result")"
run_test "label_parent_exit_zero" "0" "$(last_status "$result")"
run_contains "label_parent_epic" "EPIC_ISSUE=900" "$body"
run_contains "label_parent_source" "EPIC_SOURCE=label_parent_converged" "$body"

echo ""
echo "=== wrapper: diverging label parents fail closed ==="
reset_fixture
export MOCK_LABEL_PARENT_MODE=diverge
write_pr 84 "develop-test-1281" "develop" "true" "Graduate" "No epic"
result="$(run_wrapper --graduation-pr 84)"
body="$(last_body "$result")"
run_test "diverge_exit_one" "1" "$(last_status "$result")"
run_contains "diverge_reason" "epic_discovery_failed" "$body"

echo ""
echo "=== wrapper: defer-epic-close label passes flag to child ==="
reset_fixture
export MOCK_LABEL_PARENT_MODE=empty
write_pr 85 "develop-test-1281" "develop" "true" "Graduate" "Epic #900"
printf '%s' 'defer-epic-close' > "$MOCK_STATE_DIR/issue-900-labels.txt"
result="$(run_wrapper --graduation-pr 85)"
body="$(last_body "$result")"
run_test "defer_label_exit_zero" "0" "$(last_status "$result")"
run_contains "defer_source_label" "DEFER_SOURCE=epic_label" "$body"
run_contains "defer_child_flag" "--defer-epic-close" "$(cat "$CHILD_ARGV_LOG")"

echo ""
echo "=== wrapper: CLI defer override ==="
reset_fixture
export MOCK_LABEL_PARENT_MODE=empty
write_pr 86 "develop-test-1281" "develop" "true" "Graduate" "Epic #900"
result="$(run_wrapper --graduation-pr 86 --defer-epic-close)"
body="$(last_body "$result")"
run_test "defer_cli_exit_zero" "0" "$(last_status "$result")"
run_contains "defer_source_cli" "DEFER_SOURCE=cli" "$body"
run_contains "defer_cli_child_flag" "--defer-epic-close" "$(cat "$CHILD_ARGV_LOG")"

echo ""
echo "=== wrapper: exclude-issue forwarded ==="
reset_fixture
export MOCK_LABEL_PARENT_MODE=empty
write_pr 87 "develop-test-1281" "develop" "true" "Graduate" "Epic #900"
result="$(run_wrapper --graduation-pr 87 --exclude-issue 501 --exclude-issue 502)"
run_test "exclude_exit_zero" "0" "$(last_status "$result")"
run_contains "exclude_forwarded" "--exclude-issue 501 --exclude-issue 502" "$(cat "$CHILD_ARGV_LOG")"

echo ""
echo "=== wrapper: unmerged PR fails closed ==="
reset_fixture
write_pr 88 "develop-test-1281" "develop" "false" "Open grad" "Epic #900"
result="$(run_wrapper --graduation-pr 88)"
body="$(last_body "$result")"
run_test "unmerged_exit_one" "1" "$(last_status "$result")"
run_contains "unmerged_reason" "graduation_pr_not_merged" "$body"

echo ""
echo "=== wrapper: Linear epic LEA-326 from PR body; no GH #326 mutations (#1984) ==="
reset_fixture
write_tracker_config linear
export MOCK_LABEL_PARENT_MODE=ok
export MOCK_PARENT_DEFAULT=326
write_pr 90 "develop-test-1984" "develop" "true" "Graduate" "Epic LEA-326"
result="$(run_wrapper --graduation-pr 90)"
body="$(last_body "$result")"
run_test "linear_wrapper_exit_zero" "0" "$(last_status "$result")"
run_contains "linear_wrapper_epic" "EPIC_ISSUE=LEA-326" "$body"
run_contains "linear_wrapper_provider" "TRACKER_PROVIDER=linear" "$body"
run_contains "linear_child_epic" "--epic LEA-326" "$(cat "$CHILD_ARGV_LOG")"
run_test "linear_wrapper_no_parent_graphql" "" "$(cat "$MOCK_GRAPHQL_LOG")"
run_not_contains "linear_wrapper_no_issue_view_326" "issue view 326" "$(cat "$MOCK_GH_LOG")"

echo ""
echo "=== wrapper: Linear bare --epic 326 fails closed (#1984) ==="
reset_fixture
write_tracker_config linear
write_pr 91 "develop-test-1984" "develop" "true" "Graduate" "Epic LEA-326"
result="$(run_wrapper --graduation-pr 91 --epic 326)"
body="$(last_body "$result")"
run_test "linear_wrapper_bare_exit_64" "64" "$(last_status "$result")"
run_contains "linear_wrapper_bare_error" "native Linear ID" "$body"
run_test "linear_wrapper_bare_no_child" "missing" "$( [ -f "$CHILD_ARGV_LOG" ] && echo present || echo missing )"

echo ""
echo "=== wrapper: Linear --dry-run forwarded to child (#1984) ==="
reset_fixture
write_tracker_config linear
write_pr 92 "develop-test-1984" "develop" "true" "Graduate" "Epic LEA-326"
result="$(run_wrapper --graduation-pr 92 --dry-run)"
body="$(last_body "$result")"
run_test "linear_wrapper_dry_exit_zero" "0" "$(last_status "$result")"
run_contains "linear_wrapper_dry_flag" "DRY_RUN=1" "$body"
run_contains "linear_wrapper_dry_child" "--dry-run" "$(cat "$CHILD_ARGV_LOG")"

echo ""
echo "=== wrapper: Linear ignores tilde-fenced example Epic LEA-999 (#1984 Pass 2) ==="
reset_fixture
write_tracker_config linear
export MOCK_LABEL_PARENT_MODE=empty
write_pr 94 "develop-test-1984" "develop" "true" "Graduate" $'Example only:\n~~~\nEpic LEA-999\n~~~\nNo live epic.'
result="$(run_wrapper --graduation-pr 94)"
body="$(last_body "$result")"
run_test "linear_tilde_fence_exit_one" "1" "$(last_status "$result")"
run_contains "linear_tilde_fence_reason" "epic_discovery_failed" "$body"
run_test "linear_tilde_fence_no_child" "missing" "$( [ -f "$CHILD_ARGV_LOG" ] && echo present || echo missing )"
run_not_contains "linear_tilde_fence_no_lea999" "LEA-999" "$( [ -f "$CHILD_ARGV_LOG" ] && cat "$CHILD_ARGV_LOG" || true )"

echo ""
echo "=== wrapper: Linear ignores unclosed-fence example Epic LEA-999 (#1984 Pass 2) ==="
reset_fixture
write_tracker_config linear
export MOCK_LABEL_PARENT_MODE=empty
write_pr 95 "develop-test-1984" "develop" "true" "Graduate" $'Example only:\n```text\nEpic LEA-999\n'
result="$(run_wrapper --graduation-pr 95)"
body="$(last_body "$result")"
run_test "linear_unclosed_fence_exit_one" "1" "$(last_status "$result")"
run_contains "linear_unclosed_fence_reason" "epic_discovery_failed" "$body"
run_test "linear_unclosed_fence_no_child" "missing" "$( [ -f "$CHILD_ARGV_LOG" ] && echo present || echo missing )"
run_not_contains "linear_unclosed_fence_no_lea999" "LEA-999" "$( [ -f "$CHILD_ARGV_LOG" ] && cat "$CHILD_ARGV_LOG" || true )"

echo ""
echo "=== wrapper: Linear ignores indented-code Epic LEA-999 (#1984 Pass 1) ==="
reset_fixture
write_tracker_config linear
export MOCK_LABEL_PARENT_MODE=empty
write_pr 96 "develop-test-1984" "develop" "true" "Graduate" $'Example only:\n    Epic LEA-999\nNo live epic.'
result="$(run_wrapper --graduation-pr 96)"
body="$(last_body "$result")"
run_test "linear_indented_epic_exit_one" "1" "$(last_status "$result")"
run_contains "linear_indented_epic_reason" "epic_discovery_failed" "$body"
run_test "linear_indented_epic_no_child" "missing" "$( [ -f "$CHILD_ARGV_LOG" ] && echo present || echo missing )"
run_not_contains "linear_indented_epic_no_lea999" "LEA-999" "$( [ -f "$CHILD_ARGV_LOG" ] && cat "$CHILD_ARGV_LOG" || true )"

echo ""
echo "=== wrapper: commented header + linear fails closed before child (#1984) ==="
reset_fixture
cat > "$FIXTURE_REPO/.ai-dev-workflow.yaml" <<'EOF'
issue_tracker: # native tracker
  provider: linear
EOF
write_pr 97 "develop-test-1984" "develop" "true" "Graduate" "Epic LEA-326"
result="$(run_wrapper --graduation-pr 97)"
body="$(last_body "$result")"
run_test "commented_linear_wrapper_exit_64" "64" "$(last_status "$result")"
run_contains "commented_linear_wrapper_remediation" "tracker bridge cannot read it" "$body"
run_test "commented_linear_wrapper_no_child" "missing" "$( [ -f "$CHILD_ARGV_LOG" ] && echo present || echo missing )"

echo ""
echo "=== wrapper: github_projects discovery unchanged with explicit config (#1984) ==="
reset_fixture
write_tracker_config github_projects
export MOCK_LABEL_PARENT_MODE=empty
write_pr 93 "develop-test-1984" "develop" "true" "Graduate" "Epic #900"
result="$(run_wrapper --graduation-pr 93)"
body="$(last_body "$result")"
run_test "gh_proj_wrapper_exit_zero" "0" "$(last_status "$result")"
run_contains "gh_proj_wrapper_epic" "EPIC_ISSUE=900" "$body"
run_contains "gh_proj_wrapper_provider" "TRACKER_PROVIDER=github_projects" "$body"
run_contains "gh_proj_child_epic" "--epic 900" "$(cat "$CHILD_ARGV_LOG")"

# ---------------------------------------------------------------------------
# #2016 — GitHub providers use GFM fixtures for epic/closing text discovery
# ---------------------------------------------------------------------------

# shellcheck disable=SC1091
. "$REPO_ROOT/scripts/development-workflow/closing-keyword-lib.sh"
# shellcheck disable=SC1091
. "$REPO_ROOT/scripts/development-workflow/graduation-closeout-lib.sh"

write_pr_from_gfm_fixture() {
  local number="$1"
  local fixture="$2"
  local title="Graduate wave"
  local body
  body="$(cat "$GFM_FIXTURE_DIR/${fixture}.md"; printf x)"
  body="${body%x}"
  case "$fixture" in
    title_closes)
      title="$(printf '%s' "$body" | head -n1)"
      body=""
      ;;
  esac
  write_pr "$number" "develop-test-2016" "develop" "true" "$title" "$body"
}

assert_wrapper_gfm_epic() {
  local provider="$1"
  local fixture="$2"
  local expected_epic="$3"
  local label="$4"
  reset_fixture
  write_tracker_config "$provider"
  export MOCK_LABEL_PARENT_MODE=empty
  write_pr_from_gfm_fixture 110 "$fixture"
  local result body
  result="$(run_wrapper --graduation-pr 110)"
  body="$(last_body "$result")"
  run_test "${label}_exit_zero" "0" "$(last_status "$result")"
  run_contains "${label}_epic" "EPIC_ISSUE=${expected_epic}" "$body"
  run_contains "${label}_provider" "TRACKER_PROVIDER=${provider}" "$body"
  run_contains "${label}_child_epic" "--epic ${expected_epic}" "$(cat "$CHILD_ARGV_LOG")"
  if [ "$expected_epic" != "326" ]; then
    run_not_contains "${label}_no_epic_326" "--epic 326" "$(cat "$CHILD_ARGV_LOG")"
  fi
}

assert_wrapper_gfm_epic_fail() {
  local provider="$1"
  local fixture="$2"
  local label="$3"
  reset_fixture
  write_tracker_config "$provider"
  export MOCK_LABEL_PARENT_MODE=empty
  write_pr_from_gfm_fixture 111 "$fixture"
  local result body
  result="$(run_wrapper --graduation-pr 111)"
  body="$(last_body "$result")"
  run_test "${label}_exit_one" "1" "$(last_status "$result")"
  run_contains "${label}_reason" "epic_discovery_failed" "$body"
  run_test "${label}_no_child" "missing" "$( [ -f "$CHILD_ARGV_LOG" ] && echo present || echo missing )"
}


echo ""
echo "=== wrapper: long Unicode body after prose keyword (#2016 Pass 1) ==="
# Write via stdout→file (never argv). ~180KiB UTF-8 exceeds Linux MAX_ARG_STRLEN.
long_unicode_file="$TMP_ROOT/long-unicode-prefilter.txt"
python3 -c 'import sys; sys.stdout.write("Epic #900\nCloses #123" + ("あ" * 60000))' >"$long_unicode_file"
set +e
graduation_closeout_raw_has_closing_keyword_candidate <"$long_unicode_file"
prefilter_status=$?
set -e
run_test "wrap_long_unicode_prefilter_exit_zero" "0" "$prefilter_status"
run_test "wrap_long_unicode_prefilter_file_over_128kib" "1" "$(python3 -c 'import pathlib,sys; print(1 if pathlib.Path(sys.argv[1]).stat().st_size > 131072 else 0)' "$long_unicode_file")"

echo ""
echo "=== wrapper: render_gfm preserves caller \$- (#2016 Pass 1) ==="
assert_wrap_render_gfm_preserves_shell_opts() {
  local mode="$1"  # errexit_on | errexit_off
  local expect_ok="$2"  # 1=success path, 0=API failure path
  local before after status
  if [ "$mode" = "errexit_on" ]; then
    set -e
  else
    set +e
  fi
  before=$-
  if [ "$expect_ok" = "1" ]; then
    unset MOCK_MARKDOWN_FAIL
  else
    export MOCK_MARKDOWN_FAIL=1
  fi
  # Capture status via if only — do not toggle set ±e around the helper.
  if printf '%s' 'Closes #326' | graduation_closeout_render_gfm lhpaul/ai-dev-framework-template >/dev/null; then
    status=0
  else
    status=$?
  fi
  after=$-
  unset MOCK_MARKDOWN_FAIL
  if [ "$expect_ok" = "1" ]; then
    run_test "wrap_render_opts_${mode}_success_status" "0" "$status"
  else
    run_test "wrap_render_opts_${mode}_fail_status" "1" "$status"
  fi
  run_test "wrap_render_opts_${mode}_expect${expect_ok}_dollar_unchanged" "$before" "$after"
  set -e
}
assert_wrap_render_gfm_preserves_shell_opts errexit_on 1
assert_wrap_render_gfm_preserves_shell_opts errexit_on 0
assert_wrap_render_gfm_preserves_shell_opts errexit_off 1
assert_wrap_render_gfm_preserves_shell_opts errexit_off 0

echo ""
echo "=== wrapper: long Unicode prose still discovers epic (#2016 Pass 1) ==="
long_epic_body_file="$TMP_ROOT/long-unicode-epic-body.txt"
python3 -c 'import sys; sys.stdout.write("Epic #900\n" + ("あ" * 60000))' >"$long_epic_body_file"
run_test "wrap_long_epic_body_file_over_128kib" "1" "$(python3 -c 'import pathlib,sys; print(1 if pathlib.Path(sys.argv[1]).stat().st_size > 131072 else 0)' "$long_epic_body_file")"
for provider in github_projects github_issues; do
  reset_fixture
  write_tracker_config "$provider"
  export MOCK_LABEL_PARENT_MODE=empty
  write_pr_from_body_file 119 "develop-test-2016" "develop" "true" "Graduate wave" "$long_epic_body_file"
  result="$(run_wrapper --graduation-pr 119)"
  body="$(last_body "$result")"
  run_test "${provider}_wrap_long_unicode_exit_zero" "0" "$(last_status "$result")"
  run_contains "${provider}_wrap_long_unicode_epic" "EPIC_ISSUE=900" "$body"
  run_contains "${provider}_wrap_long_unicode_child" "--epic 900" "$(cat "$CHILD_ARGV_LOG")"
done


echo ""
echo "=== wrapper: production PR text never passed as external argv (#2016) ==="
# Static audit: flag python3/jq/gh lines that place large PR-text shell vars on argv
# (not via stdin pipe / --input / --rawfile). Short ids like $issue / $context are OK.
argv_hits="$(python3 - "$REPO_ROOT" <<'PYAUDIT'
import pathlib, re, sys
root = pathlib.Path(sys.argv[1])
files = [
    root / "scripts/development-workflow/graduation-closeout.sh",
    root / "scripts/development-workflow/graduation-closeout-from-merged-pr.sh",
    root / "scripts/development-workflow/graduation-closeout-lib.sh",
]
var = r"\$\{?(?:body|title|text|raw|payload|title_raw|body_raw|title_enc|body_enc|visible|html)\}?"
hits = []
for path in files:
    for i, line in enumerate(path.read_text().splitlines(), 1):
        s = line.lstrip()
        if not s or s.startswith("#"):
            continue
        if not re.search(r"\b(python3|jq|gh)\b", line):
            continue
        if not re.search(var, line):
            continue
        left = line
        for cmd in ("python3", "jq", "gh"):
            if cmd in line:
                left = line.split(cmd)[0]
                break
        if "|" in left or "--input" in line or "--rawfile" in line:
            continue
        hits.append(f"{path.name}:{i}:{line.strip()}")
print("\n".join(hits))
PYAUDIT
)"
if [ -n "$argv_hits" ]; then
  echo "FAIL: production argv audit found PR-text-on-argv call sites:"
  printf '%s\n' "$argv_hits"
  FAIL_COUNT=$((FAIL_COUNT + 1))
else
  echo "PASS: wrap_production_pr_text_argv_audit_clean"
  PASS_COUNT=$((PASS_COUNT + 1))
fi

echo ""
echo "=== wrapper: >130KiB multibyte body via production stdin path (#2016) ==="
huge_body_file="$TMP_ROOT/huge-multibyte-body.txt"
python3 -c 'import sys; sys.stdout.write("Closes #326\n" + ("あ" * 50000))' >"$huge_body_file"
run_test "wrap_huge_body_over_130kib" "1" "$(python3 -c 'import pathlib,sys; print(1 if pathlib.Path(sys.argv[1]).stat().st_size > 131072 else 0)' "$huge_body_file")"
argv_guard="$TMP_ROOT/argv-guard"
cat > "$argv_guard" <<'GUARD'
#!/usr/bin/env bash
python3 - "$@" <<'PY'
import sys
limit = 131072
for i, a in enumerate(sys.argv[1:], 1):
    n = len(a.encode("utf-8"))
    if n > limit:
        sys.stderr.write(f"argv-guard: arg {i} is {n} bytes (> {limit})\n")
        sys.exit(99)
sys.exit(0)
PY
GUARD
chmod +x "$argv_guard"
# Invoke via Python so the shell never builds a >128KiB argv word (Linux E2BIG).
guard_status="$(python3 - "$argv_guard" "$huge_body_file" <<'PY'
import errno, subprocess, sys
guard, path = sys.argv[1], sys.argv[2]
body = open(path, encoding="utf-8").read()
try:
    r = subprocess.run([guard, body], capture_output=True)
    print(r.returncode)
except OSError as e:
    print(99 if getattr(e, "errno", None) == errno.E2BIG else 1)
PY
)"
run_test "wrap_argv_guard_rejects_huge_argv" "99" "$guard_status"
for provider in github_projects github_issues; do
  reset_fixture
  write_tracker_config "$provider"
  export MOCK_LABEL_PARENT_MODE=empty
  write_pr_from_body_file 120 "develop-test-2016" "develop" "true" "Graduate wave" "$huge_body_file"
  result="$(run_wrapper --graduation-pr 120)"
  body="$(last_body "$result")"
  run_test "${provider}_wrap_huge_stdin_exit_zero" "0" "$(last_status "$result")"
  run_contains "${provider}_wrap_huge_stdin_epic" "EPIC_ISSUE=326" "$body"
done
set +e
graduation_closeout_raw_has_closing_keyword_candidate <"$huge_body_file"
huge_pre_st=$?
set -e
run_test "wrap_huge_stdin_prefilter_ok" "0" "$huge_pre_st"
huge_refs="$(graduation_closeout_github_live_refs_from_markdown lhpaul/ai-dev-framework-template <"$huge_body_file" | head -n1 || true)"
run_test "wrap_huge_stdin_live_refs_326" "326" "$huge_refs"

echo ""
echo "=== wrapper: planted violation — raw fenced text would keep #326 (#2016) ==="
planted_md="$(cat "$GFM_FIXTURE_DIR/fenced_tick.md")"
planted_html="$(cat "$GFM_FIXTURE_DIR/fenced_tick.html")"
# Planted violation: raw-text keyword scan (no GFM) still sees #326 in the fence;
# rendered visible text + shared live_refs does not.
raw_refs="$(printf '%s' "$planted_md" | grep -ioE "$CLOSING_KEYWORD_REGEX" | grep -oE '[0-9]+$' || true)"
vis_refs="$(printf '%s' "$planted_html" | graduation_closeout_html_visible_text | closing_keyword_live_refs || true)"
run_test "wrap_planted_raw_finds_326" "326" "$(printf '%s' "$raw_refs" | head -n1)"
run_test "wrap_planted_rendered_strips_326" "" "$(printf '%s' "$vis_refs")"

echo ""
echo "=== wrapper: markdown API failure fail-closes text refs (#2016) ==="
for provider in github_projects github_issues; do
  reset_fixture
  write_tracker_config "$provider"
  export MOCK_LABEL_PARENT_MODE=empty
  export MOCK_MARKDOWN_FAIL=1
  write_pr_from_gfm_fixture 118 plain_prose
  result="$(run_wrapper --graduation-pr 118)"
  body="$(last_body "$result")"
  unset MOCK_MARKDOWN_FAIL
  run_test "${provider}_wrap_md_fail_exit_one" "1" "$(last_status "$result")"
  run_contains "${provider}_wrap_md_fail_unavailable" "CLOSEOUT_TEXT_REFS_UNAVAILABLE pr=118" "$body"
  run_contains "${provider}_wrap_md_fail_reason" "epic_discovery_failed" "$body"
  run_test "${provider}_wrap_md_fail_no_child" "missing" "$( [ -f "$CHILD_ARGV_LOG" ] && echo present || echo missing )"
done

for provider in github_projects github_issues; do
  echo ""
  echo "=== wrapper: ${provider} GFM fixture matrix (#2016) ==="
  assert_wrapper_gfm_epic "$provider" epic_plus_fenced_closes 900 "${provider}_wrap_epic_fence"
  assert_wrapper_gfm_epic "$provider" epic_plus_tilde_fence 900 "${provider}_wrap_epic_tilde"
  assert_wrapper_gfm_epic "$provider" epic_plus_unclosed_fence 900 "${provider}_wrap_epic_unclosed"
  assert_wrapper_gfm_epic "$provider" epic_plus_indented 900 "${provider}_wrap_epic_indent"
  assert_wrapper_gfm_epic "$provider" epic_plus_mixed_indent 900 "${provider}_wrap_epic_mixed"
  assert_wrapper_gfm_epic "$provider" body_start_indent_then_epic 900 "${provider}_wrap_body_start"
  assert_wrapper_gfm_epic "$provider" body_start_tab_then_epic 900 "${provider}_wrap_body_tab"
  assert_wrapper_gfm_epic "$provider" epic_plus_cross_repo 900 "${provider}_wrap_cross_keeps_epic"
  assert_wrapper_gfm_epic "$provider" nested_list_prose 123 "${provider}_wrap_nested_list"
  assert_wrapper_gfm_epic "$provider" list_continuation_prose 124 "${provider}_wrap_list_cont"
  assert_wrapper_gfm_epic "$provider" para_continuation 125 "${provider}_wrap_para_cont"
  assert_wrapper_gfm_epic "$provider" plain_prose 326 "${provider}_wrap_plain"
  assert_wrapper_gfm_epic "$provider" title_closes 327 "${provider}_wrap_title"
  assert_wrapper_gfm_epic_fail "$provider" fenced_tick "${provider}_wrap_fenced_only"
  assert_wrapper_gfm_epic_fail "$provider" indented_code "${provider}_wrap_indent_only"
  assert_wrapper_gfm_epic_fail "$provider" cross_repo "${provider}_wrap_foreign"
  assert_wrapper_gfm_epic_fail "$provider" example_only_fenced "${provider}_wrap_ex_fence"
  assert_wrapper_gfm_epic_fail "$provider" example_only_indented "${provider}_wrap_ex_indent"
  assert_wrapper_gfm_epic "$provider" closes_code_repo_then_prose 123 "${provider}_wrap_code_repo_prose"
  assert_wrapper_gfm_epic_fail "$provider" fixes_code_between_keyword_ref "${provider}_wrap_fixes_code_gap"
  assert_wrapper_gfm_epic "$provider" see_code_then_closes 328 "${provider}_wrap_see_code_closes"
done


echo ""
echo "Graduation closeout-from-merged-pr tests: $PASS_COUNT passed, $FAIL_COUNT failed."
if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
