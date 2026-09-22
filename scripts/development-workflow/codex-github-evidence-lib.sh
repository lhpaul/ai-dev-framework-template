#!/usr/bin/env bash
# codex-github-evidence-lib.sh — shared Codex GitHub review-thread evidence
# helpers, sourced by both codex-github-reviewer.sh (the companion
# trigger/poll/parse script) and pr-review-loop.sh (run_codex_github_review).
#
# #1757: "Resolved Codex findings no longer block reviewer loop." This
# library exists so both callers use exactly one implementation of
# applicability-aware Codex review-thread counting, rather than two
# implementations that could silently diverge.
#
# Rules for this file (must remain safe to `source` under `set -euo pipefail`
# from either caller):
#   - No top-level side effects (no argument parsing, no `exit`).
#   - Every function takes its inputs as explicit parameters — no reads of
#     caller-specific globals (companion globals such as $OWNER/$REPO or loop
#     locals such as $repo/$graphql_bot_login must never be read here).
#   - Every function's contract (parameters, stdout shape, return codes) is
#     documented directly above it.

# codex_review_thread_evidence_counts <owner> <repo_name> <pr_number> \
#     <graphql_bot_login> <mode> [max_pages]
#
#   mode   : strict | provisional; any other value falls back to strict,
#            matching check_unresolved_threads (pr-review-loop.sh)
#   stdout : "<strict_unresolved>\t<cleared>\t<provisional_relaxed>"
#            (tab-separated, always exactly three fields)
#   return : 0 success | 3 scan/pagination failure (unchanged companion
#            contract)
#
# Counts Codex-authored (first-comment author == <graphql_bot_login>)
# review-thread conversations on the live pull-request revision, over
# non-outdated threads only:
#
#   - "cleared"            : the thread is GitHub-resolved (isResolved) or
#                             the bot self-marked it addressed ("✅
#                             Addressed" in the first comment). A resolved
#                             Codex finding is excluded here regardless of
#                             applicability, per #1757 spec Business Rule 2
#                             ("Resolved Codex review conversations are
#                             excluded from fallback, existing-finding, and
#                             stale-finding blocker counts, even if their
#                             comments remain visible or re-anchored on the
#                             diff").
#   - inapplicable          : not cleared, but the thread's owning review is
#                             DISMISSED, or that review's commit does not
#                             equal the live head. Excluded from both
#                             buckets below (neither a current blocker nor
#                             "cleared" — it simply is not evidence for the
#                             live revision). Per #1757 spec Business Rule 1:
#                             "A conversation is applicable only when its
#                             Codex review is current and not dismissed and
#                             its review revision equals the live
#                             pull-request revision." When the owning
#                             review's commit cannot be read at all, the
#                             thread is treated as applicable (fails closed
#                             toward still counting as a blocker, never
#                             toward silently clearing one).
#   - "strict_unresolved"   : not cleared, and applicable. No relaxation is
#                             ever applied to this field regardless of mode.
#   - "provisional_relaxed" : the subset of strict_unresolved threads whose
#                             LAST comment was authored by a non-bot after
#                             the PR's current head-commit committedDate
#                             (issue #1508's "fixed and replied to, but not
#                             yet resolved" relaxation). Always 0 in strict
#                             mode, where the query does not fetch the
#                             lastComment/committedDate fields at all.
#
# Caller mapping (both preserve their existing semantics exactly):
#   - Companion pre-trigger check (codex-github-reviewer.sh): call with
#     mode=provisional; unresolved = strict_unresolved - provisional_relaxed,
#     cleared = cleared + provisional_relaxed (algebraically identical to the
#     companion's pre-#1757 counts).
#   - Loop phase 1 / exit-1 recount (pr-review-loop.sh
#     run_codex_github_review): call with mode=strict; use strict_unresolved
#     alone. Never read provisional_relaxed there.
codex_review_thread_evidence_counts() {
  local owner="$1"
  local repo_name="$2"
  local pr_number="$3"
  local graphql_bot_login="$4"
  local mode="$5"
  local max_pages="${6:-20}"

  case "$mode" in
    provisional) ;;
    *) mode="strict" ;;
  esac

  local thread_tmpfile thread_stderr cursor page
  local strict_unresolved=0
  local cleared=0
  local provisional_relaxed=0
  thread_tmpfile=$(mktemp)
  thread_stderr=$(mktemp)
  cursor=""
  page=0

  while :; do
    page=$((page + 1))
    if [ "$page" -gt "$max_pages" ]; then
      rm -f "$thread_tmpfile" "$thread_stderr"
      echo "ERROR: codex_review_thread_evidence_counts: exceeded $max_pages pages for PR #$pr_number" >&2
      return 3
    fi

    local -a gh_graphql_args
    gh_graphql_args=(api graphql -f owner="$owner" -f repo="$repo_name" -F number="$pr_number")
    if [ -n "$cursor" ]; then
      gh_graphql_args+=(-f cursor="$cursor")
    fi

    : > "$thread_stderr"
    local page_unresolved page_cleared page_relaxed has_next end_cursor
    if ! gh "${gh_graphql_args[@]}" \
      -f query='query($owner:String!, $repo:String!, $number:Int!, $cursor:String) {
        repository(owner:$owner, name:$repo) {
          pullRequest(number:$number) {
            headRefOid
            headRef {
              target {
                ... on Commit { committedDate }
              }
            }
            reviewThreads(first:100, after:$cursor) {
              pageInfo { hasNextPage endCursor }
              nodes {
                isResolved
                isOutdated
                firstComment: comments(first:1) {
                  nodes {
                    author { login }
                    body
                    pullRequestReview {
                      state
                      commit { oid }
                    }
                  }
                }
                lastComment: comments(last:1) {
                  nodes {
                    author { login }
                    createdAt
                  }
                }
              }
            }
          }
        }
      }' 2>"$thread_stderr" \
      | jq -r --arg bot "$graphql_bot_login" --arg mode "$mode" '
          .data.repository.pullRequest as $pr
          | ($pr.headRefOid // "") as $head_oid
          | ($pr.headRef.target.committedDate // "") as $head_date
          | ($pr.reviewThreads.pageInfo.hasNextPage // false) as $has_next
          | ($pr.reviewThreads.pageInfo.endCursor // "") as $end_cursor
          | [
              $pr.reviewThreads.nodes[]?
              | select((.isOutdated // false) == false)
              | (.firstComment.nodes[0].author.login // "") as $first_author
              | select($first_author == $bot)
              | (.firstComment.nodes[0].body // "") as $first_body
              | (.firstComment.nodes[0].pullRequestReview.state // "") as $review_state
              | (.firstComment.nodes[0].pullRequestReview.commit.oid // "") as $review_oid
              | (.lastComment.nodes[0].author.login // "") as $last_author
              | (.lastComment.nodes[0].createdAt // "") as $last_created
              | ((.isResolved // false) or ($first_body | test("✅ Addressed"))) as $cleared
              # Fail closed when the owning review commit cannot be read at
              # all: treat as applicable rather than silently excluding it.
              | (($review_state != "DISMISSED") and ($review_oid == "" or $review_oid == $head_oid)) as $applicable
              | ($mode == "provisional" and ($head_date != "") and ($last_author != "") and ($last_author != $bot) and ($last_created != "") and ($last_created > $head_date)) as $relaxed
              | { cleared: $cleared, applicable: $applicable, relaxed: $relaxed }
            ] as $threads
          | ($threads | map(select(.cleared)) | length) as $cleared_count
          | ($threads | map(select((.cleared | not) and .applicable)) | length) as $unresolved_count
          | ($threads | map(select((.cleared | not) and .applicable and .relaxed)) | length) as $relaxed_count
          | [$unresolved_count, $cleared_count, $relaxed_count, $has_next, $end_cursor] | @tsv' \
      > "$thread_tmpfile"; then
      local thread_err
      thread_err=$(cat "$thread_stderr")
      rm -f "$thread_tmpfile" "$thread_stderr"
      echo "ERROR: codex_review_thread_evidence_counts: failed to fetch or parse Codex review threads for PR #$pr_number: $thread_err" >&2
      return 3
    fi

    IFS=$'\t' read -r page_unresolved page_cleared page_relaxed has_next end_cursor < "$thread_tmpfile"
    strict_unresolved=$((strict_unresolved + page_unresolved))
    cleared=$((cleared + page_cleared))
    provisional_relaxed=$((provisional_relaxed + page_relaxed))

    if [ "$has_next" != "true" ]; then
      break
    fi
    if [ -z "$end_cursor" ]; then
      rm -f "$thread_tmpfile" "$thread_stderr"
      echo "ERROR: codex_review_thread_evidence_counts: hasNextPage=true but endCursor is empty for PR #$pr_number" >&2
      return 3
    fi
    cursor="$end_cursor"
  done

  rm -f "$thread_tmpfile" "$thread_stderr"
  printf '%s\t%s\t%s\n' "$strict_unresolved" "$cleared" "$provisional_relaxed"
}
