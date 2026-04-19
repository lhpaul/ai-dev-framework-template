# Require All Review Threads Resolved Before Ready-For-Human-Review — Implementation Plan

**Spec**: [`1_review-threads-all-resolved_specs.md`](./1_review-threads-all-resolved_specs.md)
**Smoke test runbook**: [`docs/testing/workflow/review-threads-all-resolved.smoke-test.md`](../../../testing/workflow/review-threads-all-resolved.smoke-test.md)

---

## Summary

**Approach**: Add a `check_unresolved_threads` function to `pr-review-loop.sh` that uses the GitHub GraphQL API to enumerate all `reviewThreads` on a PR, filters them to threads authored by configured bot logins, and exits `needs_fixes` with `UNRESOLVED_THREAD_COUNT=N` when any remain unresolved. This function runs as the final check inside each platform handler's "clean" exit path and also at the aggregate level before the script exits with `RESULT=clean`. Protocol 91 Step 8c is updated to add an explicit `reviewThreads` GraphQL check to its independent verification checklist.

**Estimated complexity**: M

**Rationale**: The change is entirely contained in one shell script (`pr-review-loop.sh`) and one protocol document (`91-orchestrate-work-protocol.md`). The GraphQL query, bot-login filtering, and `UNRESOLVED_THREAD_COUNT` output are straightforward to add. Pagination handling (cursor-based) and the `✅ Addressed` equivalence rule require careful implementation, pushing this from S to M.

**Dependencies**: None — no other in-progress issues block this work.

---

## Layer-by-Layer Changes

### Scripts / Automation

- [ ] **`scripts/development-workflow/pr-review-loop.sh`** — Add `check_unresolved_threads` function (see implementation steps below) and wire it into the final clean-exit path of each platform handler and the aggregate exit.

### Protocol Documentation

- [ ] **`docs/ai/development-workflow/protocols/91-orchestrate-work-protocol.md`** — Update Step 8c's independent-verification checklist to include an explicit `reviewThreads` GraphQL check as a hard gate, aligned with AC3. Also update the Automated Reviewer Loop Summary template in Step 7 to include a "Reply-only resolutions" section that lists threads resolved via reply + mutation (no code fix) with a short rationale, aligned with AC5.

- [ ] **`docs/ai/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`** — Update Step 5.1's post-dispatch PR verification checklist to include the same `reviewThreads` unresolved-thread check, aligned with AC7.

---

## Testing Strategy

**Test types**: Smoke (manual, against a real PR with known thread states)

**Key scenarios to test**:

1. PR has one Nitpick/Minor thread that is `isResolved: false` — loop must exit `needs_fixes` with `UNRESOLVED_THREAD_COUNT=1` (maps to AC1)
2. PR has all threads resolved (`isResolved: true` or `✅ Addressed` in body) — loop must exit `clean` (maps to AC2)
3. Fixer resolves thread via `resolveReviewThread` mutation; loop re-runs and sees `isResolved: true`; PR reaches `ready-for-human-review` (maps to AC4)
4. Step 8c catches a PR where thread check was bypassed (maps to AC3)
5. Human-authored threads are not counted by the gate (maps to AC6)

**Smoke test runbook**: [`docs/testing/workflow/review-threads-all-resolved.smoke-test.md`](../../../testing/workflow/review-threads-all-resolved.smoke-test.md)

**Regression suite**: No automated regression suite exists in this repository.

---

## Seed Data

No database seed data required. Testing relies on a real GitHub PR with controlled thread states.

| Entity | Values / Scenario | File |
|---|---|---|
| Test PR | PR with at least one open Nitpick-severity CodeRabbit thread | Created manually during smoke test |

---

## Documentation Updates

The protocol document changes (Step 8c in Protocol 91, Step 5.1 in Protocol 90, and the Step 7 summary template) are themselves deliverables listed in the Layer-by-Layer Changes section above and must be executed during implementation. Additionally, `CHANGELOG.md` must be updated with an entry under `[Unreleased]` as part of the implementation (Implementation Order Step 10) per standard practice for feature PRs merged into `develop`. No other project docs in `docs/project/`, `docs/best-practices/`, or `AGENTS.md` are affected by this change.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| GitHub GraphQL `reviewThreads` paginates beyond 100 nodes | Low | High (silent miss) | Use cursor-based pagination in the query loop; emit a warning if cursor is non-null after 10 pages |
| Bot login list in `.ai-dev-workflow.yaml` diverges from actual bot accounts | Low | Med | Read bot logins from `review.platforms` mapping at runtime; document the mapping in the plan |
| `✅ Addressed` text appears in a human comment, causing false positive "resolved" | Very Low | Low | Scope the `✅ Addressed` equivalence check to comments authored by bot logins only |
| `resolveReviewThread` mutation requires the `id` (node ID), not the REST `comment_id` | Med | Med | GraphQL query already returns `id` (node ID) per thread; document this in code comment |
| Spec/plan branches where CodeRabbit skips review have zero bot threads — gate must not block | Low | Med | Guard: if `UNRESOLVED_THREAD_COUNT=0`, always pass; only fail when count > 0 |

---

## Code Samples

> All samples below are **illustrative — adapt during implementation**.

### GraphQL query to enumerate review threads (paginated)

```graphql
# Illustrative — adapt during implementation
query($owner: String!, $repo: String!, $pr: Int!, $cursor: String) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $pr) {
      reviewThreads(first: 100, after: $cursor) {
        pageInfo { hasNextPage endCursor }
        nodes {
          id
          isResolved
          comments(first: 1) {
            nodes {
              author { login }
              body
            }
          }
        }
      }
    }
  }
}
```

### Bash helper to call the query (illustrative)

```bash
# Illustrative — adapt during implementation
check_unresolved_threads() {
  local pr_number="$1"
  local branch_name="$2"
  # bot_logins: space-separated list derived from review.platforms config
  local bot_logins="$3"
  local repo="$4"

  local unresolved_count=0
  local cursor=""
  local has_next_page="true"
  local owner repo_name

  owner="$(printf '%s\n' "$repo" | cut -d/ -f1)"
  repo_name="$(printf '%s\n' "$repo" | cut -d/ -f2)"

  while [ "$has_next_page" = "true" ]; do
    local result
    result="$(gh api graphql \
      -f query='query($owner:String!,$repo:String!,$pr:Int!,$cursor:String){repository(owner:$owner,name:$repo){pullRequest(number:$pr){reviewThreads(first:100,after:$cursor){pageInfo{hasNextPage endCursor}nodes{id isResolved comments(first:1){nodes{author{login}body}}}}}}}' \
      -f owner="$owner" -f repo="$repo_name" -F pr="$pr_number" ${cursor:+-f cursor="$cursor"} \
      --jq '.data.repository.pullRequest.reviewThreads')"

    has_next_page="$(printf '%s\n' "$result" | jq -r '.pageInfo.hasNextPage')"
    cursor="$(printf '%s\n' "$result" | jq -r '.pageInfo.endCursor // empty')"

    while IFS= read -r thread_json; do
      [ -z "${thread_json:-}" ] && continue
      local is_resolved author body

      is_resolved="$(printf '%s\n' "$thread_json" | jq -r '.isResolved')"
      author="$(printf '%s\n' "$thread_json" | jq -r '.comments.nodes[0].author.login // ""')"
      body="$(printf '%s\n' "$thread_json" | jq -r '.comments.nodes[0].body // ""')"

      # Check if author is a configured bot login
      local is_bot=0
      local bot_login
      for bot_login in $bot_logins; do
        if [ "$author" = "$bot_login" ]; then is_bot=1; break; fi
      done
      [ "$is_bot" -eq 0 ] && continue

      # A thread is resolved if isResolved=true OR body contains "✅ Addressed"
      if [ "$is_resolved" = "true" ]; then continue; fi
      if printf '%s\n' "$body" | grep -q "✅ Addressed"; then continue; fi

      unresolved_count=$((unresolved_count + 1))
    done < <(printf '%s\n' "$result" | jq -c '.nodes[]')
  done

  printf '%d\n' "$unresolved_count"
}
```

### Bot login mapping from `.ai-dev-workflow.yaml`

```bash
# Illustrative — adapt during implementation
# Derive bot logins from the platforms list in .ai-dev-workflow.yaml
bot_login_for_platform() {
  case "$1" in
    coderabbit) printf 'coderabbitai[bot]\n' ;;
    devin)      printf 'devin-ai-integration[bot]\n' ;;
    greptile)   printf 'greptile-apps[bot]\n' ;;
    *)          printf '\n' ;;
  esac
}
```

### Wiring into the aggregate clean-exit path (illustrative)

```bash
# Illustrative — adapt during implementation
# In the aggregate loop, after all platforms return clean/skipped:
if [ "$aggregate_result" = "clean" ] || [ "$aggregate_result" = "skipped" ]; then
  # Derive bot logins from configured platforms
  bot_logins=""
  for p in "${platforms[@]}"; do
    login="$(bot_login_for_platform "$p")"
    [ -n "$login" ] && bot_logins="$bot_logins $login"
  done
  bot_logins="$(printf '%s\n' "$bot_logins" | xargs)"  # trim

  unresolved_count=0
  if [ -n "$bot_logins" ]; then
    unresolved_count="$(check_unresolved_threads "$pr_number" "$branch_name" "$bot_logins" "$repo")"
  fi
  print_kv UNRESOLVED_THREAD_COUNT "$unresolved_count"

  if [ "$unresolved_count" -gt 0 ]; then
    print_kv RESULT needs_fixes
    print_kv REASON unresolved_review_threads
    exit 1
  fi
fi
```

---

## Implementation Order

1. **Read and understand `pr-review-loop.sh` and `workflow-lib.sh`** — identify the exact exit points that currently emit `RESULT=clean` and the aggregate exit block at the bottom of the script.

2. **Add `bot_login_for_platform` helper function** to `pr-review-loop.sh` — maps platform name (from `.ai-dev-workflow.yaml`) to its bot login string. Add immediately after the existing platform-specific `run_*` functions and before `run_platform_review`.

3. **Add `check_unresolved_threads` function** to `pr-review-loop.sh` — implements the paginated GraphQL query, bot-login filter, `isResolved` + `✅ Addressed` equivalence, and returns the unresolved count as a plain integer on stdout. Add after `bot_login_for_platform`.

4. **Wire `check_unresolved_threads` into the aggregate exit block** — in the section starting at `if [ -z "$last_platform" ]; then`, add the unresolved-thread check after the platform loop completes and the aggregate result is `clean` or `skipped` (before the `case "$aggregate_result"` exit switch). Emit `UNRESOLVED_THREAD_COUNT` in all exit paths (0 when clean, N when needs_fixes). When `unresolved_count > 0`, override `aggregate_result` to `needs_fixes`, set `aggregate_reason` to `unresolved_review_threads`, and exit 1.

5. **Update `91-orchestrate-work-protocol.md` Step 8c** — add a new row to the verification checklist table:

   | Check | Pass condition |
   |---|---|
   | All automated-reviewer `reviewThreads` resolved | GraphQL `reviewThreads.nodes[].isResolved=true` (or `✅ Addressed` in parent comment body) for every thread authored by a configured bot login |

   Add a code block showing the `gh api graphql` command that evaluates this check, consistent with the illustrative sample in this plan. Place this row after the "No `needs-fixes` label" row and before the "Automated reviewer loop summary" row in the existing table.

6. **Update `91-orchestrate-work-protocol.md` Step 7 Automated Reviewer Loop Summary template** — add a "Reply-only resolutions" subsection to the Final Summary Comment template (the `### Automated Reviewer Loop Summary` block). The new section lists each thread resolved via reply + `resolveReviewThread` mutation (no code fix) with the thread author, a short description of the concern, and the rationale given in the reply. This enables human reviewers to audit non-code-fix resolutions (AC5).

   The subsection should be added after the findings table in the summary template, similar to:

   ```markdown
   **Reply-only resolutions (no code fix):** M thread(s) resolved via reply + resolveReviewThread mutation.

   | Thread | Author | Concern summary | Rationale |
   |--------|--------|-----------------|-----------|
   | #1 | coderabbitai[bot] | First 60 chars of concern... | First 80 chars of reply rationale... |
   ```

   When M=0 (all resolutions were code fixes), omit this subsection.

7. **Update `90-batch-orchestrate-work-protocol.md` Step 5.1** — add the same `reviewThreads` unresolved-thread check to the post-dispatch PR verification checklist table (AC7). Add a row after "No `needs-fixes` label":

   | Check | Pass condition |
   |---|---|
   | All automated-reviewer `reviewThreads` resolved | GraphQL `reviewThreads.nodes[].isResolved=true` (or `✅ Addressed` in body) for every thread authored by a configured bot login |

8. **Verify `shellcheck` passes** — run `shellcheck scripts/development-workflow/pr-review-loop.sh` in the worktree and fix any warnings before committing.

9. **Verify markdown lint passes** — run `npx markdownlint-cli2 "docs/specs/developments/**/*.md" "docs/testing/workflow/**/*.md" "docs/ai/development-workflow/protocols/91-orchestrate-work-protocol.md" "docs/ai/development-workflow/protocols/90-batch-orchestrate-work-protocol.md"` in the worktree.

10. **Update CHANGELOG** — add an entry under `[Unreleased]` describing this change.

11. **Verify smoke test runbook scenarios** — manually confirm the runbook steps map to each acceptance criterion.
