#!/usr/bin/env bash
# test-graduation-closeout.sh - graduation closeout helper tests.
#
# covers: scripts/development-workflow/graduation-closeout.sh
# covers: scripts/development-workflow/graduation-closeout-lib.sh
#         (Linear tracker safety with graduation-closeout-from-merged-pr.sh)
#
# Usage: bash scripts/development-workflow/tests/test-graduation-closeout.sh

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"

TMP_ROOT="$(mktemp -d)"
MOCK_BIN="$TMP_ROOT/bin"
FIXTURE_REPO="$TMP_ROOT/repo"
MOCK_STATE_DIR="$TMP_ROOT/state"
MOCK_STATUS_DIR="$TMP_ROOT/status"
MOCK_CLOSE_LOG="$TMP_ROOT/close.log"
MOCK_LABEL_LOG="$TMP_ROOT/label.log"
MOCK_GRAPHQL_LOG="$TMP_ROOT/graphql.log"
MOCK_GH_LOG="$TMP_ROOT/gh-invocations.log"
GFM_FIXTURE_DIR="$REPO_ROOT/scripts/development-workflow/tests/fixtures/graduation-closeout-gfm"
export GFM_FIXTURE_DIR
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

mkdir -p "$MOCK_BIN" "$FIXTURE_REPO/scripts/development-workflow" "$MOCK_STATE_DIR" "$MOCK_STATUS_DIR"
cp "$REPO_ROOT/scripts/development-workflow/graduation-closeout.sh" "$FIXTURE_REPO/scripts/development-workflow/graduation-closeout.sh"
cp "$REPO_ROOT/scripts/development-workflow/closing-keyword-lib.sh" "$FIXTURE_REPO/scripts/development-workflow/closing-keyword-lib.sh"
cp "$REPO_ROOT/scripts/development-workflow/graduation-closeout-lib.sh" \
  "$FIXTURE_REPO/scripts/development-workflow/graduation-closeout-lib.sh"
# Real workflow-lib (Linear bridge / emit_linear_deferred_action / shared parser).
# Append fixture overrides only — do not reimplement Linear update_tracker.
cp "$REPO_ROOT/scripts/development-workflow/workflow-lib.sh" \
  "$FIXTURE_REPO/scripts/development-workflow/workflow-lib.sh"
cat >> "$FIXTURE_REPO/scripts/development-workflow/workflow-lib.sh" <<'FIXTURE_OVERRIDES'

# --- fixture overrides (after real definitions) ---
repo_slug() {
  printf 'lhpaul/ai-dev-framework-template\n'
}

_fixture_real_get_tracker_status_for_issue_body="$(declare -f get_tracker_status_for_issue)"
_fixture_real_get_tracker_status_for_issue_body="${_fixture_real_get_tracker_status_for_issue_body/get_tracker_status_for_issue/_fixture_real_get_tracker_status_for_issue}"
eval "$_fixture_real_get_tracker_status_for_issue_body"
unset _fixture_real_get_tracker_status_for_issue_body

_fixture_real_update_tracker_status_best_effort_body="$(declare -f update_tracker_status_best_effort)"
_fixture_real_update_tracker_status_best_effort_body="${_fixture_real_update_tracker_status_best_effort_body/update_tracker_status_best_effort/_fixture_real_update_tracker_status_best_effort}"
eval "$_fixture_real_update_tracker_status_best_effort_body"
unset _fixture_real_update_tracker_status_best_effort_body

get_tracker_status_for_issue() {
  local provider
  # Bridge readability uses the shared parser — same as production.
  provider="$(workflow_normalize_issue_tracker_provider "$(workflow_issue_tracker_provider_raw)")"
  if [ "$provider" = "linear" ]; then
    _fixture_real_get_tracker_status_for_issue "$@"
    return $?
  fi
  local issue="$1"
  if [ -f "${MOCK_STATUS_DIR:?}/$issue" ]; then
    cat "$MOCK_STATUS_DIR/$issue"
  fi
}

update_tracker_status_best_effort() {
  local provider
  provider="$(workflow_normalize_issue_tracker_provider "$(workflow_issue_tracker_provider_raw)")"
  if [ "$provider" = "linear" ]; then
    # Simulate merge-session / bridge skip: exit 0 with empty stdout.
    if [ "${MOCK_LINEAR_UPDATE_EMPTY:-0}" = "1" ]; then
      return 0
    fi
    _fixture_real_update_tracker_status_best_effort "$@"
    return $?
  fi
  local issue="$1"
  local status="$2"
  if [ "${MOCK_STATUS_FAIL_ISSUE:-}" = "$issue" ]; then
    printf 'Warning: mocked status update failure for #%s\n' "$issue" >&2
    return 0
  fi
  printf '%s\n' "$status" > "${MOCK_STATUS_DIR:?}/$issue"
}
FIXTURE_OVERRIDES
chmod +x "$FIXTURE_REPO/scripts/development-workflow/graduation-closeout.sh"

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

  api\ graphql*)
    # Record the issue number variable so Linear tests can assert #326 was
    # never queried via subIssues.
    idx=1
    while [ "$idx" -le "$#" ]; do
      if [ "${!idx}" = "-F" ]; then
        next=$((idx + 1))
        val="${!next:-}"
        case "$val" in
          number=*) printf '%s\n' "${val#number=}" >> "${MOCK_GRAPHQL_LOG:?}" ;;
        esac
      fi
      idx=$((idx + 1))
    done
    case "${MOCK_NATIVE_MODE:-children}" in
      fail)
        printf 'mock native failure\n' >&2
        exit 42
        ;;
      empty)
        cat <<'JSON'
{"data":{"repository":{"issue":{"subIssues":{"nodes":[],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}}
JSON
        ;;
      *)
        cat <<'JSON'
{"data":{"repository":{"issue":{"subIssues":{"nodes":[{"number":101,"title":"Open child","state":"OPEN","labels":{"nodes":[]}},{"number":102,"title":"Closed nonterminal","state":"CLOSED","labels":{"nodes":[]}},{"number":103,"title":"Closed terminal","state":"CLOSED","labels":{"nodes":[]}},{"number":104,"title":"Optional child","state":"OPEN","labels":{"nodes":[{"name":"optional"}]}}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}}
JSON
        ;;
    esac
    ;;
  issue\ list\ --label\ integration-branch:test\ --state\ all\ --limit\ 1000\ --json\ number,title,state,labels\ --jq\ .[]\ \|\ .number)
    if [ "${MOCK_LABEL_MODE:-ok}" = "fail" ]; then
      printf 'mock label discovery failure\n' >&2
      exit 47
    fi
    if [ -n "${MOCK_LABEL_ISSUES:-}" ]; then
      printf '%s\n' "$MOCK_LABEL_ISSUES"
    fi
    ;;
  "pr view 77 --json number,state,mergedAt,baseRefName,headRefName")
    case "${MOCK_GRADUATION_PR_MODE:-merged}" in
      open)
        cat <<'JSON'
{"number":77,"state":"OPEN","mergedAt":null,"baseRefName":"develop","headRefName":"develop-test"}
JSON
        ;;
      wrong_head)
        cat <<'JSON'
{"number":77,"state":"MERGED","mergedAt":"2026-07-15T12:00:00Z","baseRefName":"develop","headRefName":"feature/not-graduation"}
JSON
        ;;
      wrong_base)
        cat <<'JSON'
{"number":77,"state":"MERGED","mergedAt":"2026-07-15T12:00:00Z","baseRefName":"main","headRefName":"develop-test"}
JSON
        ;;
      nested_base)
        cat <<'JSON'
{"number":77,"state":"MERGED","mergedAt":"2026-07-15T12:00:00Z","baseRefName":"develop-sales-module","headRefName":"develop-test"}
JSON
        ;;
      *)
        cat <<'JSON'
{"number":77,"state":"MERGED","mergedAt":"2026-07-15T12:00:00Z","baseRefName":"develop","headRefName":"develop-test"}
JSON
        ;;
    esac
    ;;
  "pr list --state merged --base develop-test --limit 1000 --json number,title,body")
    # GitHub Projects / GitHub Issues keyword-scan path (GFM fixtures).
    case "${MOCK_PR_MODE:-single_ref}" in
      long_unicode_prose)
        python3 <<'PYLU'
import json
body = "Closes #326" + ("あ" * 60000)
print(json.dumps([{"number": 11, "title": "Graduate wave", "body": body}]))
PYLU
        ;;
      huge_body_file)
        python3 - "${MOCK_HUGE_BODY_FILE:?}" <<'PYHUGE'
import json, pathlib, sys
body = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
print(json.dumps([{"number": 11, "title": "Graduate wave", "body": body}]))
PYHUGE
        ;;
      gfm_fixture)
        python3 - "$GFM_FIXTURE_DIR" "${MOCK_GFM_FIXTURE:?}" <<'PYGFM'
import json, pathlib, sys
fix, name = pathlib.Path(sys.argv[1]), sys.argv[2]
md = (fix / f"{name}.md").read_text()
title = "Graduate wave"
body = md
if name == "title_closes":
    title = md.strip().splitlines()[0] if md.strip() else "Graduate wave"
    body = ""
print(json.dumps([{"number": 11, "title": title, "body": body}]))
PYGFM
        ;;
      fail)
        printf 'mock pr list failure\n' >&2
        exit 46
        ;;
      none)
        printf '[]\n'
        ;;
      parser)
        cat <<'JSON'
[{"number":21,"title":"Closes #301 and fixes #302","body":"(Resolves issue #303.)\n- closed #304\nDisclose #398\nhotfix #399\nnot closing #397\nowner/repo#396\nCloses owner/repo#395\nfixes #302"}]
JSON
        ;;
      fenced_example)
        # Body-only example that would falsely authorize #326 if scanned raw.
        cat <<'JSON'
[{"number":11,"title":"Graduate wave","body":"See example:\n```\nCloses #326\n```\nNo live closing keywords."}]
JSON
        ;;
      tilde_fenced_example)
        cat <<'JSON'
[{"number":11,"title":"Graduate wave","body":"See example:\n~~~\nCloses #326\n~~~\nNo live closing keywords."}]
JSON
        ;;
      unclosed_fenced_example)
        cat <<'JSON'
[{"number":11,"title":"Graduate wave","body":"See example:\n```text\nCloses #326\n"}]
JSON
        ;;
      indented_code_example)
        # Blank before indent → CommonMark indented code (not list/paragraph).
        cat <<'JSON'
[{"number":11,"title":"Graduate wave","body":"See example:\n\n    Closes #326\nNo live closing keywords."}]
JSON
        ;;
      mixed_indent_example)
        # Blank then space+tab → indented code; must not authorize #326.
        cat <<'JSON'
[{"number":11,"title":"Graduate wave","body":"See example:\n\n \tCloses #326\nNo live closing keywords."}]
JSON
        ;;
      nested_list_closes_123)
        cat <<'JSON'
[{"number":11,"title":"Deliver item","body":"- Delivered work:\n    - Closes #123"}]
JSON
        ;;
      list_continuation_closes_124)
        cat <<'JSON'
[{"number":11,"title":"Deliver item","body":"- Delivered work:\n    Closes #124"}]
JSON
        ;;
      paragraph_continuation_closes_125)
        cat <<'JSON'
[{"number":11,"title":"Deliver item","body":"Some prose about the change.\n    Closes #125"}]
JSON
        ;;
      blank_then_indented_326)
        cat <<'JSON'
[{"number":11,"title":"Graduate wave","body":"See example:\n\n    Closes #326\nNo live closing keywords."}]
JSON
        ;;
      body_starts_four_space_326)
        # Body begins with indented code; non-empty title must not make it live.
        cat <<'JSON'
[{"number":11,"title":"Graduate wave","body":"    Closes #326\nNo live closing keywords."}]
JSON
        ;;
      body_starts_tab_326)
        cat <<'JSON'
[{"number":11,"title":"Graduate wave","body":"\tCloses #326\nNo live closing keywords."}]
JSON
        ;;
      body_starts_space_tab_326)
        cat <<'JSON'
[{"number":11,"title":"Graduate wave","body":" \tCloses #326\nNo live closing keywords."}]
JSON
        ;;
      title_closes_327_body_indent_326)
        cat <<'JSON'
[{"number":11,"title":"Closes #327","body":"    Closes #326\nNo live body keyword."}]
JSON
        ;;
      thematic_break_then_indent_326)
        # Thematic break must not open list context; indented #326 stays code.
        cat <<'JSON'
[{"number":11,"title":"Graduate wave","body":"- - -\n\n    Closes #326\nNo live closing keywords."}]
JSON
        ;;
      thematic_hr_dashes_then_indent_326)
        cat <<'JSON'
[{"number":11,"title":"Graduate wave","body":"---\n\n    Closes #326\nNo live closing keywords."}]
JSON
        ;;
      thematic_stars_then_indent_326)
        cat <<'JSON'
[{"number":11,"title":"Graduate wave","body":"* * *\n\n    Closes #326\nNo live closing keywords."}]
JSON
        ;;
      thematic_hr_stars_then_indent_326)
        cat <<'JSON'
[{"number":11,"title":"Graduate wave","body":"***\n\n    Closes #326\nNo live closing keywords."}]
JSON
        ;;
      thematic_underscores_then_indent_326)
        cat <<'JSON'
[{"number":11,"title":"Graduate wave","body":"___\n\n    Closes #326\nNo live closing keywords."}]
JSON
        ;;
      list_item_then_indent_123)
        cat <<'JSON'
[{"number":11,"title":"Deliver item","body":"- item\n    Closes #123"}]
JSON
        ;;
      list_two_space_cont_closes_123)
        cat <<'JSON'
[{"number":11,"title":"Deliver item","body":"- Delivered work:\n  Additional details.\n\n    Closes #123"}]
JSON
        ;;
      list_multi_cont_closes_124)
        cat <<'JSON'
[{"number":11,"title":"Deliver item","body":"- a\n  b\n\n  c\n\n    Closes #124"}]
JSON
        ;;
      list_then_para_then_indent_326)
        cat <<'JSON'
[{"number":11,"title":"Graduate wave","body":"- item\n\nParagraph outside list.\n\n    Closes #326\nNo live closing keywords."}]
JSON
        ;;
      list_item_six_space_code_326)
        cat <<'JSON'
[{"number":11,"title":"Graduate wave","body":"- Example:\n\n      Closes #326\nNo live closing keywords."}]
JSON
        ;;
      ordered_list_seven_space_327)
        cat <<'JSON'
[{"number":11,"title":"Graduate wave","body":"1. Item\n\n       Closes #327\nNo live closing keywords."}]
JSON
        ;;
      atx_heading_then_indent_326)
        cat <<'JSON'
[{"number":11,"title":"Graduate wave","body":"## Example\n    Closes #326\nNo live closing keywords."}]
JSON
        ;;
      setext_dashes_then_indent_326)
        cat <<'JSON'
[{"number":11,"title":"Graduate wave","body":"Paragraph\n---\n    Closes #326\nNo live closing keywords."}]
JSON
        ;;
      atx_heading_blank_prose_328)
        cat <<'JSON'
[{"number":11,"title":"Deliver item","body":"## Example\n\nCloses #328"}]
JSON
        ;;
      list_tilde_fence_326)
        cat <<'JSON'
[{"number":11,"title":"Graduate wave","body":"- Example:\n\n    ~~~text\n    Closes #326\n    ~~~\nNo live closing keywords."}]
JSON
        ;;
      list_tilde_fence_unclosed_326)
        cat <<'JSON'
[{"number":11,"title":"Graduate wave","body":"- Example:\n\n    ~~~text\n    Closes #326\nNo live closing keywords."}]
JSON
        ;;
      list_backtick_fence_326)
        cat <<'JSON'
[{"number":11,"title":"Graduate wave","body":"- Example:\n\n    ```text\n    Closes #326\n    ```\nNo live closing keywords."}]
JSON
        ;;
      list_backtick_fence_unclosed_326)
        cat <<'JSON'
[{"number":11,"title":"Graduate wave","body":"- Example:\n\n    ```text\n    Closes #326\nNo live closing keywords."}]
JSON
        ;;
      list_fence_then_prose_123)
        cat <<'JSON'
[{"number":11,"title":"Deliver item","body":"- Example:\n\n    ~~~text\n    Closes #326\n    ~~~\n    Closes #123"}]
JSON
        ;;
      marker_tilde_fence_326)
        cat <<'JSON'
[{"number":11,"title":"Graduate wave","body":"- ~~~text\n  Closes #326\n  ~~~\nNo live closing keywords."}]
JSON
        ;;
      marker_tilde_fence_unclosed_326)
        cat <<'JSON'
[{"number":11,"title":"Graduate wave","body":"- ~~~text\n  Closes #326\nNo live closing keywords."}]
JSON
        ;;
      marker_backtick_fence_326)
        cat <<'JSON'
[{"number":11,"title":"Graduate wave","body":"- ```text\n  Closes #326\n  ```\nNo live closing keywords."}]
JSON
        ;;
      marker_backtick_fence_unclosed_326)
        cat <<'JSON'
[{"number":11,"title":"Graduate wave","body":"- ```text\n  Closes #326\nNo live closing keywords."}]
JSON
        ;;
      ordered_marker_tilde_fence_326)
        cat <<'JSON'
[{"number":11,"title":"Graduate wave","body":"1. ~~~\n   Closes #326\n   ~~~\nNo live closing keywords."}]
JSON
        ;;
      marker_fence_then_prose_123)
        cat <<'JSON'
[{"number":11,"title":"Deliver item","body":"- ~~~text\n  Closes #326\n  ~~~\n  Closes #123"}]
JSON
        ;;
      toplevel_fence_list_no_leak_326)
        cat <<'JSON'
[{"number":11,"title":"Graduate wave","body":"~~~text\n- example\n~~~\n\n    Closes #326\nNo live closing keywords."}]
JSON
        ;;
      toplevel_tick_fence_list_no_leak_327)
        cat <<'JSON'
[{"number":11,"title":"Graduate wave","body":"```text\n- example\n```\n\n    Closes #327\nNo live closing keywords."}]
JSON
        ;;
      heading_inside_fence_326)
        cat <<'JSON'
[{"number":11,"title":"Graduate wave","body":"~~~\n## Example\n~~~\n\n    Closes #326\nNo live closing keywords."}]
JSON
        ;;
      tab_marker_tilde_fence_326)
        cat <<'JSON'
[{"number":11,"title":"Graduate wave","body":"-\t~~~text\n\tCloses #326\n\t~~~\nNo live closing keywords."}]
JSON
        ;;
      tab_marker_tilde_unclosed_326)
        cat <<'JSON'
[{"number":11,"title":"Graduate wave","body":"-\t~~~text\n\tCloses #326\nNo live closing keywords."}]
JSON
        ;;
      tab_ordered_tick_fence_326)
        cat <<'JSON'
[{"number":11,"title":"Graduate wave","body":"1.\t```text\n\tCloses #326\n\t```\nNo live closing keywords."}]
JSON
        ;;
      tab_docstart_listlike_331)
        cat <<'JSON'
[{"number":11,"title":"Graduate wave","body":"\t- item\n\t\tCloses #331\nNo live closing keywords."}]
JSON
        ;;
      blank_then_four_space_listlike_326)
        cat <<'JSON'
[{"number":11,"title":"Graduate wave","body":"Intro\n\n    - Closes #326\nNo live closing keywords."}]
JSON
        ;;
      docstart_four_space_listlike_326)
        cat <<'JSON'
[{"number":11,"title":"Graduate wave","body":"    - Closes #326\nNo live closing keywords."}]
JSON
        ;;
      nested_list_under_delivered_123)
        cat <<'JSON'
[{"number":11,"title":"Deliver item","body":"- Delivered:\n    - Closes #123"}]
JSON
        ;;
      list_blank_then_deep_listlike_332)
        cat <<'JSON'
[{"number":11,"title":"Graduate wave","body":"- a\n\n        - Closes #332\nNo live closing keywords."}]
JSON
        ;;
      para_cont_listlike_333)
        cat <<'JSON'
[{"number":11,"title":"Deliver item","body":"Para\n    - Closes #333"}]
JSON
        ;;
      nested_list_dedent_outer_code_326)
        cat <<'JSON'
[{"number":11,"title":"Graduate wave","body":"- Outer item\n  - Nested item\n\n  Example command:\n\n      Closes #326\nNo live closing keywords."}]
JSON
        ;;
      heading_inside_list_closes_123)
        cat <<'JSON'
[{"number":11,"title":"Deliver item","body":"- Delivered work\n  ## Details\n\n    Closes #123"}]
JSON
        ;;
      three_level_dedent_l1_code_326)
        cat <<'JSON'
[{"number":11,"title":"Graduate wave","body":"- L1\n  - L2\n    - L3\n\n  Example:\n\n      Closes #326\nNo live closing keywords."}]
JSON
        ;;
      dedent_to_doc_then_indent_326)
        cat <<'JSON'
[{"number":11,"title":"Graduate wave","body":"- L1\n  - L2\n\nParagraph\n\n    Closes #326\nNo live closing keywords."}]
JSON
        ;;
      heading_inside_nested_closes_123)
        cat <<'JSON'
[{"number":11,"title":"Deliver item","body":"- Outer\n  - Nested\n    ## Details\n\n      Closes #123"}]
JSON
        ;;
      lazy_cont_then_indent_closes_326)
        cat <<'JSON'
[{"number":11,"title":"Deliver item","body":"- Delivered work:\nContinuation paragraph\n\n    Closes #326"}]
JSON
        ;;
      lazy_cont_then_exit_indent_334)
        cat <<'JSON'
[{"number":11,"title":"Graduate wave","body":"- Delivered work:\nContinuation paragraph\n\nParagraph outside\n\n    Closes #334\nNo live closing keywords."}]
JSON
        ;;
      lazy_cont_inside_nested_closes_123)
        cat <<'JSON'
[{"number":11,"title":"Deliver item","body":"- Outer\n  - Nested item\n  Nested continuation\n\n      Closes #123"}]
JSON
        ;;
      marker_five_space_code_123)
        cat <<'JSON'
[{"number":11,"title":"Graduate wave","body":"-     Closes #123\nNo live closing keywords."}]
JSON
        ;;
      marker_five_space_code_cont_123)
        cat <<'JSON'
[{"number":11,"title":"Graduate wave","body":"-     Example\n      Closes #123\nNo live closing keywords."}]
JSON
        ;;
      marker_heading_then_code_326)
        cat <<'JSON'
[{"number":11,"title":"Graduate wave","body":"- ## Example\n      Closes #326\nNo live closing keywords."}]
JSON
        ;;
      marker_two_space_closes_340)
        cat <<'JSON'
[{"number":11,"title":"Deliver item","body":"-  Closes #340"}]
JSON
        ;;
      marker_one_space_closes_341)
        cat <<'JSON'
[{"number":11,"title":"Deliver item","body":"- Closes #341"}]
JSON
        ;;
      nested_same_line_marker_fence_326)
        cat <<'JSON'
[{"number":11,"title":"Graduate wave","body":"- - ~~~text\n    Closes #326\n    ~~~\nNo live closing keywords."}]
JSON
        ;;
      nested_same_line_marker_closes_342)
        cat <<'JSON'
[{"number":11,"title":"Deliver item","body":"- - Closes #342"}]
JSON
        ;;
      ordered_nested_marker_tick_fence_343)
        cat <<'JSON'
[{"number":11,"title":"Graduate wave","body":"1. - ```\n     Closes #343\n     ```\nNo live closing keywords."}]
JSON
        ;;
      nested_same_line_blank_prose_344)
        cat <<'JSON'
[{"number":11,"title":"Deliver item","body":"- - item\n\n    prose Closes #344"}]
JSON
        ;;
      nested_same_line_tab_fence_456)
        cat <<'JSON'
[{"number":11,"title":"Graduate wave","body":"- -\t~~~text\n\tCloses #456\n\t~~~\nNo live closing keywords."}]
JSON
        ;;
      ordered_2_no_interrupt_456)
        cat <<'JSON'
[{"number":11,"title":"Graduate wave","body":"Intro\n2. Example\n\n    Closes #456\nNo live closing keywords."}]
JSON
        ;;
      ordered_1_interrupt_closes_457)
        cat <<'JSON'
[{"number":11,"title":"Deliver item","body":"Intro\n1. Example\n\n    Closes #457"}]
JSON
        ;;
      ordered_siblings_closes_458)
        cat <<'JSON'
[{"number":11,"title":"Deliver item","body":"1. a\n2. b\n\n     Closes #458"}]
JSON
        ;;
      empty_item_no_interrupt_459)
        cat <<'JSON'
[{"number":11,"title":"Graduate wave","body":"Intro\n-\n\n    Closes #459\nNo live closing keywords."}]
JSON
        ;;
      foreign_repo_text)
        cat <<'JSON'
[{"number":11,"title":"Graduate wave","body":"Closes other/repo#326\nNo local closing keywords."}]
JSON
        ;;
      plain_closes_326)
        cat <<'JSON'
[{"number":11,"title":"Deliver item","body":"Closes #326"}]
JSON
        ;;
      *)
        cat <<'JSON'
[{"number":11,"title":"Deliver extra item","body":"Closes #105"}]
JSON
        ;;
    esac
    ;;
  "pr list --state merged --base develop-test --limit 1000 --json number,title,body,closingIssuesReferences")
    # Linear merged-PR discovery (structured same-repo refs only; text keywords skipped).
    case "${MOCK_PR_MODE:-single_ref}" in
      fail)
        printf 'mock pr list failure\n' >&2
        exit 46
        ;;
      none)
        printf '[]\n'
        ;;
      fenced_example)
        cat <<'JSON'
[{"number":11,"title":"Graduate wave","body":"See example:\n```\nCloses #326\n```\nNo live closing keywords.","closingIssuesReferences":[]}]
JSON
        ;;
      tilde_fenced_example)
        cat <<'JSON'
[{"number":11,"title":"Graduate wave","body":"See example:\n~~~\nCloses #326\n~~~\nNo live closing keywords.","closingIssuesReferences":[]}]
JSON
        ;;
      unclosed_fenced_example)
        cat <<'JSON'
[{"number":11,"title":"Graduate wave","body":"See example:\n```text\nCloses #326\n","closingIssuesReferences":[]}]
JSON
        ;;
      indented_code_example)
        cat <<'JSON'
[{"number":11,"title":"Graduate wave","body":"See example:\n    Closes #326\nNo live structured refs.","closingIssuesReferences":[]}]
JSON
        ;;
      foreign_repo)
        cat <<'JSON'
[{"number":11,"title":"Deliver extra item","body":"No live closing keywords in this PR body.","closingIssuesReferences":[{"number":326,"repository":{"nameWithOwner":"other/repo"},"url":"https://github.com/other/repo/issues/326"}]}]
JSON
        ;;
      empty_structured_plain_keyword)
        cat <<'JSON'
[{"number":11,"title":"Deliver extra item","body":"Closes #326","closingIssuesReferences":[]}]
JSON
        ;;
      *)
        cat <<'JSON'
[{"number":11,"title":"Deliver extra item","body":"Closes #105","closingIssuesReferences":[{"number":105,"repository":{"nameWithOwner":"lhpaul/ai-dev-framework-template"},"url":"https://github.com/lhpaul/ai-dev-framework-template/issues/105"}]}]
JSON
        ;;
    esac
    ;;
  issue\ view\ *\ --json\ labels\ --jq\ *)
    issue="$3"
    file="$MOCK_STATE_DIR/$issue.json"
    if [ ! -f "$file" ]; then
      printf 'missing fixture for issue #%s\n' "$issue" >&2
      exit 44
    fi
    python3 - "$file" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
print(",".join(label.get("name") or "" for label in (data.get("labels") or [])))
PY
    ;;
  issue\ view\ *\ --json\ number,title,state,labels)
    issue="$3"
    file="$MOCK_STATE_DIR/$issue.json"
    if [ ! -f "$file" ]; then
      printf 'missing fixture for issue #%s\n' "$issue" >&2
      exit 44
    fi
    cat "$file"
    ;;
  issue\ edit\ *\ --add-label\ defer-epic-close)
    issue="$3"
    file="$MOCK_STATE_DIR/$issue.json"
    if [ ! -f "$file" ]; then
      printf 'missing fixture for issue #%s\n' "$issue" >&2
      exit 44
    fi
    if [ "${MOCK_LABEL_ADD_FAIL:-0}" = "1" ]; then
      printf 'mock label add failure\n' >&2
      exit 48
    fi
    python3 - "$file" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path))
labels = data.setdefault("labels", [])
if not any((label.get("name") or "") == "defer-epic-close" for label in labels):
    labels.append({"name": "defer-epic-close"})
json.dump(data, open(path, "w"))
PY
    printf 'add\t%s\tdefer-epic-close\n' "$issue" >> "$MOCK_LABEL_LOG"
    ;;
  label\ create\ defer-epic-close*)
    if [ "${MOCK_LABEL_CREATE_FAIL:-0}" = "1" ]; then
      printf 'mock label create failure\n' >&2
      exit 49
    fi
    printf 'create\tdefer-epic-close\n' >> "$MOCK_LABEL_LOG"
    ;;
  issue\ close\ *\ --comment\ *)
    issue="$3"
    if [ "${MOCK_CLOSE_FAIL_ISSUE:-}" = "$issue" ]; then
      printf 'mock close failure for #%s\n' "$issue" >&2
      exit 45
    fi
    python3 - "$MOCK_STATE_DIR/$issue.json" <<'PY'
import json
import sys
path = sys.argv[1]
data = json.load(open(path))
data["state"] = "CLOSED"
json.dump(data, open(path, "w"))
PY
    printf '%s\t%s\n' "$issue" "$*" >> "$MOCK_CLOSE_LOG"
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
export MOCK_STATE_DIR MOCK_STATUS_DIR MOCK_CLOSE_LOG MOCK_LABEL_LOG MOCK_GRAPHQL_LOG MOCK_GH_LOG

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

write_issue() {
  local number="$1"
  local title="$2"
  local state="$3"
  local labels_csv="${4:-}"
  python3 - "$MOCK_STATE_DIR/$number.json" "$number" "$title" "$state" "$labels_csv" <<'PY'
import json
import sys
path, number, title, state, labels_csv = sys.argv[1:6]
labels = [{"name": label} for label in labels_csv.split(",") if label]
json.dump({"number": int(number), "title": title, "state": state, "labels": labels}, open(path, "w"))
PY
}

set_status() {
  printf '%s\n' "$2" > "$MOCK_STATUS_DIR/$1"
}

write_tracker_config() {
  local provider="$1"
  cat > "$FIXTURE_REPO/.ai-dev-workflow.yaml" <<EOF
issue_tracker:
  provider: ${provider}
EOF
}

reset_fixture() {
  rm -f "$MOCK_STATE_DIR"/*.json "$MOCK_STATUS_DIR"/* "$MOCK_CLOSE_LOG" "$MOCK_LABEL_LOG" "$MOCK_GRAPHQL_LOG" "$MOCK_GH_LOG"
  rm -f "$FIXTURE_REPO/.ai-dev-workflow.yaml"
  : > "$MOCK_CLOSE_LOG"
  : > "$MOCK_LABEL_LOG"
  : > "$MOCK_GRAPHQL_LOG"
  : > "$MOCK_GH_LOG"
  unset MOCK_NATIVE_MODE MOCK_LABEL_MODE MOCK_LABEL_ISSUES MOCK_PR_MODE MOCK_GRADUATION_PR_MODE MOCK_CLOSE_FAIL_ISSUE MOCK_STATUS_FAIL_ISSUE MOCK_LABEL_ADD_FAIL MOCK_LABEL_CREATE_FAIL MOCK_LINEAR_UPDATE_EMPTY GITHUB_PROJECT_STATUS_GRADUATED GITHUB_PROJECT_STATUS_MERGED GRADUATION_BASE
}

run_closeout() {
  local output status
  local epic="${CLOSEOUT_EPIC:-900}"
  set +e
  output="$(cd "$FIXTURE_REPO" && ./scripts/development-workflow/graduation-closeout.sh --slug test --graduation-pr 77 --epic "$epic" "$@" 2>&1)"
  status=$?
  set -e
  printf '%s\n%s\n' "$status" "$output"
}

last_output_body() {
  tail -n +2 <<< "$1"
}

last_output_status() {
  head -n 1 <<< "$1"
}

echo ""
echo "=== graduation closeout: discovery failures fail closed ==="
reset_fixture
export MOCK_NATIVE_MODE=fail
export MOCK_PR_MODE=none
write_issue 900 "Parent epic" OPEN
set_status 900 "In Development"
empty_discovery_result="$(run_closeout)"
empty_discovery_body="$(last_output_body "$empty_discovery_result")"
run_test "empty_discovery_exit_one" "1" "$(last_output_status "$empty_discovery_result")"
run_contains "empty_discovery_failed_result" "GRADUATION_CLOSEOUT_RESULT=failed" "$empty_discovery_body"
run_contains "empty_discovery_reason" "no_delivered_subitems_discovered" "$empty_discovery_body"
run_contains "empty_discovery_epic_held" "EPIC_RESULT=held" "$empty_discovery_body"
run_test "empty_discovery_no_epic_close" "OPEN" "$(python3 -c 'import json; print(json.load(open("'"$MOCK_STATE_DIR"'/900.json"))["state"])')"

reset_fixture
export MOCK_PR_MODE=fail
write_issue 101 "Open child" OPEN
write_issue 102 "Closed nonterminal" CLOSED
write_issue 103 "Closed terminal" CLOSED
write_issue 104 "Optional child" OPEN optional
write_issue 900 "Parent epic" OPEN
set_status 101 "In Development"
set_status 102 "Development in Review"
set_status 103 "Merged"
set_status 104 "In Development"
set_status 900 "In Development"
pr_discovery_result="$(run_closeout)"
pr_discovery_body="$(last_output_body "$pr_discovery_result")"
run_test "pr_discovery_exit_one" "1" "$(last_output_status "$pr_discovery_result")"
run_contains "pr_discovery_reason" "merged_pr_discovery_failed" "$pr_discovery_body"
run_contains "pr_discovery_epic_held" "EPIC_RESULT=held" "$pr_discovery_body"
run_test "pr_discovery_child_still_processed" "CLOSED" "$(python3 -c 'import json; print(json.load(open("'"$MOCK_STATE_DIR"'/101.json"))["state"])')"
run_test "pr_discovery_no_epic_close" "OPEN" "$(python3 -c 'import json; print(json.load(open("'"$MOCK_STATE_DIR"'/900.json"))["state"])')"

reset_fixture
export MOCK_LABEL_MODE=fail
export MOCK_PR_MODE=none
write_issue 101 "Open child" OPEN
write_issue 102 "Closed nonterminal" CLOSED
write_issue 103 "Closed terminal" CLOSED
write_issue 104 "Optional child" OPEN optional
write_issue 900 "Parent epic" OPEN
set_status 101 "In Development"
set_status 102 "Development in Review"
set_status 103 "Merged"
set_status 104 "In Development"
set_status 900 "In Development"
label_discovery_result="$(run_closeout)"
label_discovery_body="$(last_output_body "$label_discovery_result")"
run_test "label_discovery_exit_one" "1" "$(last_output_status "$label_discovery_result")"
run_contains "label_discovery_reason" "label_fallback_failed" "$label_discovery_body"
run_contains "label_discovery_epic_held" "EPIC_RESULT=held" "$label_discovery_body"
run_test "label_discovery_child_still_processed" "CLOSED" "$(python3 -c 'import json; print(json.load(open("'"$MOCK_STATE_DIR"'/101.json"))["state"])')"
run_test "label_discovery_no_epic_close" "OPEN" "$(python3 -c 'import json; print(json.load(open("'"$MOCK_STATE_DIR"'/900.json"))["state"])')"

echo ""
echo "=== graduation closeout: graduation PR validation ==="
reset_fixture
export MOCK_GRADUATION_PR_MODE=open
export MOCK_NATIVE_MODE=empty
export MOCK_LABEL_ISSUES="701"
export MOCK_PR_MODE=none
write_issue 701 "Should not close" OPEN
write_issue 900 "Parent epic" OPEN
set_status 701 "In Development"
set_status 900 "In Development"
validation_result="$(run_closeout)"
validation_body="$(last_output_body "$validation_result")"
run_test "validation_exit_one" "1" "$(last_output_status "$validation_result")"
run_contains "validation_reports_unmerged_pr" "has not merged yet" "$validation_body"
run_test "validation_does_not_close_child" "OPEN" "$(python3 -c 'import json; print(json.load(open("'"$MOCK_STATE_DIR"'/701.json"))["state"])')"
run_test "validation_no_close_calls" "" "$(cat "$MOCK_CLOSE_LOG")"

echo ""
echo "=== graduation closeout: --base graduation base override (issue #1513) ==="

# Regression: default base (no --base flag) must still require the graduation
# PR to target 'develop', and must still be rejected with a clear error when
# it does not — this must not regress when --base support is added.
reset_fixture
export MOCK_GRADUATION_PR_MODE=wrong_base
export MOCK_NATIVE_MODE=empty
export MOCK_LABEL_ISSUES="801"
export MOCK_PR_MODE=none
write_issue 801 "Default base child" OPEN
write_issue 900 "Parent epic" OPEN
set_status 801 "In Development"
set_status 900 "In Development"
default_base_reject_result="$(run_closeout)"
default_base_reject_body="$(last_output_body "$default_base_reject_result")"
run_test "default_base_reject_exit_one" "1" "$(last_output_status "$default_base_reject_result")"
run_contains "default_base_reject_error" "expected 'develop'" "$default_base_reject_body"
run_test "default_base_reject_no_close" "OPEN" "$(python3 -c 'import json; print(json.load(open("'"$MOCK_STATE_DIR"'/801.json"))["state"])')"

# Non-default base: a nested graduation PR (develop-test -> develop-sales-module)
# whose --base matches the PR's actual base passes validation and completes
# closeout normally.
reset_fixture
export MOCK_GRADUATION_PR_MODE=nested_base
export MOCK_NATIVE_MODE=empty
export MOCK_LABEL_ISSUES="802"
export MOCK_PR_MODE=none
write_issue 802 "Nested base child" OPEN
write_issue 900 "Parent epic" OPEN
set_status 802 "In Development"
set_status 900 "In Development"
nested_base_result="$(run_closeout --base develop-sales-module)"
nested_base_body="$(last_output_body "$nested_base_result")"
run_test "nested_base_exit_zero" "0" "$(last_output_status "$nested_base_result")"
run_contains "nested_base_result_pass" "GRADUATION_CLOSEOUT_RESULT=pass" "$nested_base_body"
run_contains "nested_base_reported" "GRADUATION_BASE=develop-sales-module" "$nested_base_body"
run_test "nested_base_child_closed" "CLOSED" "$(python3 -c 'import json; print(json.load(open("'"$MOCK_STATE_DIR"'/802.json"))["state"])')"
run_contains "nested_base_comment_target" "to \`develop-sales-module\`" "$(cat "$MOCK_CLOSE_LOG")"

# Non-default base with a mismatched actual PR base is still rejected with a
# clear error (the "real check" required by issue #1513 AC-2) — the expected
# branch named in the error is the custom --base, not a hardcoded 'develop'.
reset_fixture
export MOCK_GRADUATION_PR_MODE=merged
export MOCK_NATIVE_MODE=empty
export MOCK_LABEL_ISSUES="803"
export MOCK_PR_MODE=none
write_issue 803 "Mismatched base child" OPEN
write_issue 900 "Parent epic" OPEN
set_status 803 "In Development"
set_status 900 "In Development"
nested_base_mismatch_result="$(run_closeout --base develop-sales-module)"
nested_base_mismatch_body="$(last_output_body "$nested_base_mismatch_result")"
run_test "nested_base_mismatch_exit_one" "1" "$(last_output_status "$nested_base_mismatch_result")"
run_contains "nested_base_mismatch_error" "expected 'develop-sales-module'" "$nested_base_mismatch_body"
run_test "nested_base_mismatch_no_close" "OPEN" "$(python3 -c 'import json; print(json.load(open("'"$MOCK_STATE_DIR"'/803.json"))["state"])')"

# An arbitrary feature/fix branch as --base is rejected up front (usage-level
# validation) before any gh call — the "real check" is not bypassable by
# simply passing a matching but non-integration-branch value.
reset_fixture
invalid_base_result="$(run_closeout --base feature/not-an-integration-branch)"
invalid_base_body="$(last_output_body "$invalid_base_result")"
run_test "invalid_base_exit_64" "64" "$(last_output_status "$invalid_base_result")"
run_contains "invalid_base_error" "must be 'develop' or a 'develop-*' integration branch" "$invalid_base_body"

echo ""
echo "=== graduation closeout: native sub-issues and PR refs ==="
reset_fixture
write_issue 101 "Open child" OPEN
write_issue 102 "Closed nonterminal" CLOSED
write_issue 103 "Closed terminal" CLOSED
write_issue 104 "Optional child" OPEN optional
write_issue 105 "PR referenced child" OPEN
write_issue 900 "Parent epic" OPEN
set_status 101 "In Development"
set_status 102 "Development in Review"
set_status 103 "Merged"
set_status 104 "In Development"
set_status 105 "Plan Ready"
set_status 900 "In Development"
native_result="$(run_closeout)"
native_body="$(last_output_body "$native_result")"
run_test "native_exit_zero" "0" "$(last_output_status "$native_result")"
run_contains "native_result_pass" "GRADUATION_CLOSEOUT_RESULT=pass" "$native_body"
run_contains "native_closed_count" "CLOSED_COUNT=3" "$native_body"
run_contains "native_already_count" "ALREADY_TERMINAL_COUNT=1" "$native_body"
run_contains "native_skipped_count" "SKIPPED_OPTIONAL_COUNT=1" "$native_body"
run_contains "native_failed_count" "FAILED_COUNT=0" "$native_body"
run_contains "native_epic_closed" "EPIC_RESULT=closed" "$native_body"
run_test "open_child_closed" "CLOSED" "$(python3 -c 'import json; print(json.load(open("'"$MOCK_STATE_DIR"'/101.json"))["state"])')"
run_test "closed_nonterminal_status_updated" "Merged" "$(cat "$MOCK_STATUS_DIR/102")"
run_test "optional_stays_open" "OPEN" "$(python3 -c 'import json; print(json.load(open("'"$MOCK_STATE_DIR"'/104.json"))["state"])')"
run_contains "pr_ref_source_reported" "#105" "$native_body"
run_contains "close_log_has_epic" "900" "$(cat "$MOCK_CLOSE_LOG")"

echo ""
echo "=== graduation closeout: label fallback ==="
reset_fixture
export MOCK_NATIVE_MODE=empty
export MOCK_LABEL_ISSUES=$'201\n202'
export MOCK_PR_MODE=none
write_issue 201 "Fallback child A" OPEN
write_issue 202 "Fallback child B" OPEN
write_issue 900 "Parent epic" OPEN
set_status 201 "In Development"
set_status 202 "In Development"
set_status 900 "In Development"
fallback_result="$(run_closeout)"
fallback_body="$(last_output_body "$fallback_result")"
run_test "fallback_exit_zero" "0" "$(last_output_status "$fallback_result")"
run_contains "fallback_closed_count" "CLOSED_COUNT=2" "$fallback_body"
run_contains "fallback_label_source" "label:integration-branch:test" "$fallback_body"

echo ""
echo "=== graduation closeout: closing keyword parser ==="
reset_fixture
export MOCK_NATIVE_MODE=empty
export MOCK_PR_MODE=parser
for issue in 301 302 303 304 395 396 397 398 399; do
  write_issue "$issue" "Parser $issue" OPEN
  set_status "$issue" "In Development"
done
write_issue 900 "Parent epic" OPEN
set_status 900 "In Development"
parser_result="$(run_closeout)"
parser_body="$(last_output_body "$parser_result")"
run_test "parser_exit_zero" "0" "$(last_output_status "$parser_result")"
run_contains "parser_variants_count" "CLOSED_COUNT=4" "$parser_body"
run_contains "parser_parentheses_match" "#303" "$parser_body"
run_contains "parser_markdown_match" "#304" "$parser_body"
run_not_contains "parser_disclose_ignored" "#398" "$parser_body"
run_not_contains "parser_hotfix_ignored" "#399" "$parser_body"
run_not_contains "parser_cross_repo_ignored" "#395" "$parser_body"
run_not_contains "parser_related_repo_ignored" "#396" "$parser_body"
run_not_contains "parser_non_closing_ignored" "#397" "$parser_body"

echo ""
echo "=== graduation closeout: partial failure and epic hold ==="
reset_fixture
export MOCK_NATIVE_MODE=empty
export MOCK_LABEL_ISSUES=$'401\n402'
export MOCK_PR_MODE=none
export MOCK_CLOSE_FAIL_ISSUE=401
write_issue 401 "Fails close" OPEN
write_issue 402 "Still closes" OPEN
write_issue 900 "Parent epic" OPEN
set_status 401 "In Development"
set_status 402 "In Development"
set_status 900 "In Development"
failure_result="$(run_closeout)"
failure_body="$(last_output_body "$failure_result")"
run_test "failure_exit_one" "1" "$(last_output_status "$failure_result")"
run_contains "failure_count" "FAILED_COUNT=1" "$failure_body"
run_contains "failure_other_item_closed" "#402" "$failure_body"
run_contains "failure_epic_held" "EPIC_RESULT=held" "$failure_body"
run_test "failed_issue_stays_open" "OPEN" "$(python3 -c 'import json; print(json.load(open("'"$MOCK_STATE_DIR"'/401.json"))["state"])')"
run_test "other_issue_closed" "CLOSED" "$(python3 -c 'import json; print(json.load(open("'"$MOCK_STATE_DIR"'/402.json"))["state"])')"

echo ""
echo "=== graduation closeout: defer epic and configured terminal status ==="
reset_fixture
export MOCK_NATIVE_MODE=empty
export MOCK_LABEL_ISSUES="501"
export MOCK_PR_MODE=none
export GITHUB_PROJECT_STATUS_GRADUATED=Done
write_issue 501 "Done child" OPEN
write_issue 900 "Parent epic" OPEN
set_status 501 "In Development"
set_status 900 "In Development"
defer_result="$(run_closeout --defer-epic-close)"
defer_body="$(last_output_body "$defer_result")"
run_test "defer_exit_zero" "0" "$(last_output_status "$defer_result")"
run_contains "defer_epic" "EPIC_RESULT=deferred" "$defer_body"
run_contains "defer_label_added" "DEFER_LABEL=added" "$defer_body"
run_contains "configured_terminal_status" "TERMINAL_STATUS=Done" "$defer_body"
run_test "done_status_written" "Done" "$(cat "$MOCK_STATUS_DIR/501")"
run_test "deferred_epic_stays_open" "OPEN" "$(python3 -c 'import json; print(json.load(open("'"$MOCK_STATE_DIR"'/900.json"))["state"])')"
run_contains "defer_label_on_epic" "defer-epic-close" "$(python3 -c 'import json; print(",".join(l["name"] for l in json.load(open("'"$MOCK_STATE_DIR"'/900.json"))["labels"]))')"

# Re-run with label already present — durable signal must stay idempotent.
defer_rerun_result="$(run_closeout --defer-epic-close)"
defer_rerun_body="$(last_output_body "$defer_rerun_result")"
run_test "defer_rerun_exit_zero" "0" "$(last_output_status "$defer_rerun_result")"
run_contains "defer_label_already" "DEFER_LABEL=already_present" "$defer_rerun_body"

echo ""
echo "=== graduation closeout: already-terminal rerun behavior ==="
reset_fixture
export MOCK_NATIVE_MODE=empty
export MOCK_LABEL_ISSUES="601"
export MOCK_PR_MODE=none
write_issue 601 "Already done" CLOSED
write_issue 900 "Parent epic" CLOSED
set_status 601 "Merged"
set_status 900 "Merged"
rerun_result="$(run_closeout)"
rerun_body="$(last_output_body "$rerun_result")"
run_test "rerun_exit_zero" "0" "$(last_output_status "$rerun_result")"
run_contains "rerun_already_count" "ALREADY_TERMINAL_COUNT=1" "$rerun_body"
run_contains "rerun_epic_already" "EPIC_RESULT=already_terminal" "$rerun_body"
run_test "rerun_no_close_calls" "" "$(cat "$MOCK_CLOSE_LOG")"

echo ""
echo "=== graduation closeout: Linear tracker does not touch unrelated GH #326 (#1984) ==="
reset_fixture
write_tracker_config linear
export MOCK_NATIVE_MODE=children
export MOCK_PR_MODE=none
# Unrelated GitHub issue whose number matches the Linear epic numeric suffix.
write_issue 326 "Unrelated GitHub issue" OPEN
set_status 326 "In Development"
CLOSEOUT_EPIC=LEA-326
linear_result="$(run_closeout)"
unset CLOSEOUT_EPIC
linear_body="$(last_output_body "$linear_result")"
run_test "linear_epic_exit_zero" "0" "$(last_output_status "$linear_result")"
run_contains "linear_result_pass" "GRADUATION_CLOSEOUT_RESULT=pass" "$linear_body"
run_contains "linear_provider_reported" "TRACKER_PROVIDER=linear" "$linear_body"
run_contains "linear_deferred_action" "TRACKER_ACTION_REQUIRED=set_status issue=LEA-326" "$linear_body"
run_contains "linear_epic_closed_mode" "EPIC_CLOSE_MODE=linear_deferred" "$linear_body"
run_test "linear_gh_326_stays_open" "OPEN" "$(python3 -c 'import json; print(json.load(open("'"$MOCK_STATE_DIR"'/326.json"))["state"])')"
run_test "linear_no_close_calls" "" "$(cat "$MOCK_CLOSE_LOG")"
run_test "linear_no_label_calls" "" "$(cat "$MOCK_LABEL_LOG")"
run_test "linear_no_subissues_query_326" "0" "$(grep -c '^326$' "$MOCK_GRAPHQL_LOG" || true)"
run_not_contains "linear_no_gh_issue_close_326" "issue close 326" "$(cat "$MOCK_GH_LOG")"
run_not_contains "linear_no_gh_issue_edit_326" "issue edit 326" "$(cat "$MOCK_GH_LOG")"
run_not_contains "linear_no_gh_issue_view_326" "issue view 326" "$(cat "$MOCK_GH_LOG")"

echo ""
echo "=== graduation closeout: Linear empty bridge emission fails closed (#1984 review) ==="
reset_fixture
write_tracker_config linear
export MOCK_PR_MODE=none
export MOCK_LINEAR_UPDATE_EMPTY=1
write_issue 326 "Unrelated GitHub issue" OPEN
CLOSEOUT_EPIC=LEA-326
empty_bridge_result="$(run_closeout)"
unset CLOSEOUT_EPIC
empty_bridge_body="$(last_output_body "$empty_bridge_result")"
run_test "linear_empty_bridge_exit_one" "1" "$(last_output_status "$empty_bridge_result")"
run_contains "linear_empty_bridge_failed_result" "GRADUATION_CLOSEOUT_RESULT=failed" "$empty_bridge_body"
run_contains "linear_empty_bridge_epic_failed" "EPIC_RESULT=failed" "$empty_bridge_body"
run_contains "linear_empty_bridge_reason" "tracker_status_update_failed" "$empty_bridge_body"
run_contains "linear_empty_bridge_error" "without emitting TRACKER_ACTION_REQUIRED=" "$empty_bridge_body"
run_not_contains "linear_empty_bridge_no_false_closed" "EPIC_RESULT=closed" "$empty_bridge_body"
run_test "linear_empty_bridge_326_intact" "OPEN" "$(python3 -c 'import json; print(json.load(open("'"$MOCK_STATE_DIR"'/326.json"))["state"])')"

echo ""
echo "=== graduation closeout: Linear bare --epic 326 fails closed (#1984) ==="
reset_fixture
write_tracker_config linear
export MOCK_PR_MODE=none
write_issue 326 "Unrelated GitHub issue" OPEN
CLOSEOUT_EPIC=326
bare_result="$(run_closeout)"
unset CLOSEOUT_EPIC
bare_body="$(last_output_body "$bare_result")"
run_test "linear_bare_epic_exit_64" "64" "$(last_output_status "$bare_result")"
run_contains "linear_bare_epic_error" "native Linear ID" "$bare_body"
run_test "linear_bare_326_stays_open" "OPEN" "$(python3 -c 'import json; print(json.load(open("'"$MOCK_STATE_DIR"'/326.json"))["state"])')"
run_test "linear_bare_no_close" "" "$(cat "$MOCK_CLOSE_LOG")"
run_test "linear_bare_no_graphql" "" "$(cat "$MOCK_GRAPHQL_LOG")"
run_test "linear_bare_no_gh_mutations" "0" "$(grep -cE 'issue (close|edit) ' "$MOCK_GH_LOG" || true)"

echo ""
echo "=== graduation closeout: Linear --dry-run prints mutations and applies none (#1984) ==="
reset_fixture
write_tracker_config linear
export MOCK_NATIVE_MODE=empty
export MOCK_PR_MODE=single_ref
write_issue 105 "PR referenced child" OPEN
write_issue 326 "Unrelated GitHub issue" OPEN
CLOSEOUT_EPIC=LEA-326
dry_result="$(run_closeout --dry-run)"
unset CLOSEOUT_EPIC
dry_body="$(last_output_body "$dry_result")"
run_test "linear_dry_run_exit_zero" "0" "$(last_output_status "$dry_result")"
run_contains "linear_dry_run_flag" "DRY_RUN=1" "$dry_body"
run_contains "linear_dry_run_tracker" "DRY_RUN would: update_tracker_status LEA-326" "$dry_body"
run_contains "linear_dry_run_gh_close" "DRY_RUN would: gh issue close #105" "$dry_body"
run_test "linear_dry_run_105_stays_open" "OPEN" "$(python3 -c 'import json; print(json.load(open("'"$MOCK_STATE_DIR"'/105.json"))["state"])')"
run_test "linear_dry_run_326_stays_open" "OPEN" "$(python3 -c 'import json; print(json.load(open("'"$MOCK_STATE_DIR"'/326.json"))["state"])')"
run_test "linear_dry_run_no_close_log" "" "$(cat "$MOCK_CLOSE_LOG")"

echo ""
echo "=== graduation closeout: Linear closes only PR-linked GitHub issues (#1984) ==="
reset_fixture
write_tracker_config linear
export MOCK_NATIVE_MODE=children
export MOCK_PR_MODE=single_ref
write_issue 105 "PR referenced child" OPEN
write_issue 326 "Unrelated GitHub issue" OPEN
write_issue 101 "Native child must not be discovered under linear" OPEN
CLOSEOUT_EPIC=LEA-326
linked_result="$(run_closeout)"
unset CLOSEOUT_EPIC
linked_body="$(last_output_body "$linked_result")"
run_test "linear_linked_exit_zero" "0" "$(last_output_status "$linked_result")"
run_test "linear_linked_105_closed" "CLOSED" "$(python3 -c 'import json; print(json.load(open("'"$MOCK_STATE_DIR"'/105.json"))["state"])')"
run_test "linear_linked_326_open" "OPEN" "$(python3 -c 'import json; print(json.load(open("'"$MOCK_STATE_DIR"'/326.json"))["state"])')"
run_test "linear_linked_101_open" "OPEN" "$(python3 -c 'import json; print(json.load(open("'"$MOCK_STATE_DIR"'/101.json"))["state"])')"
run_contains "linear_linked_deferred" "TRACKER_ACTION_REQUIRED=set_status issue=LEA-326" "$linked_body"
run_contains "linear_linked_source" "closingIssuesReferences" "$linked_body"
run_test "linear_linked_no_subissues_326" "0" "$(grep -c '^326$' "$MOCK_GRAPHQL_LOG" || true)"
run_test "linear_linked_no_subissues_any" "" "$(cat "$MOCK_GRAPHQL_LOG")"
run_contains "linear_linked_combined_pr_query" "--json number,title,body,closingIssuesReferences" "$(cat "$MOCK_GH_LOG")"

echo ""
echo "=== graduation closeout: Linear ignores fenced example Closes #326 (#1984 Pass 2) ==="
reset_fixture
write_tracker_config linear
export MOCK_NATIVE_MODE=empty
export MOCK_PR_MODE=fenced_example
write_issue 326 "Unrelated GitHub issue" OPEN
CLOSEOUT_EPIC=LEA-326
fenced_result="$(run_closeout)"
unset CLOSEOUT_EPIC
fenced_body="$(last_output_body "$fenced_result")"
run_test "linear_fenced_exit_zero" "0" "$(last_output_status "$fenced_result")"
run_contains "linear_fenced_pass" "GRADUATION_CLOSEOUT_RESULT=pass" "$fenced_body"
run_contains "linear_fenced_deferred" "TRACKER_ACTION_REQUIRED=set_status issue=LEA-326" "$fenced_body"
run_test "linear_fenced_326_untouched" "OPEN" "$(python3 -c 'import json; print(json.load(open("'"$MOCK_STATE_DIR"'/326.json"))["state"])')"
run_test "linear_fenced_no_close_log" "" "$(cat "$MOCK_CLOSE_LOG")"
run_contains "linear_fenced_skipped" "LINEAR_GITHUB_REF_SKIPPED issue=326 reason=not_structurally_linked" "$fenced_body"
run_contains "linear_fenced_combined_pr_query" "--json number,title,body,closingIssuesReferences" "$(cat "$MOCK_GH_LOG")"

echo ""
echo "=== graduation closeout: Linear ignores tilde-fenced example Closes #326 (#1984 Pass 2) ==="
reset_fixture
write_tracker_config linear
export MOCK_NATIVE_MODE=empty
export MOCK_PR_MODE=tilde_fenced_example
write_issue 326 "Unrelated GitHub issue" OPEN
CLOSEOUT_EPIC=LEA-326
tilde_result="$(run_closeout)"
unset CLOSEOUT_EPIC
tilde_body="$(last_output_body "$tilde_result")"
run_test "linear_tilde_exit_zero" "0" "$(last_output_status "$tilde_result")"
run_contains "linear_tilde_pass" "GRADUATION_CLOSEOUT_RESULT=pass" "$tilde_body"
run_test "linear_tilde_326_untouched" "OPEN" "$(python3 -c 'import json; print(json.load(open("'"$MOCK_STATE_DIR"'/326.json"))["state"])')"
run_test "linear_tilde_no_close_log" "" "$(cat "$MOCK_CLOSE_LOG")"
run_contains "linear_tilde_skipped" "LINEAR_GITHUB_REF_SKIPPED issue=326 reason=not_structurally_linked" "$tilde_body"

echo ""
echo "=== graduation closeout: Linear ignores unclosed-fence example Closes #326 (#1984 Pass 2) ==="
reset_fixture
write_tracker_config linear
export MOCK_NATIVE_MODE=empty
export MOCK_PR_MODE=unclosed_fenced_example
write_issue 326 "Unrelated GitHub issue" OPEN
CLOSEOUT_EPIC=LEA-326
unclosed_result="$(run_closeout)"
unset CLOSEOUT_EPIC
unclosed_body="$(last_output_body "$unclosed_result")"
run_test "linear_unclosed_exit_zero" "0" "$(last_output_status "$unclosed_result")"
run_contains "linear_unclosed_pass" "GRADUATION_CLOSEOUT_RESULT=pass" "$unclosed_body"
run_test "linear_unclosed_326_untouched" "OPEN" "$(python3 -c 'import json; print(json.load(open("'"$MOCK_STATE_DIR"'/326.json"))["state"])')"
run_test "linear_unclosed_no_close_log" "" "$(cat "$MOCK_CLOSE_LOG")"
run_contains "linear_unclosed_skipped" "LINEAR_GITHUB_REF_SKIPPED issue=326 reason=not_structurally_linked" "$unclosed_body"

echo ""
echo "=== graduation closeout: Linear ignores indented-code Closes #326 (#1984 Pass 1) ==="
reset_fixture
write_tracker_config linear
export MOCK_NATIVE_MODE=empty
export MOCK_PR_MODE=indented_code_example
write_issue 326 "Unrelated GitHub issue" OPEN
CLOSEOUT_EPIC=LEA-326
indented_result="$(run_closeout)"
unset CLOSEOUT_EPIC
indented_body="$(last_output_body "$indented_result")"
run_test "linear_indented_exit_zero" "0" "$(last_output_status "$indented_result")"
run_contains "linear_indented_pass" "GRADUATION_CLOSEOUT_RESULT=pass" "$indented_body"
run_test "linear_indented_326_untouched" "OPEN" "$(python3 -c 'import json; print(json.load(open("'"$MOCK_STATE_DIR"'/326.json"))["state"])')"
run_test "linear_indented_no_close_log" "" "$(cat "$MOCK_CLOSE_LOG")"
run_contains "linear_indented_skipped" "LINEAR_GITHUB_REF_SKIPPED issue=326 reason=not_structurally_linked" "$indented_body"

echo ""
echo "=== graduation closeout: Linear skips plain body Closes #326 without structured refs (#1984) ==="
reset_fixture
write_tracker_config linear
export MOCK_NATIVE_MODE=empty
export MOCK_PR_MODE=empty_structured_plain_keyword
write_issue 326 "Unrelated GitHub issue" OPEN
CLOSEOUT_EPIC=LEA-326
plain_result="$(run_closeout)"
unset CLOSEOUT_EPIC
plain_body="$(last_output_body "$plain_result")"
run_test "linear_plain_text_exit_zero" "0" "$(last_output_status "$plain_result")"
run_contains "linear_plain_text_pass" "GRADUATION_CLOSEOUT_RESULT=pass" "$plain_body"
run_test "linear_plain_text_326_untouched" "OPEN" "$(python3 -c 'import json; print(json.load(open("'"$MOCK_STATE_DIR"'/326.json"))["state"])')"
run_test "linear_plain_text_no_close_log" "" "$(cat "$MOCK_CLOSE_LOG")"
run_contains "linear_plain_text_skipped" "LINEAR_GITHUB_REF_SKIPPED issue=326 reason=not_structurally_linked" "$plain_body"
run_not_contains "linear_plain_text_no_keyword_source" "closing_keyword" "$plain_body"

echo ""
echo "=== graduation closeout: Linear ignores foreign-repo closingIssuesReferences #326 (#1984 Pass 1 c2) ==="
reset_fixture
write_tracker_config linear
export MOCK_NATIVE_MODE=empty
export MOCK_PR_MODE=foreign_repo
write_issue 326 "Unrelated local GitHub issue" OPEN
CLOSEOUT_EPIC=LEA-326
foreign_result="$(run_closeout)"
unset CLOSEOUT_EPIC
foreign_body="$(last_output_body "$foreign_result")"
run_test "linear_foreign_exit_zero" "0" "$(last_output_status "$foreign_result")"
run_contains "linear_foreign_pass" "GRADUATION_CLOSEOUT_RESULT=pass" "$foreign_body"
run_contains "linear_foreign_deferred" "TRACKER_ACTION_REQUIRED=set_status issue=LEA-326" "$foreign_body"
run_contains "linear_foreign_skipped_warning" "skipping foreign closingIssuesReferences" "$foreign_body"
run_contains "linear_foreign_skipped_repo" "other/repo" "$foreign_body"
run_test "linear_foreign_326_untouched" "OPEN" "$(python3 -c 'import json; print(json.load(open("'"$MOCK_STATE_DIR"'/326.json"))["state"])')"
run_test "linear_foreign_no_close_log" "" "$(cat "$MOCK_CLOSE_LOG")"
run_not_contains "linear_foreign_no_close_326" "issue close 326" "$(cat "$MOCK_GH_LOG")"

echo ""
echo "=== graduation closeout: github_projects behavior unchanged with explicit config (#1984) ==="
reset_fixture
write_tracker_config github_projects
write_issue 101 "Open child" OPEN
write_issue 102 "Closed nonterminal" CLOSED
write_issue 103 "Closed terminal" CLOSED
write_issue 104 "Optional child" OPEN optional
write_issue 105 "PR referenced child" OPEN
write_issue 900 "Parent epic" OPEN
set_status 101 "In Development"
set_status 102 "Development in Review"
set_status 103 "Merged"
set_status 104 "In Development"
set_status 105 "Plan Ready"
set_status 900 "In Development"
gh_proj_result="$(run_closeout)"
gh_proj_body="$(last_output_body "$gh_proj_result")"
run_test "github_projects_exit_zero" "0" "$(last_output_status "$gh_proj_result")"
run_contains "github_projects_pass" "GRADUATION_CLOSEOUT_RESULT=pass" "$gh_proj_body"
run_contains "github_projects_provider" "TRACKER_PROVIDER=github_projects" "$gh_proj_body"
run_test "github_projects_child_closed" "CLOSED" "$(python3 -c 'import json; print(json.load(open("'"$MOCK_STATE_DIR"'/101.json"))["state"])')"
run_contains "github_projects_epic_close" "900" "$(cat "$MOCK_CLOSE_LOG")"
run_not_contains "github_projects_no_linear_action" "TRACKER_ACTION_REQUIRED=" "$gh_proj_body"

echo ""
echo "=== graduation closeout: commented header + github_projects keeps legacy path (#1984) ==="
reset_fixture
cat > "$FIXTURE_REPO/.ai-dev-workflow.yaml" <<'EOF'
issue_tracker: # tracker
  provider: github_projects
EOF
write_issue 101 "Open child" OPEN
write_issue 102 "Closed nonterminal" CLOSED
write_issue 103 "Closed terminal" CLOSED
write_issue 104 "Optional child" OPEN optional
write_issue 105 "PR referenced child" OPEN
write_issue 900 "Parent epic" OPEN
set_status 101 "In Development"
set_status 102 "Development in Review"
set_status 103 "Merged"
set_status 104 "In Development"
set_status 105 "Plan Ready"
set_status 900 "In Development"
commented_gh_result="$(run_closeout)"
commented_gh_body="$(last_output_body "$commented_gh_result")"
run_test "commented_gh_projects_exit_zero" "0" "$(last_output_status "$commented_gh_result")"
run_contains "commented_gh_projects_provider" "TRACKER_PROVIDER=github_projects" "$commented_gh_body"
run_contains "commented_gh_projects_pass" "GRADUATION_CLOSEOUT_RESULT=pass" "$commented_gh_body"
run_test "commented_gh_projects_child_closed" "CLOSED" "$(python3 -c 'import json; print(json.load(open("'"$MOCK_STATE_DIR"'/101.json"))["state"])')"
run_contains "commented_gh_projects_epic_close" "900" "$(cat "$MOCK_CLOSE_LOG")"
run_not_contains "commented_gh_projects_no_linear" "TRACKER_ACTION_REQUIRED=" "$commented_gh_body"

echo ""
echo "=== graduation closeout: commented header + github_issues keeps legacy path (#1984) ==="
reset_fixture
cat > "$FIXTURE_REPO/.ai-dev-workflow.yaml" <<'EOF'
issue_tracker: # tracker
  provider: github_issues
EOF
write_issue 101 "Open child" OPEN
write_issue 102 "Closed nonterminal" CLOSED
write_issue 103 "Closed terminal" CLOSED
write_issue 104 "Optional child" OPEN optional
write_issue 105 "PR referenced child" OPEN
write_issue 900 "Parent epic" OPEN
set_status 101 "In Development"
set_status 102 "Development in Review"
set_status 103 "Merged"
set_status 104 "In Development"
set_status 105 "Plan Ready"
set_status 900 "In Development"
commented_issues_result="$(run_closeout)"
commented_issues_body="$(last_output_body "$commented_issues_result")"
run_test "commented_gh_issues_exit_zero" "0" "$(last_output_status "$commented_issues_result")"
# Legacy shared parser sees empty under commented header → same default as develop.
run_contains "commented_gh_issues_provider" "TRACKER_PROVIDER=github_projects" "$commented_issues_body"
run_contains "commented_gh_issues_pass" "GRADUATION_CLOSEOUT_RESULT=pass" "$commented_issues_body"
run_test "commented_gh_issues_child_closed" "CLOSED" "$(python3 -c 'import json; print(json.load(open("'"$MOCK_STATE_DIR"'/101.json"))["state"])')"
run_contains "commented_gh_issues_epic_close" "900" "$(cat "$MOCK_CLOSE_LOG")"

echo ""
echo "=== graduation closeout: commented header + linear fails closed before mutation (#1984) ==="
reset_fixture
cat > "$FIXTURE_REPO/.ai-dev-workflow.yaml" <<'EOF'
issue_tracker: # native tracker
  provider: linear
EOF
export MOCK_NATIVE_MODE=empty
export MOCK_PR_MODE=none
write_issue 326 "Unrelated GitHub issue" OPEN
CLOSEOUT_EPIC=LEA-326
commented_lea_result="$(run_closeout)"
unset CLOSEOUT_EPIC
commented_lea_body="$(last_output_body "$commented_lea_result")"
run_test "commented_linear_lea_exit_64" "64" "$(last_output_status "$commented_lea_result")"
run_contains "commented_linear_lea_remediation" "tracker bridge cannot read it" "$commented_lea_body"
run_contains "commented_linear_lea_fix_header" "Remove the trailing comment from the 'issue_tracker:' line" "$commented_lea_body"
run_test "commented_linear_lea_326_untouched" "OPEN" "$(python3 -c 'import json; print(json.load(open("'"$MOCK_STATE_DIR"'/326.json"))["state"])')"
run_test "commented_linear_lea_no_close_log" "" "$(cat "$MOCK_CLOSE_LOG")"
run_not_contains "commented_linear_lea_no_mutation" "issue close" "$(cat "$MOCK_GH_LOG")"
run_not_contains "commented_linear_lea_no_deferred" "TRACKER_ACTION_REQUIRED=" "$commented_lea_body"
run_not_contains "commented_linear_lea_no_gh_api" "api graphql" "$(cat "$MOCK_GH_LOG")"

echo ""
echo "=== graduation closeout: uncommented linear + LEA-326 uses real bridge (#1984) ==="
reset_fixture
write_tracker_config linear
export MOCK_NATIVE_MODE=empty
export MOCK_PR_MODE=none
write_issue 326 "Unrelated GitHub issue" OPEN
CLOSEOUT_EPIC=LEA-326
uncommented_lea_result="$(run_closeout)"
unset CLOSEOUT_EPIC
uncommented_lea_body="$(last_output_body "$uncommented_lea_result")"
run_test "uncommented_linear_lea_exit_zero" "0" "$(last_output_status "$uncommented_lea_result")"
run_contains "uncommented_linear_lea_provider" "TRACKER_PROVIDER=linear" "$uncommented_lea_body"
run_contains "uncommented_linear_lea_deferred" "TRACKER_ACTION_REQUIRED=set_status issue=LEA-326" "$uncommented_lea_body"
run_test "uncommented_linear_lea_326_untouched" "OPEN" "$(python3 -c 'import json; print(json.load(open("'"$MOCK_STATE_DIR"'/326.json"))["state"])')"
run_test "uncommented_linear_lea_no_close_log" "" "$(cat "$MOCK_CLOSE_LOG")"
run_not_contains "uncommented_linear_lea_no_mutation" "issue close" "$(cat "$MOCK_GH_LOG")"

# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# #2016 — GitHub providers use GFM fixtures (recorded gh api markdown HTML)
# ---------------------------------------------------------------------------

# shellcheck disable=SC1091
. "$REPO_ROOT/scripts/development-workflow/closing-keyword-lib.sh"
# shellcheck disable=SC1091
. "$REPO_ROOT/scripts/development-workflow/graduation-closeout-lib.sh"

assert_gfm_fixture_untouched() {
  local provider="$1"
  local fixture="$2"
  local label="$3"
  local issue="$4"
  reset_fixture
  write_tracker_config "$provider"
  export MOCK_NATIVE_MODE=children
  export MOCK_PR_MODE=gfm_fixture
  export MOCK_GFM_FIXTURE="$fixture"
  write_issue 101 "Open child" OPEN
  write_issue 102 "Closed nonterminal" CLOSED
  write_issue 103 "Closed terminal" CLOSED
  write_issue 104 "Optional child" OPEN optional
  write_issue "$issue" "Example-only issue" OPEN
  write_issue 900 "Parent epic" OPEN
  set_status 101 "In Development"
  set_status 102 "Development in Review"
  set_status 103 "Merged"
  set_status 104 "In Development"
  set_status "$issue" "In Development"
  set_status 900 "In Development"
  local result body
  result="$(run_closeout)"
  body="$(last_output_body "$result")"
  run_test "${label}_exit_zero" "0" "$(last_output_status "$result")"
  run_contains "${label}_pass" "GRADUATION_CLOSEOUT_RESULT=pass" "$body"
  run_contains "${label}_provider" "TRACKER_PROVIDER=${provider}" "$body"
  run_test "${label}_child_closed" "CLOSED" "$(python3 -c 'import json; print(json.load(open("'"$MOCK_STATE_DIR"'/101.json"))["state"])')"
  run_test "${label}_${issue}_untouched" "OPEN" "$(python3 -c 'import json; print(json.load(open("'"$MOCK_STATE_DIR"'/'"$issue"'.json"))["state"])')"
  run_not_contains "${label}_no_close_${issue}" "issue close ${issue}" "$(cat "$MOCK_GH_LOG")"
  run_not_contains "${label}_no_close_log_${issue}" "${issue}"$'\t' "$(cat "$MOCK_CLOSE_LOG")"
}

assert_gfm_fixture_closed() {
  local provider="$1"
  local fixture="$2"
  local issue="$3"
  local label="$4"
  reset_fixture
  write_tracker_config "$provider"
  export MOCK_NATIVE_MODE=empty
  export MOCK_PR_MODE=gfm_fixture
  export MOCK_GFM_FIXTURE="$fixture"
  write_issue "$issue" "Live closing keyword" OPEN
  write_issue 900 "Parent epic" OPEN
  set_status "$issue" "In Development"
  set_status 900 "In Development"
  local result body
  result="$(run_closeout)"
  body="$(last_output_body "$result")"
  run_test "${label}_exit_zero" "0" "$(last_output_status "$result")"
  run_contains "${label}_pass" "GRADUATION_CLOSEOUT_RESULT=pass" "$body"
  run_test "${label}_issue_closed" "CLOSED" "$(python3 -c 'import json; print(json.load(open("'"$MOCK_STATE_DIR"'/'"$issue"'.json"))["state"])')"
  run_contains "${label}_close_log" "$issue" "$(cat "$MOCK_CLOSE_LOG")"
}


echo ""
echo "=== graduation closeout: long Unicode body after prose keyword (#2016 Pass 1) ==="
# pipefail is on; prefilter must not SIGPIPE (141) when the keyword is early
# and a huge Unicode tail follows. Body via file/stdin — never argv.
long_unicode_file="$TMP_ROOT/long-unicode-prefilter.txt"
python3 -c 'import sys; sys.stdout.write("Closes #326" + ("あ" * 60000))' >"$long_unicode_file"
set +e
graduation_closeout_raw_has_closing_keyword_candidate <"$long_unicode_file"
prefilter_status=$?
set -e
run_test "long_unicode_prefilter_exit_zero" "0" "$prefilter_status"
run_test "long_unicode_prefilter_file_over_128kib" "1" "$(python3 -c 'import pathlib,sys; print(1 if pathlib.Path(sys.argv[1]).stat().st_size > 131072 else 0)' "$long_unicode_file")"

echo ""
echo "=== graduation closeout: render_gfm preserves caller \$- (#2016 Pass 1) ==="
assert_render_gfm_preserves_shell_opts() {
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
    run_test "render_opts_${mode}_success_status" "0" "$status"
  else
    run_test "render_opts_${mode}_fail_status" "1" "$status"
  fi
  run_test "render_opts_${mode}_expect${expect_ok}_dollar_unchanged" "$before" "$after"
  set -e
}
# Need mock gh on PATH for render_gfm — already installed for the suite.
assert_render_gfm_preserves_shell_opts errexit_on 1
assert_render_gfm_preserves_shell_opts errexit_on 0
assert_render_gfm_preserves_shell_opts errexit_off 1
assert_render_gfm_preserves_shell_opts errexit_off 0

echo ""
echo "=== graduation closeout: long Unicode prose still closes #326 (#2016 Pass 1) ==="
for provider in github_projects github_issues; do
  reset_fixture
  write_tracker_config "$provider"
  export MOCK_NATIVE_MODE=empty
  export MOCK_PR_MODE=long_unicode_prose
  write_issue 326 "Live closing keyword" OPEN
  write_issue 900 "Parent epic" OPEN
  set_status 326 "In Development"
  set_status 900 "In Development"
  result="$(run_closeout)"
  body="$(last_output_body "$result")"
  run_test "${provider}_long_unicode_exit_zero" "0" "$(last_output_status "$result")"
  run_contains "${provider}_long_unicode_pass" "GRADUATION_CLOSEOUT_RESULT=pass" "$body"
  run_test "${provider}_long_unicode_issue_closed" "CLOSED" "$(python3 -c 'import json; print(json.load(open("'"$MOCK_STATE_DIR"'/326.json"))["state"])')"
  run_contains "${provider}_long_unicode_close_log" "326" "$(cat "$MOCK_CLOSE_LOG")"
done


echo ""
echo "=== graduation closeout: production PR text never passed as external argv (#2016) ==="
argv_hits="$(python3 - "$REPO_ROOT" <<'PYAUDIT'
import pathlib, re, sys
root = pathlib.Path(sys.argv[1])
files = [
    root / "scripts/development-workflow/graduation-closeout.sh",
    root / "scripts/development-workflow/graduation-closeout-from-merged-pr.sh",
    root / "scripts/development-workflow/graduation-closeout-lib.sh",
]
var_pr_text = r"\$\{?(?:body|title|text|raw|payload|title_raw|body_raw|title_enc|body_enc|visible|html)\}?"
hits = []
for path in files:
    for i, line in enumerate(path.read_text().splitlines(), 1):
        s = line.lstrip()
        if not s or s.startswith("#"):
            continue
        if not re.search(r"\b(python3|jq|gh)\b", line):
            continue
        if not re.search(var_pr_text, line):
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
  echo "PASS: production_pr_text_argv_audit_clean"
  PASS_COUNT=$((PASS_COUNT + 1))
fi

echo ""
echo "=== graduation closeout: >130KiB multibyte body via production stdin path (#2016) ==="
huge_body_file="$TMP_ROOT/huge-multibyte-body.txt"
python3 -c 'import sys; sys.stdout.write("Closes #326\n" + ("あ" * 50000))' >"$huge_body_file"
run_test "huge_body_over_130kib" "1" "$(python3 -c 'import pathlib,sys; print(1 if pathlib.Path(sys.argv[1]).stat().st_size > 131072 else 0)' "$huge_body_file")"
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
guard_status="$(python3 - "$argv_guard" "$huge_body_file" <<'PY'
import os, subprocess, sys
guard, path = sys.argv[1], sys.argv[2]
body = open(path, encoding="utf-8").read()
try:
    r = subprocess.run([guard, body], capture_output=True)
    print(r.returncode)
except OSError as e:
    import errno
    print(99 if getattr(e, "errno", None) == errno.E2BIG else 1)
PY
)"
run_test "argv_guard_rejects_huge_argv" "99" "$guard_status"
set +e
graduation_closeout_raw_has_closing_keyword_candidate <"$huge_body_file"
huge_pre_st=$?
set -e
run_test "huge_stdin_prefilter_ok" "0" "$huge_pre_st"
for provider in github_projects github_issues; do
  reset_fixture
  write_tracker_config "$provider"
  export MOCK_NATIVE_MODE=empty
  export MOCK_PR_MODE=huge_body_file
  export MOCK_HUGE_BODY_FILE="$huge_body_file"
  write_issue 326 "Live closing keyword" OPEN
  write_issue 900 "Parent epic" OPEN
  set_status 326 "In Development"
  set_status 900 "In Development"
  result="$(run_closeout)"
  body="$(last_output_body "$result")"
  run_test "${provider}_huge_stdin_exit_zero" "0" "$(last_output_status "$result")"
  run_contains "${provider}_huge_stdin_pass" "GRADUATION_CLOSEOUT_RESULT=pass" "$body"
  run_test "${provider}_huge_stdin_issue_closed" "CLOSED" "$(python3 -c 'import json; print(json.load(open("'"$MOCK_STATE_DIR"'/326.json"))["state"])')"
done
unset MOCK_HUGE_BODY_FILE

echo ""
echo "=== graduation closeout: planted violation — raw fenced text would keep #326 (#2016) ==="
planted_md="$(cat "$GFM_FIXTURE_DIR/fenced_tick.md")"
planted_html="$(cat "$GFM_FIXTURE_DIR/fenced_tick.html")"
# Planted violation: raw-text keyword scan (no GFM) still sees #326 in the fence;
# rendered visible text + shared live_refs does not.
raw_refs="$(printf '%s' "$planted_md" | grep -ioE "$CLOSING_KEYWORD_REGEX" | grep -oE '[0-9]+$' || true)"
vis_refs="$(printf '%s' "$planted_html" | graduation_closeout_html_visible_text | closing_keyword_live_refs || true)"
run_test "planted_raw_finds_326" "326" "$(printf '%s' "$raw_refs" | head -n1)"
run_test "planted_rendered_strips_326" "" "$(printf '%s' "$vis_refs")"

echo ""
echo "=== graduation closeout: code-boundary placeholder prevents Closes+code+# fusion (#2016) ==="
fusion_html="$(cat "$GFM_FIXTURE_DIR/closes_code_repo_then_prose.html")"
fusion_vis="$(printf '%s' "$fusion_html" | graduation_closeout_html_visible_text)"
fusion_refs="$(printf '%s' "$fusion_vis" | closing_keyword_live_refs | tr '\n' ' ')"
run_contains "code_boundary_vis_has_placeholder" "[code]" "$fusion_vis"
run_not_contains "code_boundary_vis_not_fused_closes_326" "Closes #326" "$(printf '%s' "$fusion_vis" | tr '\n' ' ')"
run_test "code_boundary_refs_only_123" "123" "$(printf '%s' "$fusion_refs" | awk '{print $1}')"
run_not_contains "code_boundary_refs_no_326" "326" "$fusion_refs"
gap_refs="$(cat "$GFM_FIXTURE_DIR/fixes_code_between_keyword_ref.html" | graduation_closeout_html_visible_text | closing_keyword_live_refs || true)"
run_test "code_gap_fixes_not_selected" "" "$(printf '%s' "$gap_refs")"
see_refs="$(cat "$GFM_FIXTURE_DIR/see_code_then_closes.html" | graduation_closeout_html_visible_text | closing_keyword_live_refs | tr '\n' ' ')"
run_test "see_code_then_closes_328" "328" "$(printf '%s' "$see_refs" | awk '{print $1}')"


echo ""
echo "=== graduation closeout: markdown API failure fail-closes text refs (#2016) ==="
for provider in github_projects github_issues; do
  reset_fixture
  write_tracker_config "$provider"
  export MOCK_NATIVE_MODE=children
  export MOCK_PR_MODE=gfm_fixture
  export MOCK_GFM_FIXTURE=plain_prose
  export MOCK_MARKDOWN_FAIL=1
  write_issue 101 "Open child" OPEN
  write_issue 102 "Closed nonterminal" CLOSED
  write_issue 103 "Closed terminal" CLOSED
  write_issue 104 "Optional child" OPEN optional
  write_issue 326 "Should stay open" OPEN
  write_issue 900 "Parent epic" OPEN
  set_status 101 "In Development"
  set_status 102 "Development in Review"
  set_status 103 "Merged"
  set_status 104 "In Development"
  set_status 326 "In Development"
  set_status 900 "In Development"
  result="$(run_closeout)"
  body="$(last_output_body "$result")"
  unset MOCK_MARKDOWN_FAIL
  run_test "${provider}_md_fail_exit_zero" "0" "$(last_output_status "$result")"
  run_contains "${provider}_md_fail_unavailable" "CLOSEOUT_TEXT_REFS_UNAVAILABLE pr=11" "$body"
  run_test "${provider}_md_fail_326_untouched" "OPEN" "$(python3 -c 'import json; print(json.load(open("'"$MOCK_STATE_DIR"'/326.json"))["state"])')"
  run_not_contains "${provider}_md_fail_no_close_326" "issue close 326" "$(cat "$MOCK_GH_LOG")"
done

for provider in github_projects github_issues; do
  echo ""
  echo "=== graduation closeout: ${provider} GFM fixture matrix (#2016) ==="
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    name="$(printf '%s' "$row" | python3 -c 'import json,sys; print(json.load(sys.stdin)["name"])')"
    refs="$(printf '%s' "$row" | python3 -c 'import json,sys; print(" ".join(json.load(sys.stdin).get("expected_refs") or []))')"
    if [ -z "$refs" ]; then
      issue="$(cat "$GFM_FIXTURE_DIR/${name}.md" | closing_keyword_live_refs | head -n1 || true)"
      [ -n "$issue" ] || issue=326
      assert_gfm_fixture_untouched "$provider" "$name" "${provider}_gfm_${name}" "$issue"
    else
      issue="$(printf '%s' "$refs" | awk '{print $1}')"
      assert_gfm_fixture_closed "$provider" "$name" "$issue" "${provider}_gfm_${name}"
    fi
  done < <(python3 -c 'import json,pathlib; print("\n".join(json.dumps(x) for x in json.loads(pathlib.Path("'"$GFM_FIXTURE_DIR"'/manifest.json").read_text())))')
done


echo ""
echo "Graduation closeout tests: $PASS_COUNT passed, $FAIL_COUNT failed."
if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
