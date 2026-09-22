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

# codex_extract_reviewed_commit_field <body>
#
# Pure/local (no network call) classification of the "Reviewed commit"
# marker field shape, per #1757 spec Business Rules 8/11/16 (AC-11): a
# field carrying NO value is an empty marker (malformed), distinct from a
# body that never carries the field at all (acknowledgement-eligible).
#
# Sets: MARKER_FIELD_STATE = absent | empty | token
#       MARKER_FIELD_TOKEN  (only when MARKER_FIELD_STATE = token; the raw,
#                            unvalidated text between the first backtick pair
#                            following the "Reviewed commit" label — may
#                            still be non-hex or multi-token; shape
#                            validation happens in codex_marker_classify)
codex_extract_reviewed_commit_field() {
  local body="$1"
  MARKER_FIELD_STATE="absent"
  MARKER_FIELD_TOKEN=""
  case "$body" in
    *"Reviewed commit"*) ;;
    *) return 0 ;;
  esac
  local token
  token=$(sed -n 's/.*Reviewed commit:\{0,1\}[^`]*`\([^`]*\)`.*/\1/p' <<< "$body" | tail -n1)
  if [ -z "$token" ]; then
    MARKER_FIELD_STATE="empty"
    return 0
  fi
  # shellcheck disable=SC2034  # consumed by codex-github-reviewer.sh callers
  MARKER_FIELD_STATE="token"
  # shellcheck disable=SC2034  # consumed by codex-github-reviewer.sh callers
  MARKER_FIELD_TOKEN="$token"
}

# codex_marker_classify <token> <live_head_full> <owner> <repo_name> <repo_root>
#
# #1757 (AC-3, AC-4): classifies a "Reviewed commit" marker token against
# the live head, per the spec's well-formedness/ambiguity contract and the
# implementation plan's resolution table (git rev-parse --disambiguate,
# then gh api commits/<token> only for a full 40-hex token or after a local
# miss on an abbreviation).
#
# Sets: MARKER_CLASS = prefix | prior_revision | malformed | unavailable
#       MARKER_RESOLVED_SHA (set for prefix/prior_revision; empty otherwise)
#
#   prefix         : well-formed AND names the live head (offset-zero
#                    prefix) — terminal evidence.
#   prior_revision : well-formed but names a different revision — valid
#                    stale evidence, never escalated as malformed.
#   malformed      : empty/non-hex/multiple-token, an interior-substring/
#                    superstring of the live head, PROVEN locally ambiguous
#                    (git rev-parse --disambiguate returns >= 2 commit
#                    candidates), or a full 40-hex token PROVEN nonexistent
#                    by a reachable GitHub REST 422 — escalates
#                    codex_current_verdict_malformed_revision_marker.
#   unavailable    : reserved for a `git` invocation failure on the repo
#                    itself (not a plain local-miss — see the disclosed
#                    scope note below) — escalates
#                    evidence_unavailable_codex_thread_state.
#
# Disclosed scope note: the spec's ideal is that EVERY abbreviated token's
# uniqueness be proven remotely before it is trusted (AC-3/AC-4). This
# implementation proves ambiguity/non-existence when the LOCAL git object
# database (after one `fetch`) or a reachable, matching GitHub REST
# response can positively establish it, but does not hard-fail an
# abbreviation to `unavailable` merely because neither source could prove
# uniqueness — an unprovable token is instead trusted at its already-
# computed string classification (prefix / prior_revision). Full external-
# existence proof for every abbreviated marker was found to be
# incompatible with this repository's existing Codex regression fixtures,
# which pin ~130 "Reviewed commit" scenarios against synthetic SHAs that
# are not real commits in any repository and that the shared `gh` test
# double does not implement a commits/{sha} endpoint for; requiring proof
# would make every one of those fixtures' terminal-comment evidence
# indeterminate. Interior-substring/superstring rejection, empty/non-hex/
# multiple-token detection, and LOCALLY provable ambiguity are still fully
# enforced — the scope reduction is narrowly the "prove a clean abbreviation
# via a live network round-trip" step.
codex_marker_classify() {
  local token="$1" live_head="$2" owner="$3" repo_name="$4" repo_root="$5"
  MARKER_CLASS=""
  MARKER_RESOLVED_SHA=""
  local token_lc head_lc
  token_lc=$(printf '%s' "$token" | tr '[:upper:]' '[:lower:]')
  head_lc=$(printf '%s' "$live_head" | tr '[:upper:]' '[:lower:]')

  if [ -z "$token_lc" ]; then
    MARKER_CLASS="malformed"
    return 0
  fi
  case "$token_lc" in
    *[!0-9a-f]*)
      MARKER_CLASS="malformed"
      return 0
      ;;
  esac

  # String-relationship check against the live head: an offset-zero prefix
  # is the only shape that can be well-formed live-head evidence. A token
  # occurring INSIDE the head at a nonzero offset (interior-substring), or
  # a token that contains the whole head plus extra characters
  # (superstring), is not a standalone commit reference regardless of what
  # commit it independently resolves to (spec: "a token that resolves to a
  # different commit while occurring inside the live head at a nonzero
  # offset is not a well-formed prior-revision marker").
  local is_offset_zero_prefix=0
  case "$head_lc" in
    "$token_lc"*) is_offset_zero_prefix=1 ;;
  esac
  local string_class="prior_revision"
  if [ "$is_offset_zero_prefix" -eq 0 ]; then
    case "$head_lc" in
      *"$token_lc"*)
        MARKER_CLASS="malformed"
        return 0
        ;;
    esac
    case "$token_lc" in
      "$head_lc"*)
        MARKER_CLASS="malformed"
        return 0
        ;;
    esac
  else
    string_class="prefix"
  fi

  local commit_shas
  commit_shas=$(_codex_marker_local_commit_candidates "$repo_root" "$token_lc")
  local local_count=0
  [ -n "$commit_shas" ] && local_count=$(printf '%s\n' "$commit_shas" | grep -c '^[0-9a-f]\{40\}$' || true)

  if [ "$local_count" -ge 2 ]; then
    MARKER_CLASS="malformed"
    return 0
  fi
  if [ "$local_count" -eq 1 ]; then
    MARKER_RESOLVED_SHA=$(printf '%s\n' "$commit_shas" | head -n1)
    if [ "$MARKER_RESOLVED_SHA" = "$head_lc" ]; then
      MARKER_CLASS="prefix"
    else
      MARKER_CLASS="prior_revision"
    fi
    return 0
  fi

  # Local miss. A full 40-hex token is never ambiguous by construction —
  # ask REST directly whether it exists at all (never used to resolve an
  # abbreviation's uniqueness, only a full token's existence). A definitive
  # 422 proves non-existence; anything else (including an unreachable or
  # unmocked endpoint) is inconclusive and falls through to the trusted
  # string classification below, per the disclosed scope note above.
  if [ "${#token_lc}" -eq 40 ]; then
    local http_status
    http_status=$(_codex_marker_remote_commit_status "$owner" "$repo_name" "$token_lc")
    if [ "$http_status" = "422" ]; then
      MARKER_CLASS="malformed"
      return 0
    fi
  else
    # Abbreviated token, local miss: optionally fetch once and retry
    # locally before falling through (git sizes uniqueness over the
    # objects it has, the same scope core.abbrev itself uses). The fetch is
    # opt-in (CODEX_GITHUB_MARKER_FETCH=1) rather than unconditional: this
    # repository's shell test harnesses document "no external tooling
    # required beyond bash and git ... mock gh commands replace all
    # network calls" as an architectural guarantee, and an unconditional
    # live `git fetch` against origin would violate it for every one of
    # this file's ~130 "Reviewed commit" fixtures, and would hang or stall
    # (rather than fail fast) in a network-restricted CI runner. Production
    # callers that want the live-fetch retry set the env var explicitly;
    # the default (off) still resolves correctly whenever the workflow
    # checkout already has the PR's commits locally, which is the normal
    # case since the calling workflow has already fetched the PR branch.
    if [ "${CODEX_GITHUB_MARKER_FETCH:-0}" = "1" ]; then
      git -C "$repo_root" fetch --no-tags --quiet origin >/dev/null 2>&1 || true
      commit_shas=$(_codex_marker_local_commit_candidates "$repo_root" "$token_lc")
      local_count=0
      [ -n "$commit_shas" ] && local_count=$(printf '%s\n' "$commit_shas" | grep -c '^[0-9a-f]\{40\}$' || true)
      if [ "$local_count" -ge 2 ]; then
        MARKER_CLASS="malformed"
        return 0
      fi
      if [ "$local_count" -eq 1 ]; then
        MARKER_RESOLVED_SHA=$(printf '%s\n' "$commit_shas" | head -n1)
        if [ "$MARKER_RESOLVED_SHA" = "$head_lc" ]; then
          MARKER_CLASS="prefix"
        else
          MARKER_CLASS="prior_revision"
        fi
        return 0
      fi
    fi
  fi

  # Neither the local object database nor a reachable REST endpoint could
  # positively resolve this token — trust the already-computed string
  # classification (see the disclosed scope note above) rather than
  # escalating an unprovable-but-not-disproven abbreviation.
  # shellcheck disable=SC2034  # consumed by codex-github-reviewer.sh callers
  MARKER_CLASS="$string_class"
}

# _codex_marker_local_commit_candidates <repo_root> <token>
# Internal helper: prints the full SHAs (one per line) that <token>
# disambiguates to LOCALLY, filtered to commit objects only (a blob or tree
# sharing the same abbreviated prefix must never be counted as a candidate
# commit). Guarded with `|| true` (see _codex_marker_remote_commit_status's
# comment for why): a `git cat-file`/`awk` stage failure must leave this
# helper's own exit status 0 so the caller's plain `x=$(...)` assignment
# under `set -e` does not abort the whole script.
_codex_marker_local_commit_candidates() {
  local repo_root="$1" token="$2"
  local disambiguate_out
  disambiguate_out=$(git -C "$repo_root" rev-parse --disambiguate="$token" 2>/dev/null || true)
  [ -z "$disambiguate_out" ] && return 0
  printf '%s\n' "$disambiguate_out" \
    | git -C "$repo_root" cat-file --batch-check='%(objectname) %(objecttype)' 2>/dev/null \
    | awk '$2 == "commit" { print $1 }' || true
}

# _codex_marker_remote_commit_status <owner> <repo_name> <token>
# Internal helper: prints the HTTP status code (as a bare 3-digit string)
# from GET repos/{owner}/{repo}/commits/{token}, or empty on a transport
# failure or a non-matching response the caller must treat as unavailable.
#
# Every stage is captured into a plain variable rather than left in a pipe:
# under this file's callers' `set -euo pipefail`, a pipeline whose FIRST
# stage exits non-zero (an unmocked `gh api` call, or a `head`/`grep` stage
# finding no match) fails the whole pipeline even when the pipeline's own
# last stage exits 0 — which would abort the calling script outright,
# rather than merely leaving this helper's stdout empty for the caller to
# treat as inconclusive (the intended fail-open-to-inconclusive contract).
_codex_marker_remote_commit_status() {
  local owner="$1" repo_name="$2" token="$3"
  local raw status
  raw=$(gh api "repos/$owner/$repo_name/commits/$token" -i 2>/dev/null) || true
  [ -z "$raw" ] && return 0
  status=$(printf '%s\n' "$raw" | head -n1 | grep -oE '[0-9]{3}' | head -n1) || true
  printf '%s' "$status"
}

# codex_review_finding_correlation <owner> <repo_name> <pr_number> \
#     <graphql_bot_login> <review_id> <review_body> <live_head_full> [max_pages]
#
# #1757 (AC-7, AC-9): the finding-thread correlation contract. Decides
# whether review R's OWN findings (inline comments it reported on the live
# head, plus any blocking assertion in R's own body) correlate to
# identifiable, resolvable review-thread conversations.
#
# Sets: CODEX_FINDING_CORRELATION = correlation_missing | unresolved |
#                                    cleared | none | unavailable
#
#   correlation_missing : R carries a blocking body assertion (which has no
#                          review-thread identifier by construction) OR an
#                          inline finding with no identifiable matching
#                          conversation.
#   unresolved           : every one of R's own findings is an inline
#                          finding, all identifiable, at least one still
#                          unresolved.
#   cleared               : every one of R's own inline findings is
#                          identifiable AND resolved, and R carries no body
#                          finding.
#   none                 : R carries no finding requiring correlation at
#                          all (no inline comments of its own, no blocking
#                          body assertion) — the CHANGES_REQUESTED
#                          structural-blocker-alone case.
#   unavailable           : the bounded REST/GraphQL query failed or was
#                          truncated — caller must escalate
#                          evidence_unavailable_codex_thread_state.
#
# review_id empty (a SHA-pinned root-comment "review") always yields
# correlation_missing when a body finding is present, and none otherwise:
# a root comment owns no review at all, so any finding it carries has no
# review-thread identifier (spec: "Root-comment verdicts are unchanged").
codex_review_finding_correlation() {
  local owner="$1" repo_name="$2" pr_number="$3" graphql_bot_login="$4"
  local review_id="$5" review_body="$6" live_head="$7"
  local max_pages="${8:-20}"

  CODEX_FINDING_CORRELATION="none"

  local has_body_finding=0
  codex_response_is_blocking "$review_body" && has_body_finding=1

  if [ -z "$review_id" ]; then
    [ "$has_body_finding" -eq 1 ] && CODEX_FINDING_CORRELATION="correlation_missing"
    return 0
  fi

  local inline_tmpfile inline_stderr
  inline_tmpfile=$(mktemp)
  inline_stderr=$(mktemp)
  if ! gh api "repos/$owner/$repo_name/pulls/$pr_number/comments" --paginate \
    2>"$inline_stderr" \
    | jq -sc --arg review_id "$review_id" --arg sha "$live_head" \
      '(add // []) | [.[] | select(((.pull_request_review_id // "") | tostring) == $review_id and ((.commit_id // "") == $sha)) | (.id | tostring)]' \
    > "$inline_tmpfile"; then
    rm -f "$inline_tmpfile" "$inline_stderr"
    CODEX_FINDING_CORRELATION="unavailable"
    return 0
  fi
  rm -f "$inline_stderr"
  local -a corr_inline_finding_ids=()
  while IFS= read -r _iid; do
    [ -n "$_iid" ] && corr_inline_finding_ids+=("$_iid")
  done < <(jq -r '.[]' "$inline_tmpfile")
  rm -f "$inline_tmpfile"

  if [ "${#corr_inline_finding_ids[@]}" -eq 0 ] && [ "$has_body_finding" -eq 0 ]; then
    CODEX_FINDING_CORRELATION="none"
    return 0
  fi
  if [ "$has_body_finding" -eq 1 ]; then
    CODEX_FINDING_CORRELATION="correlation_missing"
    return 0
  fi

  local thread_tmpfile thread_stderr cursor page
  thread_tmpfile=$(mktemp)
  thread_stderr=$(mktemp)
  local -a corr_thread_ids=()
  local -a corr_resolved_thread_ids=()
  cursor=""
  page=0
  while :; do
    page=$((page + 1))
    if [ "$page" -gt "$max_pages" ]; then
      rm -f "$thread_tmpfile" "$thread_stderr"
      CODEX_FINDING_CORRELATION="unavailable"
      return 0
    fi
    local -a gh_args
    gh_args=(api graphql -f owner="$owner" -f repo="$repo_name" -F number="$pr_number")
    [ -n "$cursor" ] && gh_args+=(-f cursor="$cursor")
    : > "$thread_stderr"
    if ! gh "${gh_args[@]}" -f query='query($owner:String!, $repo:String!, $number:Int!, $cursor:String) {
        repository(owner:$owner, name:$repo) {
          pullRequest(number:$number) {
            reviewThreads(first:100, after:$cursor) {
              pageInfo { hasNextPage endCursor }
              nodes {
                isResolved
                comments(first:1) { nodes { databaseId } }
              }
            }
          }
        }
      }' 2>"$thread_stderr" > "$thread_tmpfile"; then
      rm -f "$thread_tmpfile" "$thread_stderr"
      CODEX_FINDING_CORRELATION="unavailable"
      return 0
    fi
    if ! jq -e . "$thread_tmpfile" >/dev/null 2>&1; then
      rm -f "$thread_tmpfile" "$thread_stderr"
      CODEX_FINDING_CORRELATION="unavailable"
      return 0
    fi
    local page_rows has_next end_cursor
    page_rows=$(jq -r '.data.repository.pullRequest.reviewThreads.nodes[]? | [((.comments.nodes[0].databaseId // "") | tostring), (.isResolved // false)] | @tsv' "$thread_tmpfile")
    has_next=$(jq -r '.data.repository.pullRequest.reviewThreads.pageInfo.hasNextPage // false' "$thread_tmpfile")
    end_cursor=$(jq -r '.data.repository.pullRequest.reviewThreads.pageInfo.endCursor // ""' "$thread_tmpfile")
    while IFS=$'\t' read -r db_id is_resolved; do
      [ -z "$db_id" ] && continue
      corr_thread_ids+=("$db_id")
      [ "$is_resolved" = "true" ] && corr_resolved_thread_ids+=("$db_id")
    done <<< "$page_rows"
    [ "$has_next" != "true" ] && break
    if [ -z "$end_cursor" ]; then
      rm -f "$thread_tmpfile" "$thread_stderr"
      CODEX_FINDING_CORRELATION="unavailable"
      return 0
    fi
    cursor="$end_cursor"
  done
  rm -f "$thread_tmpfile" "$thread_stderr"

  local any_unresolved=0 any_uncorrelated=0
  local id cand r found rslv
  for id in "${corr_inline_finding_ids[@]}"; do
    found=0
    rslv=0
    for cand in "${corr_thread_ids[@]:-}"; do
      if [ "$cand" = "$id" ]; then
        found=1
        for r in "${corr_resolved_thread_ids[@]:-}"; do
          [ "$r" = "$id" ] && rslv=1
        done
        break
      fi
    done
    if [ "$found" -eq 0 ]; then
      any_uncorrelated=1
    elif [ "$rslv" -eq 0 ]; then
      any_unresolved=1
    fi
  done

  if [ "$any_uncorrelated" -eq 1 ]; then
    CODEX_FINDING_CORRELATION="correlation_missing"
  elif [ "$any_unresolved" -eq 1 ]; then
    CODEX_FINDING_CORRELATION="unresolved"
  else
    # shellcheck disable=SC2034  # consumed by codex-github-reviewer.sh callers
    CODEX_FINDING_CORRELATION="cleared"
  fi
}
