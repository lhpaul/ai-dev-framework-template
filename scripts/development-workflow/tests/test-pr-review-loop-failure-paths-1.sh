#!/usr/bin/env bash
# shellcheck disable=SC2034
# test-pr-review-loop-failure-paths-1.sh — pr-review-loop.sh harness: Area 13
# (PR #801 failure paths), part 1 of 4.
# duration: 130
# covers: scripts/development-workflow/pr-review-loop.sh
# covers: scripts/development-workflow/tests/lib/pr-review-loop-harness.sh
# covers: docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md
#
# The pr-review-loop.sh harness is split across these suites (#1876), which
# share their preamble — snapshot re-exec, --area filter, gh/git mocks, the
# HARNESS_MODE source of pr-review-loop.sh, and the run_test helpers — through
# tests/lib/pr-review-loop-harness.sh:
#
#   test-pr-review-loop.sh
#   test-pr-review-loop-cycles-labels.sh
#   test-pr-review-loop-failure-paths-1.sh
#   test-pr-review-loop-failure-paths-2.sh
#   test-pr-review-loop-failure-paths-3.sh
#   test-pr-review-loop-failure-paths-4.sh
#   test-pr-review-loop-release-bugbot.sh
#   test-pr-review-loop-pr-agent-coderabbit.sh
#   test-pr-review-loop-staged-gates.sh
#   test-pr-review-loop-no-verdict-yet.sh
#
# Areas in this suite:
#   Area 13: PR #801 reviewer-loop failure paths (part 1 of 4)
#
# Usage: bash scripts/development-workflow/tests/test-pr-review-loop-failure-paths-1.sh [--area <name>]... [--list-areas]
# No external tooling required beyond bash, git, and jq (git only locates the
# repository root at startup; mock gh commands replace all network calls).
#
# Exit code: 0 if all tests pass, 1 if any test fails, 2 on a usage error.
#
# SC2034 is disabled for the whole file (line 2). Most assignments here set
# pr-review-loop.sh globals that the functions under test read; ShellCheck does
# not follow that source, so it sees every one as unused. When the harness was
# a single file the warning stayed quiet only because some other area happened
# to read the same name — coincidence, not analysis.

set -euo pipefail

# Resolve the shared harness from the checked-in suite path. Inside a snapshot
# run $0 is a temp copy, so TEST_PR_REVIEW_LOOP_ORIGIN (set by the harness on
# re-exec, or by hand for an out-of-tree copy) takes precedence.
_prl_harness="$(dirname -- "${TEST_PR_REVIEW_LOOP_ORIGIN:-$0}")/lib/pr-review-loop-harness.sh"
if [ ! -f "$_prl_harness" ]; then
  echo "ERROR: shared harness not found: $_prl_harness" >&2
  echo "  Run the checked-in suite, or set TEST_PR_REVIEW_LOOP_ORIGIN to its path." >&2
  exit 2
fi
# shellcheck source=scripts/development-workflow/tests/lib/pr-review-loop-harness.sh
source "$_prl_harness" "$@"
unset _prl_harness

# ---------------------------------------------------------------------------
# Area 13: PR #801 follow-up coverage for reviewer-loop failure paths
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 13: PR #801 reviewer-loop failure paths (part 1 of 4) ==="

export CODEX_GITHUB_PRE_TRIGGER_WAIT=0

export MOCK_GH_OUTPUT='{
  "reviewThreads": {
  "pageInfo": {"hasNextPage": false, "endCursor": null},
  "nodes": [
    {
      "id": "thread-outdated",
      "isResolved": false,
      "isOutdated": true,
      "firstComment": {
        "nodes": [
          {
            "author": {"login": "chatgpt-codex-connector"},
            "body": "stale Codex finding"
          }
        ]
      }
    },
    {
      "id": "thread-active",
      "isResolved": false,
      "isOutdated": false,
      "firstComment": {
        "nodes": [
          {
            "author": {"login": "chatgpt-codex-connector"},
            "body": "active Codex finding"
          }
        ]
      }
    }
  ]
  }
}'
run_test "codex_thread_audit_ignores_outdated" "1" \
  "$(check_unresolved_threads "42" "owner/repo" strict "chatgpt-codex-connector")"
export MOCK_GH_OUTPUT='{
  "reviewThreads": {
  "pageInfo": {"hasNextPage": false, "endCursor": null},
  "nodes": [
    {
      "id": "thread-outdated",
      "isResolved": false,
      "isOutdated": true,
      "firstComment": {
        "nodes": [
          {
            "author": {"login": "chatgpt-codex-connector"},
            "body": "stale Codex finding"
          }
        ]
      }
    }
  ]
  }
}'
run_test "codex_thread_audit_all_outdated_clean" "0" \
  "$(check_unresolved_threads "42" "owner/repo" strict "chatgpt-codex-connector")"
unset MOCK_GH_OUTPUT

manual_readiness_audit_count() {
  jq --arg codex_bot "chatgpt-codex-connector" '[.data.repository.pullRequest.reviewThreads.nodes[]
        | select(.isResolved == false)
        | select((.isOutdated // false) == false)
        | select(.comments.nodes[0].author.login as $a | ["coderabbitai","devin-ai-integration","greptile-apps",$codex_bot] | index($a) != null)
        | select((.comments.nodes[0].body // "") | test("✅ Addressed") | not)] | length'
}

_manual_audit_fixture='{
  "data": {
    "repository": {
      "pullRequest": {
        "reviewThreads": {
          "nodes": [
            {
              "id": "active-codex",
              "isResolved": false,
              "isOutdated": false,
              "comments": {
                "nodes": [
                  {
                    "author": {"login": "chatgpt-codex-connector"},
                    "body": "active Codex finding"
                  }
                ]
              }
            },
            {
              "id": "outdated-codex",
              "isResolved": false,
              "isOutdated": true,
              "comments": {
                "nodes": [
                  {
                    "author": {"login": "chatgpt-codex-connector"},
                    "body": "stale Codex finding"
                  }
                ]
              }
            },
            {
              "id": "addressed-coderabbit",
              "isResolved": false,
              "isOutdated": false,
              "comments": {
                "nodes": [
                  {
                    "author": {"login": "coderabbitai"},
                    "body": "✅ Addressed in latest commit"
                  }
                ]
              }
            }
          ]
        }
      }
    }
  }
}'
run_test "manual_readiness_audit_active_codex_blocks" "1" \
  "$(printf '%s\n' "$_manual_audit_fixture" | manual_readiness_audit_count)"

_manual_audit_fixture_outdated_only='{
  "data": {
    "repository": {
      "pullRequest": {
        "reviewThreads": {
          "nodes": [
            {
              "id": "outdated-codex",
              "isResolved": false,
              "isOutdated": true,
              "comments": {
                "nodes": [
                  {
                    "author": {"login": "chatgpt-codex-connector"},
                    "body": "stale Codex finding"
                  }
                ]
              }
            }
          ]
        }
      }
    }
  }
}'
run_test "manual_readiness_audit_outdated_codex_passes" "0" \
  "$(printf '%s\n' "$_manual_audit_fixture_outdated_only" | manual_readiness_audit_count)"

_docs_is_outdated_field_count="$(grep -h 'nodes { isResolved isOutdated comments(first: 1)' \
  "$REPO_ROOT/docs/workflow/development-workflow/protocols/03-implement-development-protocol.md" \
  "$REPO_ROOT/docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md" \
  | wc -l | tr -d ' ')"
run_test "manual_readiness_audit_docs_request_is_outdated" "5" "$_docs_is_outdated_field_count"

_docs_is_outdated_filter_count="$(grep -h 'select((.isOutdated // false) == false)' \
  "$REPO_ROOT/docs/workflow/development-workflow/protocols/03-implement-development-protocol.md" \
  "$REPO_ROOT/docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md" \
  | wc -l | tr -d ' ')"
run_test "manual_readiness_audit_docs_filter_outdated" "5" "$_docs_is_outdated_filter_count"
unset _manual_audit_fixture _manual_audit_fixture_outdated_only _docs_is_outdated_field_count _docs_is_outdated_filter_count

if grep -q "Codex acknowledgement detected; waiting for current-head review or inline review comments" \
    "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh"; then
  _codex_ack_wait_signal="yes"
else
  _codex_ack_wait_signal="no"
fi
run_test "codex_reviewer_ack_wait_signal" "yes" "$_codex_ack_wait_signal"
unset _codex_ack_wait_signal

_codex_trigger_comments='[
  {
    "id": 111,
    "created_at": "2026-01-01T00:00:00Z",
    "user": {"login": "alice"},
    "body": "Review triggered by workflow runner for abc123"
  },
  {
    "id": 222,
    "created_at": "2026-01-01T00:05:00Z",
    "user": {"login": "bob"},
    "body": "Review triggered by workflow runner for abc123"
  },
  {
    "id": 333,
    "created_at": "2026-01-01T00:10:00Z",
    "user": {"login": "chatgpt-codex-connector[bot]"},
    "body": "Review triggered by workflow runner for abc123"
  }
]'
_codex_selected_trigger="$(
  printf '%s\n' "$_codex_trigger_comments" \
    | jq -sc --arg sha "abc123" --arg marker "review triggered by workflow runner" --arg bot "chatgpt-codex-connector[bot]" --arg bot_plain "chatgpt-codex-connector" \
      '[.[][] | select(.user.login != $bot and .user.login != $bot_plain) | select((.body | contains($sha)) and (.body | ascii_downcase | contains($marker)))] | sort_by(.created_at) | reverse | .[0] // empty | {id: .id, created_at: .created_at, body: .body}'
)"
run_test "codex_trigger_idempotency_selects_newest" "222" \
  "$(printf '%s\n' "$_codex_selected_trigger" | jq -r '.id')"
run_test "codex_trigger_idempotency_single_object" "1" \
  "$(printf '%s\n' "$_codex_selected_trigger" | wc -l | tr -d ' ')"
_codex_paginated_trigger_comments='[
  {
    "id": 111,
    "created_at": "2026-01-01T00:00:00Z",
    "user": {"login": "alice"},
    "body": "Review triggered by workflow runner for abc123"
  }
]
[
  {
    "id": 222,
    "created_at": "2026-01-01T00:05:00Z",
    "user": {"login": "bob"},
    "body": "Review triggered by workflow runner for abc123"
  }
]'
_codex_paginated_selected_trigger="$(
  printf '%s\n' "$_codex_paginated_trigger_comments" \
    | jq -sc --arg sha "abc123" --arg marker "review triggered by workflow runner" --arg bot "chatgpt-codex-connector[bot]" --arg bot_plain "chatgpt-codex-connector" \
      '[.[][] | select(.user.login != $bot and .user.login != $bot_plain) | select((.body | contains($sha)) and (.body | ascii_downcase | contains($marker)))] | sort_by(.created_at) | reverse | .[0] // empty | {id: .id, created_at: .created_at, body: .body}'
)"
run_test "codex_trigger_idempotency_paginated_selects_newest" "222" \
  "$(printf '%s\n' "$_codex_paginated_selected_trigger" | jq -r '.id')"
run_test "codex_trigger_idempotency_paginated_single_object" "1" \
  "$(printf '%s\n' "$_codex_paginated_selected_trigger" | wc -l | tr -d ' ')"
unset _codex_trigger_comments _codex_selected_trigger _codex_paginated_trigger_comments _codex_paginated_selected_trigger

_codex_pending_idempotent_dir="$(mktemp -d)"
cat > "$_codex_pending_idempotent_dir/gh" <<'CODEX_PENDING_IDEMPOTENT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*) exit 0 ;;
  *"pr view"*headRefOid*) printf 'abc123pending0000000000000000000000000000\n'; exit 0 ;;
  *"--method POST"*)
    printf 'ERROR=duplicate-trigger-post\n' >&2
    exit 64 ;;
  *"issues/comments/"*"/reactions"*) printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*) printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*) printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":901,"created_at":"2026-01-01T00:00:00Z","user":{"login":"alice"},"body":"@codex review (review triggered by workflow runner, commit: abc123pending0000000000000000000000000000)"}]\n'
    exit 0 ;;
  *) printf 'ERROR=unexpected-gh-invocation\n' >&2; printf 'ARGS=%q\n' "$*" >&2; exit 64 ;;
esac
CODEX_PENDING_IDEMPOTENT_GH
chmod +x "$_codex_pending_idempotent_dir/gh"
_codex_pending_idempotent_exit=0
PATH="$_codex_pending_idempotent_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --pre-trigger-wait 0 --max-retriggers 0 \
  >"$_codex_pending_idempotent_dir/output.txt" 2>&1 || _codex_pending_idempotent_exit=$?
_codex_pending_idempotent_output="$(cat "$_codex_pending_idempotent_dir/output.txt")"
run_test "codex_pending_existing_trigger_exit_waiting" "4" "$_codex_pending_idempotent_exit"
run_test "codex_pending_existing_trigger_verdict" \
  "VERDICT: WAITING_ON_REVIEWER — current-head Codex review is still pending after 1s (budget 1s) across up to 1 attempt(s)" \
  "$(printf '%s\n' "$_codex_pending_idempotent_output" | grep "^VERDICT:")"
run_test "codex_pending_existing_trigger_no_duplicate_post" "0" \
  "$(grep_count_or_zero 'duplicate-trigger-post' "$_codex_pending_idempotent_dir/output.txt")"
run_test "codex_pending_existing_trigger_reason" "REASON=codex-github-review-pending" \
  "$(printf '%s\n' "$_codex_pending_idempotent_output" | grep "^REASON=")"
run_test "codex_pending_existing_trigger_id" "PENDING_REVIEW_TRIGGER_COMMENT_ID=901" \
  "$(printf '%s\n' "$_codex_pending_idempotent_output" | grep "^PENDING_REVIEW_TRIGGER_COMMENT_ID=")"
rm -rf "$_codex_pending_idempotent_dir"
unset _codex_pending_idempotent_dir _codex_pending_idempotent_exit _codex_pending_idempotent_output

# --- #1522: the account-not-connected refusal is unavailability, not a finding
_codex_notconn_dir="$(mktemp -d)"
cat > "$_codex_notconn_dir/gh" <<'CODEX_NOTCONN_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*) exit 0 ;;
  *"pr view"*headRefOid*) printf 'abcnotconn1234567890\n'; exit 0 ;;
  *"--method POST"*) printf '{"id":101,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*) printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*) printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*) printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":201,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"To use Codex here, [create a Codex account and connect to github](https://chatgpt.com/codex/cloud/settings/connectors)."}]\n'
    exit 0 ;;
  *) printf 'ERROR=unexpected-gh-invocation\n' >&2; exit 64 ;;
esac
CODEX_NOTCONN_GH
chmod +x "$_codex_notconn_dir/gh"
_codex_notconn_exit=0
PATH="$_codex_notconn_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_notconn_dir/output.txt" 2>&1 || _codex_notconn_exit=$?
_codex_notconn_output="$(cat "$_codex_notconn_dir/output.txt")"
run_test "codex_account_not_connected_exit_unavailable" "3" "$_codex_notconn_exit"
run_test "codex_account_not_connected_verdict" \
  "VERDICT: UNAVAILABLE — Codex GitHub account is not connected for the triggering identity" \
  "$(printf '%s\n' "$_codex_notconn_output" | grep "^VERDICT:")"
run_test "codex_account_not_connected_reason" "REASON=codex-github-account-not-connected" \
  "$(printf '%s\n' "$_codex_notconn_output" | grep "^REASON=")"
run_test "codex_account_not_connected_blocking_count" "BLOCKING_COUNT=0" \
  "$(printf '%s\n' "$_codex_notconn_output" | grep "^BLOCKING_COUNT=")"
rm -rf "$_codex_notconn_dir"
unset _codex_notconn_dir _codex_notconn_exit _codex_notconn_output

# A same-fetch mix of a non-blocking review and an account-connection refusal
# must classify as UNAVAILABLE, not as the review (CodeRabbit on PR #1586);
# a BLOCKING review still wins outright, as for usage-limit.
_codex_mixed_dir="$(mktemp -d)"
cat > "$_codex_mixed_dir/gh" <<'CODEX_MIXED_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*) exit 0 ;;
  *"pr view"*headRefOid*) printf 'abcmixed1234567890\n'; exit 0 ;;
  *"--method POST"*) printf '{"id":101,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*) printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*) printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[{"id":401,"submitted_at":"2026-01-01T00:00:02Z","state":"COMMENTED","user":{"login":"chatgpt-codex-connector[bot]"},"body":"%s"}]\n' "${MOCK_REVIEW_BODY:-No blocking issues found. Reviewed commit: \`abcmixed1234567890\`}"
    exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":201,"created_at":"2026-01-01T00:00:03Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"%s"}]\n' "${MOCK_REFUSAL_OVERRIDE:-To use Codex here, [create a Codex account and connect to github](https://chatgpt.com/codex/cloud/settings/connectors).}"
    exit 0 ;;
  *) printf 'ERROR=unexpected-gh-invocation\n' >&2; exit 64 ;;
esac
CODEX_MIXED_GH
chmod +x "$_codex_mixed_dir/gh"
_codex_mixed_exit=0
PATH="$_codex_mixed_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_mixed_dir/output.txt" 2>&1 || _codex_mixed_exit=$?
run_test "codex_mixed_fetch_refusal_wins_over_clean_review" "3" "$_codex_mixed_exit"
run_test "codex_mixed_fetch_refusal_reason" "REASON=codex-github-account-not-connected" \
  "$(grep "^REASON=" "$_codex_mixed_dir/output.txt" || true)"
_codex_mixed_blocking_exit=0
MOCK_REVIEW_BODY="Changes requested: must fix the null deref. Reviewed commit: \`abcmixed1234567890\`" \
PATH="$_codex_mixed_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_mixed_dir/blocking.txt" 2>&1 || _codex_mixed_blocking_exit=$?
# Parity, not an independent guarantee: with a blocking review in the SAME
# fetch, the pre-existing usage-limit path also returns UNAVAILABLE (measured
# on develop: usage-limit → 3, environment-error → 2). The not-connected block
# must behave identically to usage-limit rather than inventing a stricter
# contract; the shared blocking-evidence gap is tracked separately.
_codex_mixed_usage_exit=0
MOCK_REVIEW_BODY="Changes requested: must fix the null deref. Reviewed commit: \`abcmixed1234567890\`" \
MOCK_REFUSAL_OVERRIDE="You have reached your Codex usage limits for code reviews." \
PATH="$_codex_mixed_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_mixed_dir/usage.txt" 2>&1 || _codex_mixed_usage_exit=$?
run_test "codex_mixed_fetch_not_connected_matches_usage_limit" \
  "$_codex_mixed_usage_exit" "$_codex_mixed_blocking_exit"
rm -rf "$_codex_mixed_dir"
unset _codex_mixed_dir _codex_mixed_exit _codex_mixed_blocking_exit _codex_mixed_usage_exit

# --- #1526: a trigger already answered with a refusal must be re-triggered,
# so a restored quota/connection can review the same commit. Without the fix
# the guard skipped the post and re-read the stale refusal forever.
_codex_retrig_dir="$(mktemp -d)"
cat > "$_codex_retrig_dir/gh" <<'CODEX_RETRIG_GH'
#!/usr/bin/env bash
log="$MOCK_POST_LOG"
case "$*" in
  *"auth status"*) exit 0 ;;
  *"pr view"*headRefOid*) printf 'abcretrig1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf 'POST\n' >> "$log"
    printf '{"id":301,"created_at":"2026-01-01T00:10:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*) printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*) printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*) printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":200,"created_at":"2026-01-01T00:00:00Z","user":{"login":"runner"},"body":"Review triggered by workflow runner for abcretrig1234567890"},{"id":201,"created_at":"2026-01-01T00:00:05Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"You have reached your Codex usage limits for code reviews."}]\n'
    exit 0 ;;
  *) printf 'ERROR=unexpected-gh-invocation\n' >&2; exit 64 ;;
esac
CODEX_RETRIG_GH
chmod +x "$_codex_retrig_dir/gh"
: > "$_codex_retrig_dir/posts.log"
MOCK_POST_LOG="$_codex_retrig_dir/posts.log" PATH="$_codex_retrig_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_retrig_dir/output.txt" 2>&1 || true
_codex_retrig_output="$(cat "$_codex_retrig_dir/output.txt")"
run_test "codex_refused_trigger_is_retriggered" "yes" \
  "$(if grep -Fq "re-triggering so a restored quota/connection can review this commit" <<<"$_codex_retrig_output"; then printf yes; else printf no; fi)"
run_test "codex_refused_trigger_posts_new_comment" "yes" \
  "$(if grep -Fq POST "$_codex_retrig_dir/posts.log"; then printf yes; else printf no; fi)"
run_test "codex_refused_trigger_does_not_skip_as_duplicate" "no" \
  "$(if grep -Fq "skipping duplicate post" <<<"$_codex_retrig_output"; then printf yes; else printf no; fi)"
rm -rf "$_codex_retrig_dir"
unset _codex_retrig_dir _codex_retrig_output

# The environment-error refusal is the third unavailability form and must be
# recovered from identically (pr-agent on PR #1586).
_codex_envretrig_dir="$(mktemp -d)"
cat > "$_codex_envretrig_dir/gh" <<'CODEX_ENVRETRIG_GH'
#!/usr/bin/env bash
log="$MOCK_POST_LOG"
case "$*" in
  *"auth status"*) exit 0 ;;
  *"pr view"*headRefOid*) printf 'abcenvretrig123456\n'; exit 0 ;;
  *"--method POST"*)
    printf 'POST\n' >> "$log"
    printf '{"id":301,"created_at":"2026-01-01T00:10:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*) printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*) printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*) printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":200,"created_at":"2026-01-01T00:00:00Z","user":{"login":"runner"},"body":"Review triggered by workflow runner for abcenvretrig123456"},{"id":201,"created_at":"2026-01-01T00:00:05Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"To use Codex here, create an environment for this repo."}]\n'
    exit 0 ;;
  *) printf 'ERROR=unexpected-gh-invocation\n' >&2; exit 64 ;;
esac
CODEX_ENVRETRIG_GH
chmod +x "$_codex_envretrig_dir/gh"
: > "$_codex_envretrig_dir/posts.log"
MOCK_POST_LOG="$_codex_envretrig_dir/posts.log" PATH="$_codex_envretrig_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_envretrig_dir/output.txt" 2>&1 || true
_codex_envretrig_output="$(cat "$_codex_envretrig_dir/output.txt")"
run_test "codex_env_error_trigger_is_retriggered" "yes" \
  "$(if grep -Fq "re-triggering so a restored quota/connection can review this commit" <<<"$_codex_envretrig_output"; then printf yes; else printf no; fi)"
run_test "codex_env_error_trigger_posts_new_comment" "yes" \
  "$(if grep -Fq POST "$_codex_envretrig_dir/posts.log"; then printf yes; else printf no; fi)"
rm -rf "$_codex_envretrig_dir"
unset _codex_envretrig_dir _codex_envretrig_output

# --- #1522 (async-arrival path): the not-connected refusal must still be
# classified as UNAVAILABLE when it only arrives during the post-poll-window
# "async grace period" check, not just during the main poll loop. This
# exercises a SEPARATE duplicate three-path classification chain in the
# script (ASYNC_BOT_RESPONSE) that has its own usage-limit/environment-error
# branches; without the account-not-connected branch mirrored there too, a
# refusal seen only during the grace poll fell through to a generic
# TIMED_OUT instead of the specific UNAVAILABLE/REASON verdict.
_codex_notconn_async_dir="$(mktemp -d)"
: > "$_codex_notconn_async_dir/calls.log"
cat > "$_codex_notconn_async_dir/gh" <<'CODEX_NOTCONN_ASYNC_GH'
#!/usr/bin/env bash
log="$MOCK_CALL_LOG"
case "$*" in
  *"auth status"*) exit 0 ;;
  *"pr view"*headRefOid*) printf 'abcnotconnasync1234\n'; exit 0 ;;
  *"--method POST"*) printf '{"id":901,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*) printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*) printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*) printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    n=0
    [ -f "$log" ] && n=$(cat "$log")
    n=$((n + 1))
    echo "$n" > "$log"
    # First two reads (idempotency check + the single main-loop poll) see no
    # reply yet; only the async-grace-period read sees the refusal, so the
    # main poll loop's own (already-present) classification cannot be what
    # catches this case.
    if [ "$n" -le 2 ]; then
      printf '[]\n'
    else
      printf '[{"id":902,"created_at":"2026-01-01T00:00:05Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"To use Codex here, [create a Codex account and connect to github](https://chatgpt.com/codex/cloud/settings/connectors)."}]\n'
    fi
    exit 0 ;;
  *) printf 'ERROR=unexpected-gh-invocation\n' >&2; exit 64 ;;
esac
CODEX_NOTCONN_ASYNC_GH
chmod +x "$_codex_notconn_async_dir/gh"
_codex_notconn_async_exit=0
MOCK_CALL_LOG="$_codex_notconn_async_dir/calls.log" PATH="$_codex_notconn_async_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_notconn_async_dir/output.txt" 2>&1 || _codex_notconn_async_exit=$?
_codex_notconn_async_output="$(cat "$_codex_notconn_async_dir/output.txt")"
run_test "codex_account_not_connected_async_exit_unavailable" "3" "$_codex_notconn_async_exit"
run_test "codex_account_not_connected_async_verdict" \
  "VERDICT: UNAVAILABLE — Codex GitHub account is not connected for the triggering identity" \
  "$(printf '%s\n' "$_codex_notconn_async_output" | grep "^VERDICT:")"
run_test "codex_account_not_connected_async_reason" "REASON=codex-github-account-not-connected" \
  "$(printf '%s\n' "$_codex_notconn_async_output" | grep "^REASON=")"
rm -rf "$_codex_notconn_async_dir"
unset _codex_notconn_async_dir _codex_notconn_async_exit _codex_notconn_async_output

_codex_usage_comment_mock_dir="$(mktemp -d)"
cat > "$_codex_usage_comment_mock_dir/gh" <<'CODEX_USAGE_COMMENT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'abcusage1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":101,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":201,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"You have reached your Codex usage limits for code reviews."}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_USAGE_COMMENT_GH
chmod +x "$_codex_usage_comment_mock_dir/gh"

_codex_usage_comment_output=""
_codex_usage_comment_exit=0
PATH="$_codex_usage_comment_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_usage_comment_mock_dir/output.txt" 2>&1 || _codex_usage_comment_exit=$?
_codex_usage_comment_output="$(cat "$_codex_usage_comment_mock_dir/output.txt")"
run_test "codex_usage_limit_comment_exit_unavailable" "3" "$_codex_usage_comment_exit"
run_test "codex_usage_limit_comment_verdict" \
  "VERDICT: UNAVAILABLE — Codex GitHub review usage limit reached" \
  "$(printf '%s\n' "$_codex_usage_comment_output" | grep "^VERDICT:")"
run_test "codex_usage_limit_comment_reason" "REASON=codex-github-usage-limit" \
  "$(printf '%s\n' "$_codex_usage_comment_output" | grep "^REASON=")"
run_test "codex_usage_limit_comment_comment_count" "COMMENT_COUNT=0" \
  "$(printf '%s\n' "$_codex_usage_comment_output" | grep "^COMMENT_COUNT=")"
run_test "codex_usage_limit_comment_blocking_count" "BLOCKING_COUNT=0" \
  "$(printf '%s\n' "$_codex_usage_comment_output" | grep "^BLOCKING_COUNT=")"
run_test "codex_usage_limit_comment_suggestion_count" "SUGGESTION_COUNT=0" \
  "$(printf '%s\n' "$_codex_usage_comment_output" | grep "^SUGGESTION_COUNT=")"
rm -rf "$_codex_usage_comment_mock_dir"
unset _codex_usage_comment_mock_dir _codex_usage_comment_output _codex_usage_comment_exit

_codex_usage_review_mock_dir="$(mktemp -d)"
cat > "$_codex_usage_review_mock_dir/gh" <<'CODEX_USAGE_REVIEW_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'abcreview1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":102,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[{"submitted_at":"2026-01-01T00:00:01Z","commit_id":"abcreview1234567890","user":{"login":"chatgpt-codex-connector[bot]"},"body":"Codex review capacity exhausted. Please rerun after quota reset."}]\n'
    exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_USAGE_REVIEW_GH
chmod +x "$_codex_usage_review_mock_dir/gh"

_codex_usage_review_output=""
_codex_usage_review_exit=0
PATH="$_codex_usage_review_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_usage_review_mock_dir/output.txt" 2>&1 || _codex_usage_review_exit=$?
_codex_usage_review_output="$(cat "$_codex_usage_review_mock_dir/output.txt")"
run_test "codex_usage_limit_review_exit_unavailable" "3" "$_codex_usage_review_exit"
run_test "codex_usage_limit_review_verdict" \
  "VERDICT: UNAVAILABLE — Codex GitHub review usage limit reached" \
  "$(printf '%s\n' "$_codex_usage_review_output" | grep "^VERDICT:")"
run_test "codex_usage_limit_review_reason" "REASON=codex-github-usage-limit" \
  "$(printf '%s\n' "$_codex_usage_review_output" | grep "^REASON=")"
run_test "codex_usage_limit_review_comment_count" "COMMENT_COUNT=0" \
  "$(printf '%s\n' "$_codex_usage_review_output" | grep "^COMMENT_COUNT=")"
run_test "codex_usage_limit_review_blocking_count" "BLOCKING_COUNT=0" \
  "$(printf '%s\n' "$_codex_usage_review_output" | grep "^BLOCKING_COUNT=")"
run_test "codex_usage_limit_review_suggestion_count" "SUGGESTION_COUNT=0" \
  "$(printf '%s\n' "$_codex_usage_review_output" | grep "^SUGGESTION_COUNT=")"
rm -rf "$_codex_usage_review_mock_dir"
unset _codex_usage_review_mock_dir _codex_usage_review_output _codex_usage_review_exit

_codex_existing_clean_mock_dir="$(mktemp -d)"
cat > "$_codex_existing_clean_mock_dir/gh" <<'CODEX_EXISTING_CLEAN_GH'
#!/usr/bin/env bash
log="$MOCK_POST_LOG"
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'abcef1234567890abcde\n'; exit 0 ;;
  *"api graphql"*)
    printf '{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[{"isResolved":true,"isOutdated":false,"comments":{"nodes":[{"author":{"login":"chatgpt-codex-connector"}}]}}]}}}}}\n'
    exit 0 ;;
  *"--method POST"*)
    printf 'POST\n' >> "$log"
    printf '{"id":102,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    jq -nc '[{submitted_at:"2026-01-01T00:00:01Z",commit_id:"abcef1234567890abcde",state:"APPROVED",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'\''t find any major issues. Swish! **Reviewed commit:** `abcef1234567890abcde` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> [Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment \"@codex review\". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\". </details>")}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_EXISTING_CLEAN_GH
chmod +x "$_codex_existing_clean_mock_dir/gh"
: > "$_codex_existing_clean_mock_dir/posts.log"
_codex_existing_clean_output=""
_codex_existing_clean_exit=0
MOCK_POST_LOG="$_codex_existing_clean_mock_dir/posts.log" PATH="$_codex_existing_clean_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --pre-trigger-wait 08 --max-retriggers 0 \
  >"$_codex_existing_clean_mock_dir/output.txt" 2>&1 || _codex_existing_clean_exit=$?
_codex_existing_clean_output="$(cat "$_codex_existing_clean_mock_dir/output.txt")"
run_test "codex_existing_current_head_review_exit_clean" "0" "$_codex_existing_clean_exit"
run_test "codex_existing_current_head_review_approved" "VERDICT: APPROVED" \
  "$(printf '%s\n' "$_codex_existing_clean_output" | grep "^VERDICT:")"
run_test "codex_existing_current_head_review_skips_trigger" "0" \
  "$(wc -l < "$_codex_existing_clean_mock_dir/posts.log" | tr -d ' ')"
run_test "codex_existing_current_head_review_logs_no_trigger" "yes" \
  "$(if grep -Fq "existing current-head Codex evidence detected; no trigger comment will be posted" "$_codex_existing_clean_mock_dir/output.txt"; then printf yes; else printf no; fi)"
run_test "codex_pre_trigger_wait_normalizes_leading_zero" "INFO: Pre-trigger wait: 8s" \
  "$(grep "^INFO: Pre-trigger wait:" "$_codex_existing_clean_mock_dir/output.txt")"
rm -rf "$_codex_existing_clean_mock_dir"
unset _codex_existing_clean_mock_dir _codex_existing_clean_output _codex_existing_clean_exit

_codex_existing_fetch_failure_mock_dir="$(mktemp -d)"
cat > "$_codex_existing_fetch_failure_mock_dir/gh" <<'CODEX_EXISTING_FETCH_FAILURE_GH'
#!/usr/bin/env bash
log="$MOCK_POST_LOG"
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'abcfetchfail1234567890\n'; exit 0 ;;
  *"api graphql"*)
    printf '{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[]}}}}}\n'
    exit 0 ;;
  *"--method POST"*)
    printf 'POST\n' >> "$log"
    printf '{"id":105,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf 'api unavailable\n' >&2
    exit 1 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_EXISTING_FETCH_FAILURE_GH
chmod +x "$_codex_existing_fetch_failure_mock_dir/gh"
: > "$_codex_existing_fetch_failure_mock_dir/posts.log"
_codex_existing_fetch_failure_output=""
_codex_existing_fetch_failure_exit=0
MOCK_POST_LOG="$_codex_existing_fetch_failure_mock_dir/posts.log" PATH="$_codex_existing_fetch_failure_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --pre-trigger-wait 1 --max-retriggers 0 \
  >"$_codex_existing_fetch_failure_mock_dir/output.txt" 2>&1 || _codex_existing_fetch_failure_exit=$?
_codex_existing_fetch_failure_output="$(cat "$_codex_existing_fetch_failure_mock_dir/output.txt")"
run_test "codex_existing_fetch_failure_exit_unavailable" "2" "$_codex_existing_fetch_failure_exit"
run_test "codex_existing_fetch_failure_verdict" \
  "VERDICT: TIMED_OUT — could not fetch existing Codex evidence before trigger (treated as unavailable)" \
  "$(printf '%s\n' "$_codex_existing_fetch_failure_output" | grep "^VERDICT:")"
run_test "codex_existing_fetch_failure_skips_trigger" "0" \
  "$(wc -l < "$_codex_existing_fetch_failure_mock_dir/posts.log" | tr -d ' ')"
rm -rf "$_codex_existing_fetch_failure_mock_dir"
unset _codex_existing_fetch_failure_mock_dir _codex_existing_fetch_failure_output _codex_existing_fetch_failure_exit

_codex_stale_existing_mock_dir="$(mktemp -d)"
cat > "$_codex_stale_existing_mock_dir/gh" <<'CODEX_STALE_EXISTING_GH'
#!/usr/bin/env bash
log="$MOCK_POST_LOG"
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'abcnewhead1234567890\n'; exit 0 ;;
  *"api graphql"*)
    printf '{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[]}}}}}\n'
    exit 0 ;;
  *"--method POST"*)
    printf 'POST\n' >> "$log"
    printf '{"id":104,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    jq -nc '[{submitted_at:"2026-01-01T00:00:01Z",commit_id:"abcoldhead1234567890",state:"APPROVED",user:{login:"chatgpt-codex-connector[bot]"},body:"Codex Review: Did not cover the current head."}]'
    exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    jq -nc '[{id:204,created_at:"2026-01-01T00:00:01Z",user:{login:"chatgpt-codex-connector[bot]"},body:"Codex Review: Didn'\''t find any major issues. Swish! **Reviewed commit:** `abcoldhead1234567890`"}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_STALE_EXISTING_GH
chmod +x "$_codex_stale_existing_mock_dir/gh"
: > "$_codex_stale_existing_mock_dir/posts.log"
_codex_stale_existing_exit=0
MOCK_POST_LOG="$_codex_stale_existing_mock_dir/posts.log" PATH="$_codex_stale_existing_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --pre-trigger-wait 1 --max-retriggers 0 \
  >"$_codex_stale_existing_mock_dir/output.txt" 2>&1 || _codex_stale_existing_exit=$?
run_test "codex_stale_existing_evidence_posts_trigger" "1" \
  "$(wc -l < "$_codex_stale_existing_mock_dir/posts.log" | tr -d ' ')"
run_test "codex_stale_existing_evidence_no_fast_path" "yes" \
  "$(if grep -Fq "no existing current-head Codex evidence found before trigger window elapsed" "$_codex_stale_existing_mock_dir/output.txt"; then printf yes; else printf no; fi)"
rm -rf "$_codex_stale_existing_mock_dir"
unset _codex_stale_existing_mock_dir _codex_stale_existing_exit

_codex_prefix_mismatch_mock_dir="$(mktemp -d)"
cat > "$_codex_prefix_mismatch_mock_dir/gh" <<'CODEX_PREFIX_MISMATCH_GH'
#!/usr/bin/env bash
log="$MOCK_POST_LOG"
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'abcdefab1234567890abcdefab1234567890abcd\n'; exit 0 ;;
  *"api graphql"*)
    printf '{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[]}}}}}\n'
    exit 0 ;;
  *"--method POST"*)
    printf 'POST\n' >> "$log"
    printf '{"id":106,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    jq -nc '[{submitted_at:"2026-01-01T00:00:01Z",commit_id:"abcdefab1234567890abcdefab1234567890abce",state:"APPROVED",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'\''t find any major issues. Swish! **Reviewed commit:** `abcdefab1234` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> [Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment \"@codex review\". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\". </details>")}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_PREFIX_MISMATCH_GH
chmod +x "$_codex_prefix_mismatch_mock_dir/gh"
: > "$_codex_prefix_mismatch_mock_dir/posts.log"
_codex_prefix_mismatch_exit=0
MOCK_POST_LOG="$_codex_prefix_mismatch_mock_dir/posts.log" PATH="$_codex_prefix_mismatch_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --pre-trigger-wait 1 --max-retriggers 0 \
  >"$_codex_prefix_mismatch_mock_dir/output.txt" 2>&1 || _codex_prefix_mismatch_exit=$?
run_test "codex_prefix_mismatch_review_posts_trigger" "1" \
  "$(wc -l < "$_codex_prefix_mismatch_mock_dir/posts.log" | tr -d ' ')"
run_test "codex_prefix_mismatch_review_no_fast_path" "yes" \
  "$(if grep -Fq "no existing current-head Codex evidence found before trigger window elapsed" "$_codex_prefix_mismatch_mock_dir/output.txt"; then printf yes; else printf no; fi)"
rm -rf "$_codex_prefix_mismatch_mock_dir"
unset _codex_prefix_mismatch_mock_dir _codex_prefix_mismatch_exit

_codex_provisional_reply_mock_dir="$(mktemp -d)"
cat > "$_codex_provisional_reply_mock_dir/gh" <<'CODEX_PROVISIONAL_REPLY_GH'
#!/usr/bin/env bash
log="$MOCK_POST_LOG"
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n'; exit 0 ;;
  *"api graphql"*)
    printf '{"data":{"repository":{"pullRequest":{"headRef":{"target":{"committedDate":"2026-01-01T00:00:00Z"}},"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"isResolved":false,"isOutdated":false,"firstComment":{"nodes":[{"author":{"login":"chatgpt-codex-connector"}}]},"lastComment":{"nodes":[{"author":{"login":"lhpaul"},"createdAt":"2026-01-01T00:00:01Z"}]}}]}}}}}\n'
    exit 0 ;;
  *"--method POST"*)
    printf 'POST\n' >> "$log"
    printf '{"id":107,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    jq -nc '[{submitted_at:"2026-01-01T00:00:01Z",commit_id:"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",state:"APPROVED",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'\''t find any major issues. Swish! **Reviewed commit:** `aaaaaaaaaaaa` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> [Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment \"@codex review\". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\". </details>")}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_PROVISIONAL_REPLY_GH
chmod +x "$_codex_provisional_reply_mock_dir/gh"
: > "$_codex_provisional_reply_mock_dir/posts.log"
_codex_provisional_reply_exit=0
MOCK_POST_LOG="$_codex_provisional_reply_mock_dir/posts.log" PATH="$_codex_provisional_reply_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --pre-trigger-wait 1 --max-retriggers 0 \
  >"$_codex_provisional_reply_mock_dir/output.txt" 2>&1 || _codex_provisional_reply_exit=$?
run_test "codex_provisional_reply_allows_existing_review" "0" "$_codex_provisional_reply_exit"
run_test "codex_provisional_reply_skips_trigger" "0" \
  "$(wc -l < "$_codex_provisional_reply_mock_dir/posts.log" | tr -d ' ')"
rm -rf "$_codex_provisional_reply_mock_dir"
unset _codex_provisional_reply_mock_dir _codex_provisional_reply_exit

_codex_provisional_missing_author_mock_dir="$(mktemp -d)"
cat > "$_codex_provisional_missing_author_mock_dir/gh" <<'CODEX_PROVISIONAL_MISSING_AUTHOR_GH'
#!/usr/bin/env bash
log="$MOCK_POST_LOG"
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf '1212121212121212121212121212121212121212\n'; exit 0 ;;
  *"api graphql"*)
    printf '{"data":{"repository":{"pullRequest":{"headRef":{"target":{"committedDate":"2026-01-01T00:00:00Z"}},"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"isResolved":false,"isOutdated":false,"firstComment":{"nodes":[{"author":{"login":"chatgpt-codex-connector"},"body":"Blocking issue"}]},"lastComment":{"nodes":[{"author":null,"createdAt":"2026-01-01T00:00:01Z"}]}}]}}}}}\n'
    exit 0 ;;
  *"--method POST"*)
    printf 'POST\n' >> "$log"
    printf '{"id":115,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_PROVISIONAL_MISSING_AUTHOR_GH
chmod +x "$_codex_provisional_missing_author_mock_dir/gh"
: > "$_codex_provisional_missing_author_mock_dir/posts.log"
_codex_provisional_missing_author_output=""
_codex_provisional_missing_author_exit=0
MOCK_POST_LOG="$_codex_provisional_missing_author_mock_dir/posts.log" PATH="$_codex_provisional_missing_author_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --pre-trigger-wait 1 --max-retriggers 0 \
  >"$_codex_provisional_missing_author_mock_dir/output.txt" 2>&1 || _codex_provisional_missing_author_exit=$?
_codex_provisional_missing_author_output="$(cat "$_codex_provisional_missing_author_mock_dir/output.txt")"
run_test "codex_provisional_missing_author_exit_needs_revision" "1" "$_codex_provisional_missing_author_exit"
run_test "codex_provisional_missing_author_verdict" "VERDICT: NEEDS_REVISION" \
  "$(printf '%s\n' "$_codex_provisional_missing_author_output" | grep "^VERDICT:")"
run_test "codex_provisional_missing_author_skips_trigger" "0" \
  "$(wc -l < "$_codex_provisional_missing_author_mock_dir/posts.log" | tr -d ' ')"
rm -rf "$_codex_provisional_missing_author_mock_dir"
unset _codex_provisional_missing_author_mock_dir _codex_provisional_missing_author_output _codex_provisional_missing_author_exit

_codex_provisional_changes_requested_mock_dir="$(mktemp -d)"
cat > "$_codex_provisional_changes_requested_mock_dir/gh" <<'CODEX_PROVISIONAL_CHANGES_REQUESTED_GH'
#!/usr/bin/env bash
log="$MOCK_POST_LOG"
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'cccccccccccccccccccccccccccccccccccccccc\n'; exit 0 ;;
  *"api graphql"*)
    printf '{"data":{"repository":{"pullRequest":{"headRef":{"target":{"committedDate":"2026-01-01T00:00:00Z"}},"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"isResolved":false,"isOutdated":false,"firstComment":{"nodes":[{"author":{"login":"chatgpt-codex-connector"}}]},"lastComment":{"nodes":[{"author":{"login":"lhpaul"},"createdAt":"2026-01-01T00:00:01Z"}]}}]}}}}}\n'
    exit 0 ;;
  *"--method POST"*)
    printf 'POST\n' >> "$log"
    printf '{"id":109,"created_at":"2026-01-01T00:00:10Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    jq -nc '[{submitted_at:"2026-01-01T00:00:01Z",commit_id:"cccccccccccccccccccccccccccccccccccccccc",state:"COMMENTED",user:{login:"chatgpt-codex-connector[bot]"},body:"### 💡 Codex Review\n\nHere are some automated review suggestions for this pull request.\n\n**Reviewed commit:** `cccccccccccc`"}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_PROVISIONAL_CHANGES_REQUESTED_GH
chmod +x "$_codex_provisional_changes_requested_mock_dir/gh"
: > "$_codex_provisional_changes_requested_mock_dir/posts.log"
_codex_provisional_changes_requested_exit=0
MOCK_POST_LOG="$_codex_provisional_changes_requested_mock_dir/posts.log" PATH="$_codex_provisional_changes_requested_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --pre-trigger-wait 1 --max-retriggers 0 \
  >"$_codex_provisional_changes_requested_mock_dir/output.txt" 2>&1 || _codex_provisional_changes_requested_exit=$?
run_test "codex_provisional_changes_requested_posts_trigger" "1" \
  "$(wc -l < "$_codex_provisional_changes_requested_mock_dir/posts.log" | tr -d ' ')"
run_test "codex_provisional_changes_requested_no_fast_path" "yes" \
  "$(if grep -Fq "inline-review summary has only cleared thread findings; a fresh trigger is needed unless a newer one is outstanding" "$_codex_provisional_changes_requested_mock_dir/output.txt"; then printf yes; else printf no; fi)"
rm -rf "$_codex_provisional_changes_requested_mock_dir"
unset _codex_provisional_changes_requested_mock_dir _codex_provisional_changes_requested_exit

_codex_resolved_changes_requested_mock_dir="$(mktemp -d)"
cat > "$_codex_resolved_changes_requested_mock_dir/gh" <<'CODEX_RESOLVED_CHANGES_REQUESTED_GH'
#!/usr/bin/env bash
log="$MOCK_POST_LOG"
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'ffffffffffffffffffffffffffffffffffffffff\n'; exit 0 ;;
  *"api graphql"*)
    printf '{"data":{"repository":{"pullRequest":{"headRef":{"target":{"committedDate":"2026-01-01T00:00:00Z"}},"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"isResolved":true,"isOutdated":false,"firstComment":{"nodes":[{"author":{"login":"chatgpt-codex-connector"}}]},"lastComment":{"nodes":[{"author":{"login":"lhpaul"},"createdAt":"2026-01-01T00:00:01Z"}]}}]}}}}}\n'
    exit 0 ;;
  *"--method POST"*)
    printf 'POST\n' >> "$log"
    printf '{"id":111,"created_at":"2026-01-01T00:00:10Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    jq -nc '[{submitted_at:"2026-01-01T00:00:01Z",commit_id:"ffffffffffffffffffffffffffffffffffffffff",state:"COMMENTED",user:{login:"chatgpt-codex-connector[bot]"},body:"### 💡 Codex Review\n\nHere are some automated review suggestions for this pull request.\n\n**Reviewed commit:** `ffffffffffff`"}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_RESOLVED_CHANGES_REQUESTED_GH
chmod +x "$_codex_resolved_changes_requested_mock_dir/gh"
: > "$_codex_resolved_changes_requested_mock_dir/posts.log"
_codex_resolved_changes_requested_exit=0
MOCK_POST_LOG="$_codex_resolved_changes_requested_mock_dir/posts.log" PATH="$_codex_resolved_changes_requested_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --pre-trigger-wait 1 --max-retriggers 0 \
  >"$_codex_resolved_changes_requested_mock_dir/output.txt" 2>&1 || _codex_resolved_changes_requested_exit=$?
run_test "codex_resolved_changes_requested_posts_trigger" "1" \
  "$(wc -l < "$_codex_resolved_changes_requested_mock_dir/posts.log" | tr -d ' ')"
run_test "codex_resolved_changes_requested_no_fast_path" "yes" \
  "$(if grep -Fq "inline-review summary has only cleared thread findings; a fresh trigger is needed unless a newer one is outstanding" "$_codex_resolved_changes_requested_mock_dir/output.txt"; then printf yes; else printf no; fi)"
rm -rf "$_codex_resolved_changes_requested_mock_dir"
unset _codex_resolved_changes_requested_mock_dir _codex_resolved_changes_requested_exit

_codex_addressed_changes_requested_mock_dir="$(mktemp -d)"
cat > "$_codex_addressed_changes_requested_mock_dir/gh" <<'CODEX_ADDRESSED_CHANGES_REQUESTED_GH'
#!/usr/bin/env bash
log="$MOCK_POST_LOG"
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf '9999999999999999999999999999999999999999\n'; exit 0 ;;
  *"api graphql"*)
    printf '{"data":{"repository":{"pullRequest":{"headRef":{"target":{"committedDate":"2026-01-01T00:00:00Z"}},"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"isResolved":false,"isOutdated":false,"firstComment":{"nodes":[{"author":{"login":"chatgpt-codex-connector"},"body":"✅ Addressed in latest commit"}]},"lastComment":{"nodes":[{"author":{"login":"chatgpt-codex-connector"},"createdAt":"2026-01-01T00:00:01Z"}]}}]}}}}}\n'
    exit 0 ;;
  *"--method POST"*)
    printf 'POST\n' >> "$log"
    printf '{"id":112,"created_at":"2026-01-01T00:00:10Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    jq -nc '[{id:212,created_at:"2026-01-01T00:00:00Z",user:{login:"lhpaul"},body:"@codex review (review triggered by workflow runner, commit: 999999999999)"}]'
    exit 0 ;;
  *"pulls/"*"/reviews"*)
    jq -nc '[{submitted_at:"2026-01-01T00:00:01Z",commit_id:"9999999999999999999999999999999999999999",state:"COMMENTED",user:{login:"chatgpt-codex-connector[bot]"},body:"### 💡 Codex Review\n\nHere are some automated review suggestions for this pull request.\n\n**Reviewed commit:** `999999999999`"}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_ADDRESSED_CHANGES_REQUESTED_GH
chmod +x "$_codex_addressed_changes_requested_mock_dir/gh"
: > "$_codex_addressed_changes_requested_mock_dir/posts.log"
_codex_addressed_changes_requested_exit=0
MOCK_POST_LOG="$_codex_addressed_changes_requested_mock_dir/posts.log" PATH="$_codex_addressed_changes_requested_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --pre-trigger-wait 1 --max-retriggers 0 \
  >"$_codex_addressed_changes_requested_mock_dir/output.txt" 2>&1 || _codex_addressed_changes_requested_exit=$?
run_test "codex_addressed_changes_requested_posts_trigger" "1" \
  "$(wc -l < "$_codex_addressed_changes_requested_mock_dir/posts.log" | tr -d ' ')"
run_test "codex_addressed_changes_requested_no_fast_path" "yes" \
  "$(if grep -Fq "inline-review summary has only cleared thread findings; a fresh trigger is needed unless a newer one is outstanding" "$_codex_addressed_changes_requested_mock_dir/output.txt"; then printf yes; else printf no; fi)"
rm -rf "$_codex_addressed_changes_requested_mock_dir"
unset _codex_addressed_changes_requested_mock_dir _codex_addressed_changes_requested_exit

# #1789 T4.8 — regression: an older cleared Codex review plus a newer
# unanswered trigger (plan D11 Codex row, V36). The cleared review was
# submitted at 00:00:01; a runner trigger for the head created strictly later
# (00:00:05) is the outstanding replacement: nothing is posted, the D11 INFO
# line is logged, and the companion polls with that trigger's time (and
# reports it as REVIEW_REQUESTED_AT, plan D12). A trigger created at the same
# second as the review was answered by it, so exactly one fresh trigger is
# posted, as today.
_codex_t48_dir="$(mktemp -d)"
cat > "$_codex_t48_dir/gh" <<'CODEX_T48_GH'
#!/usr/bin/env bash
log="$MOCK_POST_LOG"
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf '9999999999999999999999999999999999999999\n'; exit 0 ;;
  *"api graphql"*)
    printf '{"data":{"repository":{"pullRequest":{"headRef":{"target":{"committedDate":"2026-01-01T00:00:00Z"}},"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"isResolved":false,"isOutdated":false,"firstComment":{"nodes":[{"author":{"login":"chatgpt-codex-connector"},"body":"✅ Addressed in latest commit"}]},"lastComment":{"nodes":[{"author":{"login":"chatgpt-codex-connector"},"createdAt":"2026-01-01T00:00:01Z"}]}}]}}}}}\n'
    exit 0 ;;
  *"--method POST"*)
    printf 'POST\n' >> "$log"
    printf '{"id":412,"created_at":"2026-01-01T00:00:10Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    jq -nc --arg t "$MOCK_T48_TRIGGER_AT" '[{id:312,created_at:$t,user:{login:"lhpaul"},body:"@codex review (review triggered by workflow runner, commit: 999999999999)"}]'
    exit 0 ;;
  *"pulls/"*"/reviews"*)
    jq -nc '[{submitted_at:"2026-01-01T00:00:01Z",commit_id:"9999999999999999999999999999999999999999",state:"COMMENTED",user:{login:"chatgpt-codex-connector[bot]"},body:"### 💡 Codex Review\n\nHere are some automated review suggestions for this pull request.\n\n**Reviewed commit:** `999999999999`"}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_T48_GH
chmod +x "$_codex_t48_dir/gh"
_codex_t48_run() {
  : > "$_codex_t48_dir/posts.log"
  _codex_t48_exit=0
  MOCK_T48_TRIGGER_AT="$1" MOCK_POST_LOG="$_codex_t48_dir/posts.log" PATH="$_codex_t48_dir:$PATH" \
    "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
    42 owner repo --poll-interval 1 --max-wait 1 --pre-trigger-wait 1 --max-retriggers 0 \
    >"$_codex_t48_dir/output.txt" 2>&1 || _codex_t48_exit=$?
}
_codex_t48_run "2026-01-01T00:00:05Z"
run_test "1789_T4.8_newer_trigger_posts_nothing" "0" \
  "$(wc -l < "$_codex_t48_dir/posts.log" | tr -d ' ')"
run_test "1789_T4.8_newer_trigger_logs_outstanding" "1" \
  "$(grep -Fc "INFO: trigger for commit 999999999999 posted after the cleared Codex review is still outstanding — not posting a duplicate" "$_codex_t48_dir/output.txt" || true)"
run_test "1789_T4.8_newer_trigger_polls_with_its_time" "1" \
  "$(grep -Fc "(trigger time: 2026-01-01T00:00:05Z)" "$_codex_t48_dir/output.txt" || true)"
run_test "1789_T4.8_newer_trigger_pending_exit" "4" "$_codex_t48_exit"
run_test "1789_T4.8_newer_trigger_requested_at" "REVIEW_REQUESTED_AT=2026-01-01T00:00:05Z" \
  "$(grep '^REVIEW_REQUESTED_AT=' "$_codex_t48_dir/output.txt" | sort -u)"
_codex_t48_run "2026-01-01T00:00:01Z"
run_test "1789_T4.8_same_second_trigger_posts_once" "1" \
  "$(wc -l < "$_codex_t48_dir/posts.log" | tr -d ' ')"
run_test "1789_T4.8_same_second_trigger_requested_at_is_new_post" "REVIEW_REQUESTED_AT=2026-01-01T00:00:10Z" \
  "$(grep '^REVIEW_REQUESTED_AT=' "$_codex_t48_dir/output.txt" | sort -u)"
rm -rf "$_codex_t48_dir"
unset _codex_t48_dir _codex_t48_exit
unset -f _codex_t48_run

_codex_cleared_thread_top_level_blocker_mock_dir="$(mktemp -d)"
cat > "$_codex_cleared_thread_top_level_blocker_mock_dir/gh" <<'CODEX_CLEARED_THREAD_TOP_LEVEL_BLOCKER_GH'
#!/usr/bin/env bash
log="$MOCK_POST_LOG"
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf '8888888888888888888888888888888888888888\n'; exit 0 ;;
  *"api graphql"*)
    printf '{"data":{"repository":{"pullRequest":{"headRef":{"target":{"committedDate":"2026-01-01T00:00:00Z"}},"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"isResolved":true,"isOutdated":false,"firstComment":{"nodes":[{"author":{"login":"chatgpt-codex-connector"},"body":"Resolved inline finding"}]},"lastComment":{"nodes":[{"author":{"login":"lhpaul"},"createdAt":"2026-01-01T00:00:01Z"}]}}]}}}}}\n'
    exit 0 ;;
  *"--method POST"*)
    printf 'POST\n' >> "$log"
    printf '{"id":113,"created_at":"2026-01-01T00:00:10Z"}\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    jq -nc '[{submitted_at:"2026-01-01T00:00:01Z",commit_id:"8888888888888888888888888888888888888888",state:"COMMENTED",user:{login:"chatgpt-codex-connector[bot]"},body:"Blocking issues: top-level problem not represented by an inline thread."}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_CLEARED_THREAD_TOP_LEVEL_BLOCKER_GH
chmod +x "$_codex_cleared_thread_top_level_blocker_mock_dir/gh"
: > "$_codex_cleared_thread_top_level_blocker_mock_dir/posts.log"
_codex_cleared_thread_top_level_blocker_exit=0
MOCK_POST_LOG="$_codex_cleared_thread_top_level_blocker_mock_dir/posts.log" PATH="$_codex_cleared_thread_top_level_blocker_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --pre-trigger-wait 1 --max-retriggers 0 \
  >"$_codex_cleared_thread_top_level_blocker_mock_dir/output.txt" 2>&1 || _codex_cleared_thread_top_level_blocker_exit=$?
run_test "codex_cleared_thread_top_level_blocker_exit_needs_revision" "2" "$_codex_cleared_thread_top_level_blocker_exit"
run_test "codex_cleared_thread_top_level_blocker_skips_trigger" "0" \
  "$(wc -l < "$_codex_cleared_thread_top_level_blocker_mock_dir/posts.log" | tr -d ' ')"
run_test "codex_cleared_thread_top_level_blocker_verdict" "VERDICT: ESCALATE — Codex finding has no stable review-thread identifier or no identifiable matching review-thread conversation" \
  "$(grep "^VERDICT:" "$_codex_cleared_thread_top_level_blocker_mock_dir/output.txt")"
rm -rf "$_codex_cleared_thread_top_level_blocker_mock_dir"
unset _codex_cleared_thread_top_level_blocker_mock_dir _codex_cleared_thread_top_level_blocker_exit

_codex_cleared_thread_changes_requested_state_mock_dir="$(mktemp -d)"
cat > "$_codex_cleared_thread_changes_requested_state_mock_dir/gh" <<'CODEX_CLEARED_THREAD_CHANGES_REQUESTED_STATE_GH'
#!/usr/bin/env bash
log="$MOCK_POST_LOG"
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf '7777777777777777777777777777777777777777\n'; exit 0 ;;
  *"api graphql"*)
    printf '{"data":{"repository":{"pullRequest":{"headRef":{"target":{"committedDate":"2026-01-01T00:00:00Z"}},"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"isResolved":true,"isOutdated":false,"firstComment":{"nodes":[{"author":{"login":"chatgpt-codex-connector"},"body":"Resolved inline finding"}]},"lastComment":{"nodes":[{"author":{"login":"lhpaul"},"createdAt":"2026-01-01T00:00:01Z"}]}}]}}}}}\n'
    exit 0 ;;
  *"--method POST"*)
    printf 'POST\n' >> "$log"
    printf '{"id":114,"created_at":"2026-01-01T00:00:10Z"}\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    jq -nc '[{submitted_at:"2026-01-01T00:00:01Z",commit_id:"7777777777777777777777777777777777777777",state:"CHANGES_REQUESTED",user:{login:"chatgpt-codex-connector[bot]"},body:"### 💡 Codex Review\n\nHere are some automated review suggestions for this pull request.\n\n**Reviewed commit:** `777777777777`"}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_CLEARED_THREAD_CHANGES_REQUESTED_STATE_GH
chmod +x "$_codex_cleared_thread_changes_requested_state_mock_dir/gh"
: > "$_codex_cleared_thread_changes_requested_state_mock_dir/posts.log"
_codex_cleared_thread_changes_requested_state_exit=0
MOCK_POST_LOG="$_codex_cleared_thread_changes_requested_state_mock_dir/posts.log" PATH="$_codex_cleared_thread_changes_requested_state_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --pre-trigger-wait 1 --max-retriggers 0 \
  >"$_codex_cleared_thread_changes_requested_state_mock_dir/output.txt" 2>&1 || _codex_cleared_thread_changes_requested_state_exit=$?
run_test "codex_cleared_thread_changes_requested_state_exit_needs_revision" "1" "$_codex_cleared_thread_changes_requested_state_exit"
run_test "codex_cleared_thread_changes_requested_state_skips_trigger" "0" \
  "$(wc -l < "$_codex_cleared_thread_changes_requested_state_mock_dir/posts.log" | tr -d ' ')"
run_test "codex_cleared_thread_changes_requested_state_verdict" "VERDICT: NEEDS_REVISION" \
  "$(grep "^VERDICT:" "$_codex_cleared_thread_changes_requested_state_mock_dir/output.txt")"
rm -rf "$_codex_cleared_thread_changes_requested_state_mock_dir"
unset _codex_cleared_thread_changes_requested_state_mock_dir _codex_cleared_thread_changes_requested_state_exit

_codex_pre_trigger_head_changed_mock_dir="$(mktemp -d)"
cat > "$_codex_pre_trigger_head_changed_mock_dir/gh" <<'CODEX_PRE_TRIGGER_HEAD_CHANGED_GH'
#!/usr/bin/env bash
log="$MOCK_POST_LOG"
counter_file="$MOCK_PR_VIEW_COUNTER"
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    count=0
    if [ -f "$counter_file" ]; then
      count="$(cat "$counter_file")"
    fi
    count=$((count + 1))
    printf '%s\n' "$count" > "$counter_file"
    if [ "$count" -eq 1 ]; then
      printf 'dddddddddddddddddddddddddddddddddddddddd\n'
    else
      printf 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\n'
    fi
    exit 0 ;;
  *"api graphql"*)
    printf '{"data":{"repository":{"pullRequest":{"headRef":{"target":{"committedDate":"2026-01-01T00:00:00Z"}},"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}}}}}\n'
    exit 0 ;;
  *"--method POST"*)
    printf 'POST\n' >> "$log"
    printf '{"id":110,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_PRE_TRIGGER_HEAD_CHANGED_GH
chmod +x "$_codex_pre_trigger_head_changed_mock_dir/gh"
: > "$_codex_pre_trigger_head_changed_mock_dir/posts.log"
: > "$_codex_pre_trigger_head_changed_mock_dir/pr-view-count"
_codex_pre_trigger_head_changed_exit=0
MOCK_POST_LOG="$_codex_pre_trigger_head_changed_mock_dir/posts.log" \
  MOCK_PR_VIEW_COUNTER="$_codex_pre_trigger_head_changed_mock_dir/pr-view-count" \
  PATH="$_codex_pre_trigger_head_changed_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --pre-trigger-wait 1 --max-retriggers 0 \
  >"$_codex_pre_trigger_head_changed_mock_dir/output.txt" 2>&1 || _codex_pre_trigger_head_changed_exit=$?
run_test "codex_pre_trigger_head_changed_exit_unavailable" "2" "$_codex_pre_trigger_head_changed_exit"
run_test "codex_pre_trigger_head_changed_skips_trigger" "0" \
  "$(wc -l < "$_codex_pre_trigger_head_changed_mock_dir/posts.log" | tr -d ' ')"
run_test "codex_pre_trigger_head_changed_reason" "REASON=codex-github-head-changed" \
  "$(grep "^REASON=" "$_codex_pre_trigger_head_changed_mock_dir/output.txt")"
rm -rf "$_codex_pre_trigger_head_changed_mock_dir"
unset _codex_pre_trigger_head_changed_mock_dir _codex_pre_trigger_head_changed_exit

_codex_paginated_thread_mock_dir="$(mktemp -d)"
cat > "$_codex_paginated_thread_mock_dir/gh" <<'CODEX_PAGINATED_THREAD_GH'
#!/usr/bin/env bash
log="$MOCK_POST_LOG"
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\n'; exit 0 ;;
  *"api graphql"*cursor1*)
    printf '{"data":{"repository":{"pullRequest":{"headRef":{"target":{"committedDate":"2026-01-01T00:00:00Z"}},"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"isResolved":false,"isOutdated":false,"firstComment":{"nodes":[{"author":{"login":"chatgpt-codex-connector"}}]},"lastComment":{"nodes":[{"author":{"login":"chatgpt-codex-connector"},"createdAt":"2026-01-01T00:00:01Z"}]}}]}}}}}\n'
    exit 0 ;;
  *"api graphql"*)
    case " $* " in
      *" -f cursor="*)
        printf 'ERROR=first-page-cursor-sent\n' >&2
        exit 65 ;;
    esac
    printf '{"data":{"repository":{"pullRequest":{"headRef":{"target":{"committedDate":"2026-01-01T00:00:00Z"}},"reviewThreads":{"pageInfo":{"hasNextPage":true,"endCursor":"cursor1"},"nodes":[]}}}}}\n'
    exit 0 ;;
  *"--method POST"*)
    printf 'POST\n' >> "$log"
    printf '{"id":108,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_PAGINATED_THREAD_GH
chmod +x "$_codex_paginated_thread_mock_dir/gh"
: > "$_codex_paginated_thread_mock_dir/posts.log"
_codex_paginated_thread_output=""
_codex_paginated_thread_exit=0
MOCK_POST_LOG="$_codex_paginated_thread_mock_dir/posts.log" PATH="$_codex_paginated_thread_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --pre-trigger-wait 1 --max-retriggers 0 \
  >"$_codex_paginated_thread_mock_dir/output.txt" 2>&1 || _codex_paginated_thread_exit=$?
_codex_paginated_thread_output="$(cat "$_codex_paginated_thread_mock_dir/output.txt")"
run_test "codex_paginated_thread_exit_needs_revision" "1" "$_codex_paginated_thread_exit"
run_test "codex_paginated_thread_verdict" "VERDICT: NEEDS_REVISION" \
  "$(printf '%s\n' "$_codex_paginated_thread_output" | grep "^VERDICT:")"
run_test "codex_paginated_thread_skips_trigger" "0" \
  "$(wc -l < "$_codex_paginated_thread_mock_dir/posts.log" | tr -d ' ')"
rm -rf "$_codex_paginated_thread_mock_dir"
unset _codex_paginated_thread_mock_dir _codex_paginated_thread_output _codex_paginated_thread_exit

_codex_reaction_mock_dir="$(mktemp -d)"
cat > "$_codex_reaction_mock_dir/gh" <<'CODEX_REACTION_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'abcreact1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":103,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[{"content":"+1","user":{"login":"chatgpt-codex-connector[bot]"}}]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_REACTION_GH
chmod +x "$_codex_reaction_mock_dir/gh"

_codex_reaction_output=""
_codex_reaction_exit=0
PATH="$_codex_reaction_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_reaction_mock_dir/output.txt" 2>&1 || _codex_reaction_exit=$?
_codex_reaction_output="$(cat "$_codex_reaction_mock_dir/output.txt")"
# #1757 (AC-10): acknowledgement-only evidence is waiting_on_reviewer (exit
# 4), not an escalation (exit 2) — remapped from the shipped exit 2.
run_test "codex_reaction_only_exit_waiting" "4" "$_codex_reaction_exit"
run_test "codex_reaction_only_reason" "REASON=codex-github-reaction-without-review" \
  "$(printf '%s\n' "$_codex_reaction_output" | grep "^REASON=")"
rm -rf "$_codex_reaction_mock_dir"
unset _codex_reaction_mock_dir _codex_reaction_output _codex_reaction_exit

_codex_clean_root_review_comment_mock_dir="$(mktemp -d)"
cat > "$_codex_clean_root_review_comment_mock_dir/gh" <<'CODEX_CLEAN_ROOT_REVIEW_COMMENT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'abcdefab1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":118,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    jq -nc '[{id:218,created_at:"2026-01-01T00:00:01Z",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'\''t find any major issues. Swish! **Reviewed commit:** `abcdefab12` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> [Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment \"@codex review\". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\". </details>")}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_CLEAN_ROOT_REVIEW_COMMENT_GH
chmod +x "$_codex_clean_root_review_comment_mock_dir/gh"

_codex_clean_root_review_comment_output=""
_codex_clean_root_review_comment_exit=0
PATH="$_codex_clean_root_review_comment_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_clean_root_review_comment_mock_dir/output.txt" 2>&1 || _codex_clean_root_review_comment_exit=$?
_codex_clean_root_review_comment_output="$(cat "$_codex_clean_root_review_comment_mock_dir/output.txt")"
run_test "codex_clean_root_review_comment_exit_clean" "0" "$_codex_clean_root_review_comment_exit"
run_test "codex_clean_root_review_comment_approved" "VERDICT: APPROVED" \
  "$(printf '%s\n' "$_codex_clean_root_review_comment_output" | grep "^VERDICT:")"
rm -rf "$_codex_clean_root_review_comment_mock_dir"
unset _codex_clean_root_review_comment_mock_dir _codex_clean_root_review_comment_output _codex_clean_root_review_comment_exit

_codex_full_root_review_comment_mock_dir="$(mktemp -d)"
cat > "$_codex_full_root_review_comment_mock_dir/gh" <<'CODEX_FULL_ROOT_REVIEW_COMMENT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'abcabcabcabc1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":126,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    jq -nc '[{id:226,created_at:"2026-01-01T00:00:01Z",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'\''t find any major issues. Swish! **Reviewed commit:** `abcabcabcabc1234567890` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> [Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment \"@codex review\". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\". </details>")}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_FULL_ROOT_REVIEW_COMMENT_GH
chmod +x "$_codex_full_root_review_comment_mock_dir/gh"

_codex_full_root_review_comment_output=""
_codex_full_root_review_comment_exit=0
PATH="$_codex_full_root_review_comment_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_full_root_review_comment_mock_dir/output.txt" 2>&1 || _codex_full_root_review_comment_exit=$?
_codex_full_root_review_comment_output="$(cat "$_codex_full_root_review_comment_mock_dir/output.txt")"
run_test "codex_full_root_review_comment_exit_clean" "0" "$_codex_full_root_review_comment_exit"
run_test "codex_full_root_review_comment_approved" "VERDICT: APPROVED" \
  "$(printf '%s\n' "$_codex_full_root_review_comment_output" | grep "^VERDICT:")"
rm -rf "$_codex_full_root_review_comment_mock_dir"
unset _codex_full_root_review_comment_mock_dir _codex_full_root_review_comment_output _codex_full_root_review_comment_exit

_codex_stale_root_review_comment_mock_dir="$(mktemp -d)"
cat > "$_codex_stale_root_review_comment_mock_dir/gh" <<'CODEX_STALE_ROOT_REVIEW_COMMENT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'abc123aa1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":119,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":219,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"Codex Review: Didn'\''t find any major issues.\\n\\n**Reviewed commit:** `def456bb12`"}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_STALE_ROOT_REVIEW_COMMENT_GH
chmod +x "$_codex_stale_root_review_comment_mock_dir/gh"

_codex_stale_root_review_comment_output=""
_codex_stale_root_review_comment_exit=0
PATH="$_codex_stale_root_review_comment_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_stale_root_review_comment_mock_dir/output.txt" 2>&1 || _codex_stale_root_review_comment_exit=$?
_codex_stale_root_review_comment_output="$(cat "$_codex_stale_root_review_comment_mock_dir/output.txt")"
run_test "codex_stale_root_review_comment_exit_waiting" "4" "$_codex_stale_root_review_comment_exit"
if printf '%s\n' "$_codex_stale_root_review_comment_output" | grep -q "^VERDICT: APPROVED"; then
  _codex_stale_root_review_comment_approved="yes"
else
  _codex_stale_root_review_comment_approved="no"
fi
run_test "codex_stale_root_review_comment_not_approved" "no" "$_codex_stale_root_review_comment_approved"
rm -rf "$_codex_stale_root_review_comment_mock_dir"
unset _codex_stale_root_review_comment_mock_dir _codex_stale_root_review_comment_output _codex_stale_root_review_comment_exit _codex_stale_root_review_comment_approved

_codex_newer_root_blocks_old_review_mock_dir="$(mktemp -d)"
cat > "$_codex_newer_root_blocks_old_review_mock_dir/gh" <<'CODEX_NEWER_ROOT_BLOCKS_OLD_REVIEW_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'feed12341234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":123,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[{"submitted_at":"2026-01-01T00:00:01Z","commit_id":"feed12341234567890","user":{"login":"chatgpt-codex-connector[bot]"},"body":"No blocking issues found."}]\n'
    exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":223,"created_at":"2026-01-01T00:00:02Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"Blocking issues: newer root finding.\\n\\n**Reviewed commit:** `feed1234`"}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_NEWER_ROOT_BLOCKS_OLD_REVIEW_GH
chmod +x "$_codex_newer_root_blocks_old_review_mock_dir/gh"

_codex_newer_root_blocks_old_review_output=""
_codex_newer_root_blocks_old_review_exit=0
PATH="$_codex_newer_root_blocks_old_review_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_newer_root_blocks_old_review_mock_dir/output.txt" 2>&1 || _codex_newer_root_blocks_old_review_exit=$?
_codex_newer_root_blocks_old_review_output="$(cat "$_codex_newer_root_blocks_old_review_mock_dir/output.txt")"
run_test "codex_newer_root_blocks_old_review_exit_needs_revision" "2" "$_codex_newer_root_blocks_old_review_exit"
run_test "codex_newer_root_blocks_old_review_verdict" "VERDICT: ESCALATE — Codex finding has no stable review-thread identifier or no identifiable matching review-thread conversation" \
  "$(printf '%s\n' "$_codex_newer_root_blocks_old_review_output" | grep "^VERDICT:")"
rm -rf "$_codex_newer_root_blocks_old_review_mock_dir"
unset _codex_newer_root_blocks_old_review_mock_dir _codex_newer_root_blocks_old_review_output _codex_newer_root_blocks_old_review_exit

_codex_tied_root_blocks_review_mock_dir="$(mktemp -d)"
cat > "$_codex_tied_root_blocks_review_mock_dir/gh" <<'CODEX_TIED_ROOT_BLOCKS_REVIEW_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'cafe12341234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":127,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[{"submitted_at":"2026-01-01T00:00:01Z","commit_id":"cafe12341234567890","user":{"login":"chatgpt-codex-connector[bot]"},"body":"No blocking issues found."}]\n'
    exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":227,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"Blocking issues: tied root finding.\\n\\n**Reviewed commit:** `cafe1234`"}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_TIED_ROOT_BLOCKS_REVIEW_GH
chmod +x "$_codex_tied_root_blocks_review_mock_dir/gh"

_codex_tied_root_blocks_review_output=""
_codex_tied_root_blocks_review_exit=0
PATH="$_codex_tied_root_blocks_review_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_tied_root_blocks_review_mock_dir/output.txt" 2>&1 || _codex_tied_root_blocks_review_exit=$?
_codex_tied_root_blocks_review_output="$(cat "$_codex_tied_root_blocks_review_mock_dir/output.txt")"
run_test "codex_tied_root_blocks_review_exit_needs_revision" "2" "$_codex_tied_root_blocks_review_exit"
run_test "codex_tied_root_blocks_review_verdict" "VERDICT: ESCALATE — Codex finding has no stable review-thread identifier or no identifiable matching review-thread conversation" \
  "$(printf '%s\n' "$_codex_tied_root_blocks_review_output" | grep "^VERDICT:")"
rm -rf "$_codex_tied_root_blocks_review_mock_dir"
unset _codex_tied_root_blocks_review_mock_dir _codex_tied_root_blocks_review_output _codex_tied_root_blocks_review_exit

# Reverse of codex_tied_root_blocks_review: this time the SHA-pinned root
# comment is CLEAN and the submitted review (same timestamp) is BLOCKING. The
# tie-break must be symmetric (blocking wins on ties regardless of which
# source supplied it), so this must also resolve to NEEDS_REVISION.
_codex_tied_review_blocks_root_mock_dir="$(mktemp -d)"
cat > "$_codex_tied_review_blocks_root_mock_dir/gh" <<'CODEX_TIED_REVIEW_BLOCKS_ROOT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'beefcafe1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":129,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[{"submitted_at":"2026-01-01T00:00:01Z","commit_id":"beefcafe1234567890","user":{"login":"chatgpt-codex-connector[bot]"},"body":"Blocking issues: tied review finding."}]\n'
    exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":229,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"Codex Review: Didn'\''t find any major issues.\\n\\n**Reviewed commit:** `beefcafe1234`"}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_TIED_REVIEW_BLOCKS_ROOT_GH
chmod +x "$_codex_tied_review_blocks_root_mock_dir/gh"

_codex_tied_review_blocks_root_output=""
_codex_tied_review_blocks_root_exit=0
PATH="$_codex_tied_review_blocks_root_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_tied_review_blocks_root_mock_dir/output.txt" 2>&1 || _codex_tied_review_blocks_root_exit=$?
_codex_tied_review_blocks_root_output="$(cat "$_codex_tied_review_blocks_root_mock_dir/output.txt")"
run_test "codex_tied_review_blocks_root_exit_needs_revision" "2" "$_codex_tied_review_blocks_root_exit"
run_test "codex_tied_review_blocks_root_verdict" "VERDICT: ESCALATE — Codex finding has no stable review-thread identifier or no identifiable matching review-thread conversation" \
  "$(printf '%s\n' "$_codex_tied_review_blocks_root_output" | grep "^VERDICT:")"
rm -rf "$_codex_tied_review_blocks_root_mock_dir"
unset _codex_tied_review_blocks_root_mock_dir _codex_tied_review_blocks_root_output _codex_tied_review_blocks_root_exit

# Reproduces Codex finding on PR #1490 (P1, comment id 3787623071): the
# terminal-evidence tie-break only checked codex_response_is_blocking, so an
# unrecognized-format submitted review tied with a clean SHA-pinned root
# comment lost the tie-break and the clean root comment won, returning
# APPROVED instead of the documented safe-fail NEEDS_REVISION for
# unrecognized responses. Root comment is a clean approval; tied review body
# matches neither the blocking nor approval pattern.
_codex_tied_unrecognized_review_safe_fails_mock_dir="$(mktemp -d)"
cat > "$_codex_tied_unrecognized_review_safe_fails_mock_dir/gh" <<'CODEX_TIED_UNRECOGNIZED_REVIEW_SAFE_FAILS_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'deadfeed1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":131,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[{"submitted_at":"2026-01-01T00:00:01Z","commit_id":"deadfeed1234567890","user":{"login":"chatgpt-codex-connector[bot]"},"body":"Some ambiguous status update with no recognized marker."}]\n'
    exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":231,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"Codex Review: Didn'\''t find any major issues.\\n\\n**Reviewed commit:** `deadfeed1234`"}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_TIED_UNRECOGNIZED_REVIEW_SAFE_FAILS_GH
chmod +x "$_codex_tied_unrecognized_review_safe_fails_mock_dir/gh"

_codex_tied_unrecognized_review_safe_fails_output=""
_codex_tied_unrecognized_review_safe_fails_exit=0
PATH="$_codex_tied_unrecognized_review_safe_fails_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_tied_unrecognized_review_safe_fails_mock_dir/output.txt" 2>&1 || _codex_tied_unrecognized_review_safe_fails_exit=$?
_codex_tied_unrecognized_review_safe_fails_output="$(cat "$_codex_tied_unrecognized_review_safe_fails_mock_dir/output.txt")"
run_test "codex_tied_unrecognized_review_safe_fails_exit_needs_revision" "2" "$_codex_tied_unrecognized_review_safe_fails_exit"
run_test "codex_tied_unrecognized_review_safe_fails_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_tied_unrecognized_review_safe_fails_output" | grep "^VERDICT:")"
rm -rf "$_codex_tied_unrecognized_review_safe_fails_mock_dir"
unset _codex_tied_unrecognized_review_safe_fails_mock_dir _codex_tied_unrecognized_review_safe_fails_output _codex_tied_unrecognized_review_safe_fails_exit

# A clean submitted review arrives first, then a SHA-pinned BLOCKING root
# comment, then a newer non-terminal acknowledgement comment. Greedily
# selecting the latest root comment overall (the ack) would discard the
# blocking root comment and let the earlier clean review win by default. The
# terminal SHA-pinned comment must be selected independently of the latest
# ancillary comment.
_codex_ack_does_not_erase_blocking_root_mock_dir="$(mktemp -d)"
cat > "$_codex_ack_does_not_erase_blocking_root_mock_dir/gh" <<'CODEX_ACK_DOES_NOT_ERASE_BLOCKING_ROOT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'dead12341234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":130,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[{"submitted_at":"2026-01-01T00:00:01Z","commit_id":"dead12341234567890","user":{"login":"chatgpt-codex-connector[bot]"},"body":"No blocking issues found."}]\n'
    exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":231,"created_at":"2026-01-01T00:00:02Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"Blocking issues: root finding before ack.\\n\\n**Reviewed commit:** `dead12341234`"},{"id":232,"created_at":"2026-01-01T00:00:03Z","user":{"login":"chatgpt-codex-connector"},"body":"If Codex has suggestions, it will comment; otherwise it will react with thumbs up."}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_ACK_DOES_NOT_ERASE_BLOCKING_ROOT_GH
chmod +x "$_codex_ack_does_not_erase_blocking_root_mock_dir/gh"

_codex_ack_does_not_erase_blocking_root_output=""
_codex_ack_does_not_erase_blocking_root_exit=0
PATH="$_codex_ack_does_not_erase_blocking_root_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_ack_does_not_erase_blocking_root_mock_dir/output.txt" 2>&1 || _codex_ack_does_not_erase_blocking_root_exit=$?
_codex_ack_does_not_erase_blocking_root_output="$(cat "$_codex_ack_does_not_erase_blocking_root_mock_dir/output.txt")"
run_test "codex_ack_does_not_erase_blocking_root_exit_needs_revision" "2" "$_codex_ack_does_not_erase_blocking_root_exit"
run_test "codex_ack_does_not_erase_blocking_root_verdict" "VERDICT: ESCALATE — Codex finding has no stable review-thread identifier or no identifiable matching review-thread conversation" \
  "$(printf '%s\n' "$_codex_ack_does_not_erase_blocking_root_output" | grep "^VERDICT:")"
rm -rf "$_codex_ack_does_not_erase_blocking_root_mock_dir"
unset _codex_ack_does_not_erase_blocking_root_mock_dir _codex_ack_does_not_erase_blocking_root_output _codex_ack_does_not_erase_blocking_root_exit

_codex_async_newer_root_blocks_old_review_mock_dir="$(mktemp -d)"
printf '0\n' > "$_codex_async_newer_root_blocks_old_review_mock_dir/comment_calls"
printf '0\n' > "$_codex_async_newer_root_blocks_old_review_mock_dir/review_calls"
cat > "$_codex_async_newer_root_blocks_old_review_mock_dir/gh" <<'CODEX_ASYNC_NEWER_ROOT_BLOCKS_OLD_REVIEW_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'deaf12341234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":125,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    calls_file="$(dirname "$0")/review_calls"
    calls="$(cat "$calls_file")"
    calls=$((calls + 1))
    printf '%s\n' "$calls" > "$calls_file"
    if [ "$calls" -ge 2 ]; then
      printf '[{"submitted_at":"2026-01-01T00:00:01Z","commit_id":"deaf12341234567890","user":{"login":"chatgpt-codex-connector[bot]"},"body":"No blocking issues found."}]\n'
    else
      printf '[]\n'
    fi
    exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    calls_file="$(dirname "$0")/comment_calls"
    calls="$(cat "$calls_file")"
    calls=$((calls + 1))
    printf '%s\n' "$calls" > "$calls_file"
    if [ "$calls" -ge 2 ]; then
      printf '[{"id":225,"created_at":"2026-01-01T00:00:02Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"Blocking issues: newer async root finding.\\n\\n**Reviewed commit:** `deaf1234`"}]\n'
    else
      printf '[]\n'
    fi
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_ASYNC_NEWER_ROOT_BLOCKS_OLD_REVIEW_GH
chmod +x "$_codex_async_newer_root_blocks_old_review_mock_dir/gh"

_codex_async_newer_root_blocks_old_review_output=""
_codex_async_newer_root_blocks_old_review_exit=0
PATH="$_codex_async_newer_root_blocks_old_review_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_async_newer_root_blocks_old_review_mock_dir/output.txt" 2>&1 || _codex_async_newer_root_blocks_old_review_exit=$?
_codex_async_newer_root_blocks_old_review_output="$(cat "$_codex_async_newer_root_blocks_old_review_mock_dir/output.txt")"
run_test "codex_async_newer_root_blocks_old_review_exit_needs_revision" "2" "$_codex_async_newer_root_blocks_old_review_exit"
run_test "codex_async_newer_root_blocks_old_review_verdict" "VERDICT: ESCALATE — Codex finding has no stable review-thread identifier or no identifiable matching review-thread conversation" \
  "$(printf '%s\n' "$_codex_async_newer_root_blocks_old_review_output" | grep "^VERDICT:")"
rm -rf "$_codex_async_newer_root_blocks_old_review_mock_dir"
unset _codex_async_newer_root_blocks_old_review_mock_dir _codex_async_newer_root_blocks_old_review_output _codex_async_newer_root_blocks_old_review_exit

# Root comments are a terminal evidence source. If the root-comments fetch
# fails specifically during the async grace period while the reviews fetch
# succeeds with a clean review, the failure must be treated as unavailable
# (fail closed) rather than silently falling through to accept the clean
# review as if no root evidence existed (fail open). Sequence: idempotency
# check (call 1, empty) and main-loop poll (call 2, empty) succeed normally;
# the async-grace root-comments fetch (call 3) fails.
_codex_async_root_fetch_failure_mock_dir="$(mktemp -d)"
printf '0\n' > "$_codex_async_root_fetch_failure_mock_dir/comment_calls"
printf '0\n' > "$_codex_async_root_fetch_failure_mock_dir/review_calls"
cat > "$_codex_async_root_fetch_failure_mock_dir/gh" <<'CODEX_ASYNC_ROOT_FETCH_FAILURE_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'fade12341234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":128,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    calls_file="$(dirname "$0")/review_calls"
    calls="$(cat "$calls_file")"
    calls=$((calls + 1))
    printf '%s\n' "$calls" > "$calls_file"
    if [ "$calls" -ge 2 ]; then
      printf '[{"submitted_at":"2026-01-01T00:00:05Z","commit_id":"fade12341234567890","user":{"login":"chatgpt-codex-connector[bot]"},"body":"No blocking issues found."}]\n'
    else
      printf '[]\n'
    fi
    exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    calls_file="$(dirname "$0")/comment_calls"
    calls="$(cat "$calls_file")"
    calls=$((calls + 1))
    printf '%s\n' "$calls" > "$calls_file"
    if [ "$calls" -ge 3 ]; then
      echo "simulated transient API failure" >&2
      exit 1
    fi
    printf '[]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_ASYNC_ROOT_FETCH_FAILURE_GH
chmod +x "$_codex_async_root_fetch_failure_mock_dir/gh"

_codex_async_root_fetch_failure_output=""
_codex_async_root_fetch_failure_exit=0
PATH="$_codex_async_root_fetch_failure_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_async_root_fetch_failure_mock_dir/output.txt" 2>&1 || _codex_async_root_fetch_failure_exit=$?
_codex_async_root_fetch_failure_output="$(cat "$_codex_async_root_fetch_failure_mock_dir/output.txt")"
run_test "codex_async_root_fetch_failure_exit_unavailable" "2" "$_codex_async_root_fetch_failure_exit"
run_test "codex_async_root_fetch_failure_verdict" \
  "VERDICT: TIMED_OUT — failed to fetch Codex root comments during async grace period (treated as unavailable)" \
  "$(printf '%s\n' "$_codex_async_root_fetch_failure_output" | grep "^VERDICT:")"
if printf '%s\n' "$_codex_async_root_fetch_failure_output" | grep -q "^VERDICT: APPROVED"; then
  _codex_async_root_fetch_failure_approved="yes"
else
  _codex_async_root_fetch_failure_approved="no"
fi
run_test "codex_async_root_fetch_failure_not_approved" "no" "$_codex_async_root_fetch_failure_approved"
rm -rf "$_codex_async_root_fetch_failure_mock_dir"
unset _codex_async_root_fetch_failure_mock_dir _codex_async_root_fetch_failure_output _codex_async_root_fetch_failure_exit _codex_async_root_fetch_failure_approved

_codex_reaction_with_review_mock_dir="$(mktemp -d)"
cat > "$_codex_reaction_with_review_mock_dir/gh" <<'CODEX_REACTION_WITH_REVIEW_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'abcreviewok1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":106,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[{"content":"+1","user":{"login":"chatgpt-codex-connector[bot]"}}]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    jq -nc '[{submitted_at:"2026-01-01T00:00:00Z",commit_id:"abcreviewok1234567890",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'\''t find any major issues. Swish! **Reviewed commit:** `aaaaaaaaaa` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> [Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment \"@codex review\". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\". </details>")}]'
    exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":206,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector"},"body":"If Codex has suggestions, it will comment; otherwise it will react with thumbs up."}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_REACTION_WITH_REVIEW_GH
chmod +x "$_codex_reaction_with_review_mock_dir/gh"

_codex_reaction_with_review_output=""
_codex_reaction_with_review_exit=0
PATH="$_codex_reaction_with_review_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_reaction_with_review_mock_dir/output.txt" 2>&1 || _codex_reaction_with_review_exit=$?
_codex_reaction_with_review_output="$(cat "$_codex_reaction_with_review_mock_dir/output.txt")"
run_test "codex_reaction_with_current_review_exit_clean" "0" "$_codex_reaction_with_review_exit"
run_test "codex_reaction_with_current_review_approved" "VERDICT: APPROVED" \
  "$(printf '%s\n' "$_codex_reaction_with_review_output" | grep "^VERDICT:")"
rm -rf "$_codex_reaction_with_review_mock_dir"
unset _codex_reaction_with_review_mock_dir _codex_reaction_with_review_output _codex_reaction_with_review_exit

_codex_reaction_then_review_mock_dir="$(mktemp -d)"
printf '0\n' > "$_codex_reaction_then_review_mock_dir/review_calls"
cat > "$_codex_reaction_then_review_mock_dir/gh" <<'CODEX_REACTION_THEN_REVIEW_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'abcreactlate1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":117,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[{"content":"+1","user":{"login":"chatgpt-codex-connector[bot]"}}]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    calls_file="$(dirname "$0")/review_calls"
    calls="$(cat "$calls_file")"
    calls=$((calls + 1))
    printf '%s\n' "$calls" > "$calls_file"
    if [ "$calls" -ge 2 ]; then
      jq -nc '[{submitted_at:"2026-01-01T00:00:01Z",commit_id:"abcreactlate1234567890",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'\''t find any major issues. Swish! **Reviewed commit:** `bbbbbbbbbb` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> [Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment \"@codex review\". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\". </details>")}]'
    else
      printf '[]\n'
    fi
    exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_REACTION_THEN_REVIEW_GH
chmod +x "$_codex_reaction_then_review_mock_dir/gh"

_codex_reaction_then_review_output=""
_codex_reaction_then_review_exit=0
PATH="$_codex_reaction_then_review_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 2 --max-retriggers 0 \
  >"$_codex_reaction_then_review_mock_dir/output.txt" 2>&1 || _codex_reaction_then_review_exit=$?
_codex_reaction_then_review_output="$(cat "$_codex_reaction_then_review_mock_dir/output.txt")"
run_test "codex_reaction_then_late_review_exit_clean" "0" "$_codex_reaction_then_review_exit"
run_test "codex_reaction_then_late_review_approved" "VERDICT: APPROVED" \
  "$(printf '%s\n' "$_codex_reaction_then_review_output" | grep "^VERDICT:")"
rm -rf "$_codex_reaction_then_review_mock_dir"
unset _codex_reaction_then_review_mock_dir _codex_reaction_then_review_output _codex_reaction_then_review_exit

_codex_async_reaction_then_review_mock_dir="$(mktemp -d)"
printf '0\n' > "$_codex_async_reaction_then_review_mock_dir/review_calls"
cat > "$_codex_async_reaction_then_review_mock_dir/gh" <<'CODEX_ASYNC_REACTION_THEN_REVIEW_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'abc456aa1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":122,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[{"content":"+1","user":{"login":"chatgpt-codex-connector[bot]"}}]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    calls_file="$(dirname "$0")/review_calls"
    calls="$(cat "$calls_file")"
    calls=$((calls + 1))
    printf '%s\n' "$calls" > "$calls_file"
    if [ "$calls" -ge 3 ]; then
      jq -nc '[{submitted_at:"2026-01-01T00:00:01Z",commit_id:"abc456aa1234567890",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'\''t find any major issues. Swish! **Reviewed commit:** `cccccccccc` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> [Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment \"@codex review\". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\". </details>")}]'
    else
      printf '[]\n'
    fi
    exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_ASYNC_REACTION_THEN_REVIEW_GH
chmod +x "$_codex_async_reaction_then_review_mock_dir/gh"

_codex_async_reaction_then_review_output=""
_codex_async_reaction_then_review_exit=0
PATH="$_codex_async_reaction_then_review_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_async_reaction_then_review_mock_dir/output.txt" 2>&1 || _codex_async_reaction_then_review_exit=$?
_codex_async_reaction_then_review_output="$(cat "$_codex_async_reaction_then_review_mock_dir/output.txt")"
run_test "codex_async_reaction_then_late_review_exit_clean" "0" "$_codex_async_reaction_then_review_exit"
run_test "codex_async_reaction_then_late_review_approved" "VERDICT: APPROVED" \
  "$(printf '%s\n' "$_codex_async_reaction_then_review_output" | grep "^VERDICT:")"
rm -rf "$_codex_async_reaction_then_review_mock_dir"
unset _codex_async_reaction_then_review_mock_dir _codex_async_reaction_then_review_output _codex_async_reaction_then_review_exit

_codex_async_reaction_environment_mock_dir="$(mktemp -d)"
cat > "$_codex_async_reaction_environment_mock_dir/gh" <<'CODEX_ASYNC_REACTION_ENVIRONMENT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'abc789aa1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":124,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[{"content":"+1","user":{"login":"chatgpt-codex-connector[bot]"}}]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":224,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"To use Codex here, create an environment for this repo."}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_ASYNC_REACTION_ENVIRONMENT_GH
chmod +x "$_codex_async_reaction_environment_mock_dir/gh"

_codex_async_reaction_environment_output=""
_codex_async_reaction_environment_exit=0
PATH="$_codex_async_reaction_environment_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_async_reaction_environment_mock_dir/output.txt" 2>&1 || _codex_async_reaction_environment_exit=$?
_codex_async_reaction_environment_output="$(cat "$_codex_async_reaction_environment_mock_dir/output.txt")"
run_test "codex_async_reaction_environment_exit_unavailable" "2" "$_codex_async_reaction_environment_exit"
run_test "codex_async_reaction_environment_reason" "REASON=codex-github-environment-missing" \
  "$(printf '%s\n' "$_codex_async_reaction_environment_output" | grep "^REASON=")"
rm -rf "$_codex_async_reaction_environment_mock_dir"
unset _codex_async_reaction_environment_mock_dir _codex_async_reaction_environment_output _codex_async_reaction_environment_exit

# Reproduces Codex finding 3786691880-followup (P2, comment id 3787460055):
# the final acknowledgement re-poll must preserve a recorded environment
# setup error instead of returning reaction-without-review when a thumbs-up
# reaction is also present. Sequence: initial async-grace poll finds the
# acknowledgement comment (no review, no reaction yet) -> sleeps -> final
# re-poll finds an environment-setup comment (sets SEEN_ENVIRONMENT_ERROR)
# -> trigger reactions endpoint reports a thumbs-up -> expect
# codex-github-environment-missing, not codex-github-reaction-without-review.
_codex_ack_repoll_env_then_reaction_mock_dir="$(mktemp -d)"
printf '0\n' > "$_codex_ack_repoll_env_then_reaction_mock_dir/comment_calls"
cat > "$_codex_ack_repoll_env_then_reaction_mock_dir/gh" <<'CODEX_ACK_REPOLL_ENV_THEN_REACTION_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'ackrepoll1234567890a\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":126,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[{"content":"+1","user":{"login":"chatgpt-codex-connector[bot]"}}]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    calls_file="$(dirname "$0")/comment_calls"
    calls="$(cat "$calls_file")"
    calls=$((calls + 1))
    printf '%s\n' "$calls" > "$calls_file"
    # Calls 1-2 are the pre-trigger dedup check and the main poll-loop's
    # bot-response check; both must stay empty so execution falls through
    # to the async-arrival grace poll (call 3) and its final re-poll
    # (call 4+).
    if [ "$calls" -ge 4 ]; then
      printf '[{"id":227,"created_at":"2026-01-01T00:00:02Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"To use Codex here, create an environment for this repo."}]\n'
    elif [ "$calls" -eq 3 ]; then
      printf '[{"id":226,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"If Codex has suggestions, it will comment; otherwise it will react with 👍 on this comment."}]\n'
    else
      printf '[]\n'
    fi
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_ACK_REPOLL_ENV_THEN_REACTION_GH
chmod +x "$_codex_ack_repoll_env_then_reaction_mock_dir/gh"

_codex_ack_repoll_env_then_reaction_output=""
_codex_ack_repoll_env_then_reaction_exit=0
PATH="$_codex_ack_repoll_env_then_reaction_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_ack_repoll_env_then_reaction_mock_dir/output.txt" 2>&1 || _codex_ack_repoll_env_then_reaction_exit=$?
_codex_ack_repoll_env_then_reaction_output="$(cat "$_codex_ack_repoll_env_then_reaction_mock_dir/output.txt")"
run_test "codex_ack_repoll_env_then_reaction_exit_unavailable" "2" "$_codex_ack_repoll_env_then_reaction_exit"
run_test "codex_ack_repoll_env_then_reaction_reason" "REASON=codex-github-environment-missing" \
  "$(printf '%s\n' "$_codex_ack_repoll_env_then_reaction_output" | grep "^REASON=")"
rm -rf "$_codex_ack_repoll_env_then_reaction_mock_dir"
unset _codex_ack_repoll_env_then_reaction_mock_dir _codex_ack_repoll_env_then_reaction_output _codex_ack_repoll_env_then_reaction_exit

# Reproduces PR-Agent advisory finding on PR #1490 (main-loop env-error
# override): the main poll loop recorded an environment setup error on its
# first iteration (SEEN_ENVIRONMENT_ERROR=1) but a later iteration's
# same-timestamp-or-older submitted review still exited APPROVED without
# checking that flag, silently discarding the recorded environment failure.
# Sequence: iteration 1 finds an environment-setup root comment -> iteration
# 2 finds no new comment but a clean current-head review AT THE SAME
# TIMESTAMP as the recorded environment error -> expect
# codex-github-environment-missing, not APPROVED (ties favor the non-clean
# evidence, per codex_response_requires_attention's tie-break principle).
# Covers all four APPROVED exit sites' shared guard, exercised here via the
# main poll loop. A strictly NEWER review is expected to supersede the
# stale environment error instead — see
# codex_main_loop_env_then_newer_review_supersedes below.
#
# The review body must reproduce a real CODEX_APPROVED_TEMPLATES entry
# (issue #1491's conservative-verdict-classifier implementation plan): the
# SEEN_ENVIRONMENT_ERROR-supersede check this scenario exercises lives
# INSIDE the `source == "review" && codex_response_is_approved` branch, so
# a body that does not exactly reproduce the template never reaches that
# check at all (it falls through to the unrecognized-format safe-fail
# instead) — silently defeating this scenario's own coverage rather than
# failing loudly, which is exactly why this fixture needed updating
# alongside the classifier redesign even though its own assertion never
# mentions "APPROVED".
_codex_main_loop_env_then_review_mock_dir="$(mktemp -d)"
printf '0\n' > "$_codex_main_loop_env_then_review_mock_dir/comment_calls"
printf '0\n' > "$_codex_main_loop_env_then_review_mock_dir/review_calls"
cat > "$_codex_main_loop_env_then_review_mock_dir/gh" <<'CODEX_MAIN_LOOP_ENV_THEN_REVIEW_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'mainloopenv1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":130,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    calls_file="$(dirname "$0")/review_calls"
    calls="$(cat "$calls_file")"
    calls=$((calls + 1))
    printf '%s\n' "$calls" > "$calls_file"
    if [ "$calls" -ge 2 ]; then
      jq -nc '[{submitted_at:"2026-01-01T00:00:01Z",commit_id:"mainloopenv1234567890",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'\''t find any major issues. Swish! **Reviewed commit:** `1111111111` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> [Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment \"@codex review\". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\". </details>")}]'
    else
      printf '[]\n'
    fi
    exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    calls_file="$(dirname "$0")/comment_calls"
    calls="$(cat "$calls_file")"
    calls=$((calls + 1))
    printf '%s\n' "$calls" > "$calls_file"
    if [ "$calls" -eq 2 ]; then
      printf '[{"id":230,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"To use Codex here, create an environment for this repo."}]\n'
    else
      printf '[]\n'
    fi
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_MAIN_LOOP_ENV_THEN_REVIEW_GH
chmod +x "$_codex_main_loop_env_then_review_mock_dir/gh"

_codex_main_loop_env_then_review_output=""
_codex_main_loop_env_then_review_exit=0
PATH="$_codex_main_loop_env_then_review_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 2 --max-retriggers 0 \
  >"$_codex_main_loop_env_then_review_mock_dir/output.txt" 2>&1 || _codex_main_loop_env_then_review_exit=$?
_codex_main_loop_env_then_review_output="$(cat "$_codex_main_loop_env_then_review_mock_dir/output.txt")"
run_test "codex_main_loop_env_then_review_exit_unavailable" "2" "$_codex_main_loop_env_then_review_exit"
run_test "codex_main_loop_env_then_review_reason" "REASON=codex-github-environment-missing" \
  "$(printf '%s\n' "$_codex_main_loop_env_then_review_output" | grep "^REASON=")"
rm -rf "$_codex_main_loop_env_then_review_mock_dir"
unset _codex_main_loop_env_then_review_mock_dir _codex_main_loop_env_then_review_output _codex_main_loop_env_then_review_exit

# Reproduces Codex finding on PR #1490 (P2, comment id 3787679406): the
# environment-error guard must not be permanently sticky — a genuinely
# fresh (strictly newer timestamp) current-head approved review must
# supersede a now-stale recorded environment error, so an operator fixing
# the Codex cloud environment mid-poll can recover within the same
# invocation. Sequence identical to codex_main_loop_env_then_review above,
# except the review's submitted_at is strictly newer than the env-error
# comment's created_at -> expect APPROVED, not environment-missing.
_codex_main_loop_env_then_newer_review_supersedes_mock_dir="$(mktemp -d)"
printf '0\n' > "$_codex_main_loop_env_then_newer_review_supersedes_mock_dir/comment_calls"
printf '0\n' > "$_codex_main_loop_env_then_newer_review_supersedes_mock_dir/review_calls"
cat > "$_codex_main_loop_env_then_newer_review_supersedes_mock_dir/gh" <<'CODEX_MAIN_LOOP_ENV_THEN_NEWER_REVIEW_SUPERSEDES_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'newerreview1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":132,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    calls_file="$(dirname "$0")/review_calls"
    calls="$(cat "$calls_file")"
    calls=$((calls + 1))
    printf '%s\n' "$calls" > "$calls_file"
    if [ "$calls" -ge 2 ]; then
      jq -nc '[{submitted_at:"2026-01-01T00:00:03Z",commit_id:"newerreview1234567890",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'\''t find any major issues. Swish! **Reviewed commit:** `dddddddddd` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> [Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment \"@codex review\". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\". </details>")}]'
    else
      printf '[]\n'
    fi
    exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    calls_file="$(dirname "$0")/comment_calls"
    calls="$(cat "$calls_file")"
    calls=$((calls + 1))
    printf '%s\n' "$calls" > "$calls_file"
    if [ "$calls" -eq 2 ]; then
      printf '[{"id":230,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"To use Codex here, create an environment for this repo."}]\n'
    else
      printf '[]\n'
    fi
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_MAIN_LOOP_ENV_THEN_NEWER_REVIEW_SUPERSEDES_GH
chmod +x "$_codex_main_loop_env_then_newer_review_supersedes_mock_dir/gh"

_codex_main_loop_env_then_newer_review_supersedes_output=""
_codex_main_loop_env_then_newer_review_supersedes_exit=0
PATH="$_codex_main_loop_env_then_newer_review_supersedes_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 2 --max-retriggers 0 \
  >"$_codex_main_loop_env_then_newer_review_supersedes_mock_dir/output.txt" 2>&1 || _codex_main_loop_env_then_newer_review_supersedes_exit=$?
_codex_main_loop_env_then_newer_review_supersedes_output="$(cat "$_codex_main_loop_env_then_newer_review_supersedes_mock_dir/output.txt")"
run_test "codex_main_loop_env_then_newer_review_supersedes_exit_clean" "0" "$_codex_main_loop_env_then_newer_review_supersedes_exit"
run_test "codex_main_loop_env_then_newer_review_supersedes_verdict" "VERDICT: APPROVED" \
  "$(printf '%s\n' "$_codex_main_loop_env_then_newer_review_supersedes_output" | grep "^VERDICT:")"
rm -rf "$_codex_main_loop_env_then_newer_review_supersedes_mock_dir"
unset _codex_main_loop_env_then_newer_review_supersedes_mock_dir _codex_main_loop_env_then_newer_review_supersedes_output _codex_main_loop_env_then_newer_review_supersedes_exit

# Reproduces Codex finding on PR #1490 (P1, comment id 3787679402): the
# codex_response_requires_attention tie-break helper (added in the prior
# cycle to fix unrecognized-format ties) checked only the approval pattern,
# so a mixed response containing BOTH an approval phrase and a blocking
# marker (e.g. "No blocking issues found. Must fix ...") was misclassified
# as a clean approval and lost the tie-break to a clean root comment,
# producing APPROVED instead of the classifier's blocking-first
# NEEDS_REVISION. Root comment is a clean approval; tied review body
# contains both an approval phrase and a blocking marker.
_codex_tied_mixed_blocking_review_wins_mock_dir="$(mktemp -d)"
cat > "$_codex_tied_mixed_blocking_review_wins_mock_dir/gh" <<'CODEX_TIED_MIXED_BLOCKING_REVIEW_WINS_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'deadb00d12345678\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":133,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[{"submitted_at":"2026-01-01T00:00:01Z","commit_id":"deadb00d12345678","user":{"login":"chatgpt-codex-connector[bot]"},"body":"No blocking issues found. Must fix the typo on line 4."}]\n'
    exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":234,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"Codex Review: Didn'\''t find any major issues.\\n\\n**Reviewed commit:** `deadb00d1234`"}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_TIED_MIXED_BLOCKING_REVIEW_WINS_GH
chmod +x "$_codex_tied_mixed_blocking_review_wins_mock_dir/gh"

_codex_tied_mixed_blocking_review_wins_output=""
_codex_tied_mixed_blocking_review_wins_exit=0
PATH="$_codex_tied_mixed_blocking_review_wins_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_tied_mixed_blocking_review_wins_mock_dir/output.txt" 2>&1 || _codex_tied_mixed_blocking_review_wins_exit=$?
_codex_tied_mixed_blocking_review_wins_output="$(cat "$_codex_tied_mixed_blocking_review_wins_mock_dir/output.txt")"
run_test "codex_tied_mixed_blocking_review_wins_exit_needs_revision" "2" "$_codex_tied_mixed_blocking_review_wins_exit"
run_test "codex_tied_mixed_blocking_review_wins_verdict" "VERDICT: ESCALATE — Codex finding has no stable review-thread identifier or no identifiable matching review-thread conversation" \
  "$(printf '%s\n' "$_codex_tied_mixed_blocking_review_wins_output" | grep "^VERDICT:")"
rm -rf "$_codex_tied_mixed_blocking_review_wins_mock_dir"
unset _codex_tied_mixed_blocking_review_wins_mock_dir _codex_tied_mixed_blocking_review_wins_output _codex_tied_mixed_blocking_review_wins_exit

# Reproduces Codex finding on PR #1490 (P1, comment id 3787786942): a
# submitted review body that exceeds a pipe buffer's capacity (well within
# GitHub's ~64KB per-comment limit) causes `jq ... | head -c 5000` to SIGPIPE
# jq once `head` closes its read end after 5000 bytes; under `set -euo
# pipefail` this aborts the whole script with exit 141 before any VERDICT
# line is emitted. Truncation now happens inside jq (codepoint slice)
# instead of via a piped `head`, eliminating the SIGPIPE entirely. Body is
# built via jq's own string-repeat operator (200000 chars) rather than a
# large literal in this file or a python3 dependency.
#
# Retargeted for issue #1491's conservative-verdict-classifier redesign:
# this body's leading "No blocking issues found." prefix was a pre-plan
# block-list vocabulary artifact, not a reproduction of
# CODEX_APPROVED_TEMPLATES' whole-body exact template, so it now correctly
# safe-fails to NEEDS_REVISION. The scenario's actual purpose — proving a
# large (~200,000-character) response completes without a SIGPIPE crash —
# is unaffected by the verdict changing; only the disposition changes.
_codex_long_review_body_no_sigpipe_mock_dir="$(mktemp -d)"
cat > "$_codex_long_review_body_no_sigpipe_mock_dir/gh" <<'CODEX_LONG_REVIEW_BODY_NO_SIGPIPE_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'longbody1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":140,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    jq -nc '[{submitted_at:"2026-01-01T00:00:01Z",commit_id:"longbody1234567890",user:{login:"chatgpt-codex-connector[bot]"},body:("No blocking issues found. " + ("x" * 200000))}]'
    exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_LONG_REVIEW_BODY_NO_SIGPIPE_GH
chmod +x "$_codex_long_review_body_no_sigpipe_mock_dir/gh"

_codex_long_review_body_no_sigpipe_output=""
_codex_long_review_body_no_sigpipe_exit=0
PATH="$_codex_long_review_body_no_sigpipe_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_long_review_body_no_sigpipe_mock_dir/output.txt" 2>&1 || _codex_long_review_body_no_sigpipe_exit=$?
_codex_long_review_body_no_sigpipe_output="$(cat "$_codex_long_review_body_no_sigpipe_mock_dir/output.txt")"
run_test "codex_long_review_body_no_sigpipe_exit_needs_revision" "2" "$_codex_long_review_body_no_sigpipe_exit"
run_test "codex_long_review_body_no_sigpipe_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_long_review_body_no_sigpipe_output" | grep "^VERDICT:")"
rm -rf "$_codex_long_review_body_no_sigpipe_mock_dir"
unset _codex_long_review_body_no_sigpipe_mock_dir _codex_long_review_body_no_sigpipe_output _codex_long_review_body_no_sigpipe_exit

# Reproduces Codex finding on PR #1490 (P1, comment id 3787786943): within a
# single poll, a clean submitted review at T1 and a newer environment-setup
# root comment at T2 were combined by unconditionally preferring the review
# (since it wasn't competing against a SHA-pinned terminal comment), so the
# newer setup failure never had a chance to be recorded as
# SEEN_ENVIRONMENT_ERROR and the run returned APPROVED. Root comment (env
# error) is strictly newer than the review in this fixture -> expect
# codex-github-environment-missing, not APPROVED.
_codex_same_poll_newer_env_error_wins_mock_dir="$(mktemp -d)"
cat > "$_codex_same_poll_newer_env_error_wins_mock_dir/gh" <<'CODEX_SAME_POLL_NEWER_ENV_ERROR_WINS_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'samepoll1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":141,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[{"submitted_at":"2026-01-01T00:00:01Z","commit_id":"samepoll1234567890","user":{"login":"chatgpt-codex-connector[bot]"},"body":"No blocking issues found."}]\n'
    exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":242,"created_at":"2026-01-01T00:00:02Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"To use Codex here, create an environment for this repo."}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_SAME_POLL_NEWER_ENV_ERROR_WINS_GH
chmod +x "$_codex_same_poll_newer_env_error_wins_mock_dir/gh"

_codex_same_poll_newer_env_error_wins_output=""
_codex_same_poll_newer_env_error_wins_exit=0
PATH="$_codex_same_poll_newer_env_error_wins_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_same_poll_newer_env_error_wins_mock_dir/output.txt" 2>&1 || _codex_same_poll_newer_env_error_wins_exit=$?
_codex_same_poll_newer_env_error_wins_output="$(cat "$_codex_same_poll_newer_env_error_wins_mock_dir/output.txt")"
run_test "codex_same_poll_newer_env_error_wins_exit_unavailable" "2" "$_codex_same_poll_newer_env_error_wins_exit"
run_test "codex_same_poll_newer_env_error_wins_reason" "REASON=codex-github-environment-missing" \
  "$(printf '%s\n' "$_codex_same_poll_newer_env_error_wins_output" | grep "^REASON=")"
rm -rf "$_codex_same_poll_newer_env_error_wins_mock_dir"
unset _codex_same_poll_newer_env_error_wins_mock_dir _codex_same_poll_newer_env_error_wins_output _codex_same_poll_newer_env_error_wins_exit

# Reproduces Codex finding on PR #1490 (P2, comment id 3787786945): when the
# same comments fetch contains an environment-setup error at T1 followed by
# a plain acknowledgement at T2, codex_scan_comment_evidence previously kept
# only the LATEST comment overall (the acknowledgement), losing the
# actionable setup-error text. Combined with a thumbs-up reaction, this
# produced codex-github-reaction-without-review instead of
# codex-github-environment-missing. Async-arrival grace path: env-error at
# T1 and acknowledgement at T2 both appear in the same async-arrival poll's
# comment fetch, plus a thumbs-up reaction on the trigger comment.
_codex_env_error_survives_later_ack_mock_dir="$(mktemp -d)"
cat > "$_codex_env_error_survives_later_ack_mock_dir/gh" <<'CODEX_ENV_ERROR_SURVIVES_LATER_ACK_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'ackenverr1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":142,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[{"content":"+1","user":{"login":"chatgpt-codex-connector[bot]"}}]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":243,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"To use Codex here, create an environment for this repo."},{"id":244,"created_at":"2026-01-01T00:00:02Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"If Codex has suggestions, it will comment; otherwise it will react with \xf0\x9f\x91\x8d on this comment."}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_ENV_ERROR_SURVIVES_LATER_ACK_GH
chmod +x "$_codex_env_error_survives_later_ack_mock_dir/gh"

_codex_env_error_survives_later_ack_output=""
_codex_env_error_survives_later_ack_exit=0
PATH="$_codex_env_error_survives_later_ack_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_env_error_survives_later_ack_mock_dir/output.txt" 2>&1 || _codex_env_error_survives_later_ack_exit=$?
_codex_env_error_survives_later_ack_output="$(cat "$_codex_env_error_survives_later_ack_mock_dir/output.txt")"
run_test "codex_env_error_survives_later_ack_exit_unavailable" "2" "$_codex_env_error_survives_later_ack_exit"
run_test "codex_env_error_survives_later_ack_reason" "REASON=codex-github-environment-missing" \
  "$(printf '%s\n' "$_codex_env_error_survives_later_ack_output" | grep "^REASON=")"
rm -rf "$_codex_env_error_survives_later_ack_mock_dir"
unset _codex_env_error_survives_later_ack_mock_dir _codex_env_error_survives_later_ack_output _codex_env_error_survives_later_ack_exit

# Reproduces Codex finding on PR #1490 (P1, comment id 3787868727): a clean
# SHA-pinned terminal root comment at T1 and a strictly newer
# environment-setup-error comment at T2, both present in the same comments
# fetch. codex_combine_terminal_evidence previously chose the terminal
# comment unconditionally whenever no submitted review was present,
# discarding the newer environment error entirely (that branch never
# considered it). No review from the reviews endpoint -> expect
# codex-github-environment-missing, not APPROVED.
_codex_terminal_comment_vs_newer_env_error_mock_dir="$(mktemp -d)"
cat > "$_codex_terminal_comment_vs_newer_env_error_mock_dir/gh" <<'CODEX_TERMINAL_COMMENT_VS_NEWER_ENV_ERROR_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'deadf00d12345678\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":150,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":250,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"Codex Review: Didn'\''t find any major issues.\\n\\n**Reviewed commit:** `deadf00d1234`"},{"id":251,"created_at":"2026-01-01T00:00:02Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"To use Codex here, create an environment for this repo."}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_TERMINAL_COMMENT_VS_NEWER_ENV_ERROR_GH
chmod +x "$_codex_terminal_comment_vs_newer_env_error_mock_dir/gh"

_codex_terminal_comment_vs_newer_env_error_output=""
_codex_terminal_comment_vs_newer_env_error_exit=0
PATH="$_codex_terminal_comment_vs_newer_env_error_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_terminal_comment_vs_newer_env_error_mock_dir/output.txt" 2>&1 || _codex_terminal_comment_vs_newer_env_error_exit=$?
_codex_terminal_comment_vs_newer_env_error_output="$(cat "$_codex_terminal_comment_vs_newer_env_error_mock_dir/output.txt")"
run_test "codex_terminal_comment_vs_newer_env_error_exit_unavailable" "2" "$_codex_terminal_comment_vs_newer_env_error_exit"
run_test "codex_terminal_comment_vs_newer_env_error_reason" "REASON=codex-github-environment-missing" \
  "$(printf '%s\n' "$_codex_terminal_comment_vs_newer_env_error_output" | grep "^REASON=")"
rm -rf "$_codex_terminal_comment_vs_newer_env_error_mock_dir"
unset _codex_terminal_comment_vs_newer_env_error_mock_dir _codex_terminal_comment_vs_newer_env_error_output _codex_terminal_comment_vs_newer_env_error_exit

# Reproduces Codex finding on PR #1490 (P1, comment id 3787868733): only
# submitted review bodies were sliced inside jq; a SHA-pinned root-comment
# body large enough to exceed a pipe buffer's capacity (well within
# GitHub's ~64KB per-comment limit) still passed through
# `printf | head -c 10000` in the main loop and all 3 async paths,
# triggering the same SIGPIPE/exit-141 crash under `set -euo pipefail`.
# All 4 sites now truncate via `jq -Rrs '.[0:10000]'`, which slurps its
# entire stdin before producing output so the writer can never receive
# SIGPIPE regardless of input size.
#
# Retargeted for issue #1491's conservative-verdict-classifier redesign:
# this body (verdict sentence + 200,000 filler characters + Reviewed-commit
# marker, no footer) does not reproduce CODEX_APPROVED_TEMPLATES' whole-body
# exact template, so it now correctly safe-fails to NEEDS_REVISION. The
# scenario's actual purpose — proving a large root-comment body completes
# without a SIGPIPE crash — is unaffected by the verdict changing; only the
# disposition changes.
_codex_long_root_comment_no_sigpipe_mock_dir="$(mktemp -d)"
cat > "$_codex_long_root_comment_no_sigpipe_mock_dir/gh" <<'CODEX_LONG_ROOT_COMMENT_NO_SIGPIPE_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'deadf00d12345678\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":151,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    jq -nc '[{id:260,created_at:"2026-01-01T00:00:01Z",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'"'"'t find any major issues.\n\n" + ("x" * 200000) + "\n\n**Reviewed commit:** `deadf00d1234`")}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_LONG_ROOT_COMMENT_NO_SIGPIPE_GH
chmod +x "$_codex_long_root_comment_no_sigpipe_mock_dir/gh"

_codex_long_root_comment_no_sigpipe_output=""
_codex_long_root_comment_no_sigpipe_exit=0
PATH="$_codex_long_root_comment_no_sigpipe_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_long_root_comment_no_sigpipe_mock_dir/output.txt" 2>&1 || _codex_long_root_comment_no_sigpipe_exit=$?
_codex_long_root_comment_no_sigpipe_output="$(cat "$_codex_long_root_comment_no_sigpipe_mock_dir/output.txt")"
run_test "codex_long_root_comment_no_sigpipe_exit_needs_revision" "2" "$_codex_long_root_comment_no_sigpipe_exit"
run_test "codex_long_root_comment_no_sigpipe_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_long_root_comment_no_sigpipe_output" | grep "^VERDICT:")"
rm -rf "$_codex_long_root_comment_no_sigpipe_mock_dir"
unset _codex_long_root_comment_no_sigpipe_mock_dir _codex_long_root_comment_no_sigpipe_output _codex_long_root_comment_no_sigpipe_exit

# Reproduces Codex finding on PR #1490 (P1, comment id 3787943162): a
# SHA-pinned terminal root comment reporting a blocking finding at T1,
# followed by a non-terminal environment-setup comment at T2 in the same
# fetch. codex_combine_terminal_evidence's final environment-error override
# previously replaced the blocking COMBINED_BODY whenever it was not
# strictly newer than the environment-error comment, silently hiding the
# blocking finding behind an "unavailable" verdict. Blocking terminal
# evidence must now win outright, regardless of timing. No review from the
# reviews endpoint -> expect NEEDS_REVISION, not environment-missing.
_codex_blocking_terminal_beats_env_error_mock_dir="$(mktemp -d)"
cat > "$_codex_blocking_terminal_beats_env_error_mock_dir/gh" <<'CODEX_BLOCKING_TERMINAL_BEATS_ENV_ERROR_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'beadf00d1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":160,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":270,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"Blocking issues: must fix the null check.\\n\\n**Reviewed commit:** `beadf00d1234`"},{"id":271,"created_at":"2026-01-01T00:00:02Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"To use Codex here, create an environment for this repo."}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_BLOCKING_TERMINAL_BEATS_ENV_ERROR_GH
chmod +x "$_codex_blocking_terminal_beats_env_error_mock_dir/gh"

_codex_blocking_terminal_beats_env_error_output=""
_codex_blocking_terminal_beats_env_error_exit=0
PATH="$_codex_blocking_terminal_beats_env_error_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_blocking_terminal_beats_env_error_mock_dir/output.txt" 2>&1 || _codex_blocking_terminal_beats_env_error_exit=$?
_codex_blocking_terminal_beats_env_error_output="$(cat "$_codex_blocking_terminal_beats_env_error_mock_dir/output.txt")"
run_test "codex_blocking_terminal_beats_env_error_exit_needs_revision" "2" "$_codex_blocking_terminal_beats_env_error_exit"
run_test "codex_blocking_terminal_beats_env_error_verdict" "VERDICT: ESCALATE — Codex finding has no stable review-thread identifier or no identifiable matching review-thread conversation" \
  "$(printf '%s\n' "$_codex_blocking_terminal_beats_env_error_output" | grep "^VERDICT:")"
rm -rf "$_codex_blocking_terminal_beats_env_error_mock_dir"
unset _codex_blocking_terminal_beats_env_error_mock_dir _codex_blocking_terminal_beats_env_error_output _codex_blocking_terminal_beats_env_error_exit

# Reproduces Codex finding on PR #1490 (P2, comment id 3787943163): a
# SHA-pinned terminal root review whose blocking finding text quotes the
# environment-setup sentence verbatim (e.g. flagging stale docs that
# reproduce it) was misclassified as an environment-setup error by the
# unanchored substring matcher, suppressing NEEDS_REVISION. A SHA-pinned
# TERMINAL comment is now never classified as an environment error,
# regardless of its text content -> expect NEEDS_REVISION.
_codex_quoted_setup_sentence_in_blocking_finding_mock_dir="$(mktemp -d)"
cat > "$_codex_quoted_setup_sentence_in_blocking_finding_mock_dir/gh" <<'CODEX_QUOTED_SETUP_SENTENCE_IN_BLOCKING_FINDING_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'cafebabe1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":161,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":280,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"Blocking issues: docs must not claim: To use Codex here, create an environment for this repo.\\n\\n**Reviewed commit:** `cafebabe1234`"}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_QUOTED_SETUP_SENTENCE_IN_BLOCKING_FINDING_GH
chmod +x "$_codex_quoted_setup_sentence_in_blocking_finding_mock_dir/gh"

_codex_quoted_setup_sentence_in_blocking_finding_output=""
_codex_quoted_setup_sentence_in_blocking_finding_exit=0
PATH="$_codex_quoted_setup_sentence_in_blocking_finding_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_quoted_setup_sentence_in_blocking_finding_mock_dir/output.txt" 2>&1 || _codex_quoted_setup_sentence_in_blocking_finding_exit=$?
_codex_quoted_setup_sentence_in_blocking_finding_output="$(cat "$_codex_quoted_setup_sentence_in_blocking_finding_mock_dir/output.txt")"
run_test "codex_quoted_setup_sentence_in_blocking_finding_exit_needs_revision" "2" "$_codex_quoted_setup_sentence_in_blocking_finding_exit"
run_test "codex_quoted_setup_sentence_in_blocking_finding_verdict" "VERDICT: ESCALATE — Codex finding has no stable review-thread identifier or no identifiable matching review-thread conversation" \
  "$(printf '%s\n' "$_codex_quoted_setup_sentence_in_blocking_finding_output" | grep "^VERDICT:")"
rm -rf "$_codex_quoted_setup_sentence_in_blocking_finding_mock_dir"
unset _codex_quoted_setup_sentence_in_blocking_finding_mock_dir _codex_quoted_setup_sentence_in_blocking_finding_output _codex_quoted_setup_sentence_in_blocking_finding_exit

# Reproduces Codex finding on PR #1490 (P1, comment id 3788008326): when
# multiple current-head reviews share GitHub's second-resolution
# submitted_at timestamp, `sort_by(.submitted_at) | last` discarded every
# response except whichever the API happened to return last, regardless of
# content. A blocking review returned BEFORE a tied clean review in the
# array silently produced APPROVED. The review-poll jq queries now select
# every review tied at the latest timestamp and codex_select_review_evidence
# picks the one requiring attention, if any. Fixture: blocking review first
# in the array, clean review second, both tied at the same timestamp.
_codex_tied_reviews_blocking_first_survives_mock_dir="$(mktemp -d)"
cat > "$_codex_tied_reviews_blocking_first_survives_mock_dir/gh" <<'CODEX_TIED_REVIEWS_BLOCKING_FIRST_SURVIVES_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'deadbeef1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":170,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[{"submitted_at":"2026-01-01T00:00:01Z","commit_id":"deadbeef1234567890","user":{"login":"chatgpt-codex-connector[bot]"},"body":"Blocking issues: must fix the leak."},{"submitted_at":"2026-01-01T00:00:01Z","commit_id":"deadbeef1234567890","user":{"login":"chatgpt-codex-connector[bot]"},"body":"No blocking issues found."}]\n'
    exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_TIED_REVIEWS_BLOCKING_FIRST_SURVIVES_GH
chmod +x "$_codex_tied_reviews_blocking_first_survives_mock_dir/gh"

_codex_tied_reviews_blocking_first_survives_output=""
_codex_tied_reviews_blocking_first_survives_exit=0
PATH="$_codex_tied_reviews_blocking_first_survives_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_tied_reviews_blocking_first_survives_mock_dir/output.txt" 2>&1 || _codex_tied_reviews_blocking_first_survives_exit=$?
_codex_tied_reviews_blocking_first_survives_output="$(cat "$_codex_tied_reviews_blocking_first_survives_mock_dir/output.txt")"
run_test "codex_tied_reviews_blocking_first_survives_exit_needs_revision" "2" "$_codex_tied_reviews_blocking_first_survives_exit"
run_test "codex_tied_reviews_blocking_first_survives_verdict" "VERDICT: ESCALATE — Codex finding has no stable review-thread identifier or no identifiable matching review-thread conversation" \
  "$(printf '%s\n' "$_codex_tied_reviews_blocking_first_survives_output" | grep "^VERDICT:")"
rm -rf "$_codex_tied_reviews_blocking_first_survives_mock_dir"
unset _codex_tied_reviews_blocking_first_survives_mock_dir _codex_tied_reviews_blocking_first_survives_output _codex_tied_reviews_blocking_first_survives_exit

# Reproduces Codex finding on PR #1490 (P2, comment id 3788008327): only
# environment-error ancillary comments were retained/compared independently
# — usage-limit comments were not, so an older clean current-head review
# and a newer root comment reporting exhausted Codex usage silently
# resolved to APPROVED instead of the configured unavailable policy.
# codex_scan_comment_evidence and the final override in
# codex_combine_terminal_evidence now treat usage-limit comments the same
# way as environment-error comments.
_codex_older_review_vs_newer_usage_limit_mock_dir="$(mktemp -d)"
cat > "$_codex_older_review_vs_newer_usage_limit_mock_dir/gh" <<'CODEX_OLDER_REVIEW_VS_NEWER_USAGE_LIMIT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'facefeed1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":180,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[{"submitted_at":"2026-01-01T00:00:01Z","commit_id":"facefeed1234567890","user":{"login":"chatgpt-codex-connector[bot]"},"body":"No blocking issues found."}]\n'
    exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":290,"created_at":"2026-01-01T00:00:02Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"You have reached your Codex usage limits for code reviews."}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_OLDER_REVIEW_VS_NEWER_USAGE_LIMIT_GH
chmod +x "$_codex_older_review_vs_newer_usage_limit_mock_dir/gh"

_codex_older_review_vs_newer_usage_limit_output=""
_codex_older_review_vs_newer_usage_limit_exit=0
PATH="$_codex_older_review_vs_newer_usage_limit_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_older_review_vs_newer_usage_limit_mock_dir/output.txt" 2>&1 || _codex_older_review_vs_newer_usage_limit_exit=$?
_codex_older_review_vs_newer_usage_limit_output="$(cat "$_codex_older_review_vs_newer_usage_limit_mock_dir/output.txt")"
run_test "codex_older_review_vs_newer_usage_limit_exit_unavailable" "3" "$_codex_older_review_vs_newer_usage_limit_exit"
run_test "codex_older_review_vs_newer_usage_limit_reason" "REASON=codex-github-usage-limit" \
  "$(printf '%s\n' "$_codex_older_review_vs_newer_usage_limit_output" | grep "^REASON=")"
rm -rf "$_codex_older_review_vs_newer_usage_limit_mock_dir"
unset _codex_older_review_vs_newer_usage_limit_mock_dir _codex_older_review_vs_newer_usage_limit_output _codex_older_review_vs_newer_usage_limit_exit

# Reproduces Codex finding on PR #1490 (P1, comment id 3788078189): when
# two current-head terminal root comments share GitHub's second-resolution
# timestamp, codex_scan_comment_evidence previously overwrote
# COMMENT_TERMINAL_BODY unconditionally on every terminal comment seen,
# regardless of content. A blocking terminal comment followed by a tied
# clean terminal comment silently produced APPROVED. The not-a-clean-
# approval-first tie-break now decides which tied terminal comment is
# tracked. Fixture: blocking terminal comment first, clean terminal
# comment second, both tied at the same timestamp, no review.
_codex_tied_terminal_comments_blocking_survives_mock_dir="$(mktemp -d)"
cat > "$_codex_tied_terminal_comments_blocking_survives_mock_dir/gh" <<'CODEX_TIED_TERMINAL_COMMENTS_BLOCKING_SURVIVES_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'aceface1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":190,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":300,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"Blocking issues: must fix the leak.\\n\\n**Reviewed commit:** `aceface1234`"},{"id":301,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"Codex Review: Didn'\''t find any major issues.\\n\\n**Reviewed commit:** `aceface1234`"}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_TIED_TERMINAL_COMMENTS_BLOCKING_SURVIVES_GH
chmod +x "$_codex_tied_terminal_comments_blocking_survives_mock_dir/gh"

_codex_tied_terminal_comments_blocking_survives_output=""
_codex_tied_terminal_comments_blocking_survives_exit=0
PATH="$_codex_tied_terminal_comments_blocking_survives_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_tied_terminal_comments_blocking_survives_mock_dir/output.txt" 2>&1 || _codex_tied_terminal_comments_blocking_survives_exit=$?
_codex_tied_terminal_comments_blocking_survives_output="$(cat "$_codex_tied_terminal_comments_blocking_survives_mock_dir/output.txt")"
run_test "codex_tied_terminal_comments_blocking_survives_exit_needs_revision" "2" "$_codex_tied_terminal_comments_blocking_survives_exit"
run_test "codex_tied_terminal_comments_blocking_survives_verdict" "VERDICT: ESCALATE — Codex finding has no stable review-thread identifier or no identifiable matching review-thread conversation" \
  "$(printf '%s\n' "$_codex_tied_terminal_comments_blocking_survives_output" | grep "^VERDICT:")"
rm -rf "$_codex_tied_terminal_comments_blocking_survives_mock_dir"
unset _codex_tied_terminal_comments_blocking_survives_mock_dir _codex_tied_terminal_comments_blocking_survives_output _codex_tied_terminal_comments_blocking_survives_exit

# Reproduces Codex finding on PR #1490 (P2, comment id 3788078191): the
# usage-limit check ran before the blocking check in every verdict path, so
# a current-head submitted review whose blocking finding text mentions
# "usage limit" as part of the finding itself (e.g. flagging stale docs
# that describe it) was misrouted to an UNAVAILABLE/usage-limit verdict
# before the blocking classifier could run, hiding the actionable finding.
# Blocking is now checked first in every verdict path.
_codex_blocking_text_mentions_usage_limit_mock_dir="$(mktemp -d)"
cat > "$_codex_blocking_text_mentions_usage_limit_mock_dir/gh" <<'CODEX_BLOCKING_TEXT_MENTIONS_USAGE_LIMIT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'baadf00d1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":191,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[{"submitted_at":"2026-01-01T00:00:01Z","commit_id":"baadf00d1234567890","user":{"login":"chatgpt-codex-connector[bot]"},"body":"Blocking issues: docs incorrectly describe the Codex usage limit for code reviews."}]\n'
    exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_BLOCKING_TEXT_MENTIONS_USAGE_LIMIT_GH
chmod +x "$_codex_blocking_text_mentions_usage_limit_mock_dir/gh"

_codex_blocking_text_mentions_usage_limit_output=""
_codex_blocking_text_mentions_usage_limit_exit=0
PATH="$_codex_blocking_text_mentions_usage_limit_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_blocking_text_mentions_usage_limit_mock_dir/output.txt" 2>&1 || _codex_blocking_text_mentions_usage_limit_exit=$?
_codex_blocking_text_mentions_usage_limit_output="$(cat "$_codex_blocking_text_mentions_usage_limit_mock_dir/output.txt")"
run_test "codex_blocking_text_mentions_usage_limit_exit_needs_revision" "2" "$_codex_blocking_text_mentions_usage_limit_exit"
run_test "codex_blocking_text_mentions_usage_limit_verdict" "VERDICT: ESCALATE — Codex finding has no stable review-thread identifier or no identifiable matching review-thread conversation" \
  "$(printf '%s\n' "$_codex_blocking_text_mentions_usage_limit_output" | grep "^VERDICT:")"
rm -rf "$_codex_blocking_text_mentions_usage_limit_mock_dir"
unset _codex_blocking_text_mentions_usage_limit_mock_dir _codex_blocking_text_mentions_usage_limit_output _codex_blocking_text_mentions_usage_limit_exit

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Tests: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
