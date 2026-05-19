# External Feedback Pipeline: GitHub Discussions Staging and Triage Protocol — Implementation Plan

**Spec**: [1_459-external-feedback-pipeline_specs.md](1_459-external-feedback-pipeline_specs.md)
**Smoke test runbook**: [../../../testing/workflow/459-external-feedback-pipeline.smoke-test.md](../../../testing/workflow/459-external-feedback-pipeline.smoke-test.md)

---

## Summary

**Approach**: Add three new documentation artefacts (a `CONTRIBUTING.md` at the repository root, a triage protocol at `docs/workflow/development-workflow/protocols/07-feedback-triage-protocol.md`, and a smoke test runbook) plus one GitHub label (`feedback-staging`), then update `AGENTS.md` / `CLAUDE.md` to reference the new triage command and protocol. No application code, scripts, database, or CI changes are required — this feature is entirely documentation and repository-configuration work.

**Estimated complexity**: S
**Rationale**: All deliverables are new Markdown documents and one GitHub label. No existing protocol files are modified; the AGENTS.md change is a single table-row addition. The implementation can be completed in a single session.

**Dependencies**: None

---

## Verification Log

| Check                                          | Command / query                                                                   | Result                                                                                                               |
| ---------------------------------------------- | --------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| Repo revision                                  | `git rev-parse --short HEAD`                                                      | `1ab1488`                                                                                                            |
| 07-feedback-triage-protocol.md exists?         | `ls docs/workflow/development-workflow/protocols/07-feedback-triage-protocol.md`  | NOT FOUND — must be created                                                                                          |
| CONTRIBUTING.md at repo root?                  | `ls CONTRIBUTING.md`                                                              | NOT FOUND — must be created                                                                                          |
| `feedback-staging` label exists?               | `gh label list \| grep feedback-staging`                                          | NOT FOUND — must be created as setup step                                                                            |
| `template-feedback` label (existing, distinct) | `gh label list \| grep template-feedback`                                         | EXISTS (`#0075ca`) — not the same label; `feedback-staging` is a separate label for issues promoted from Discussions |
| GitHub Discussions enabled on repo?            | `gh repo view --json hasDiscussionsEnabled`                                       | `true` — Discussions already enabled                                                                                 |
| Existing protocol count (0x-series)            | `ls docs/workflow/development-workflow/protocols/ \| grep -E '^0[0-9]-' \| wc -l` | 10 files (00 through 06, plus review wrappers); 07-feedback-triage-protocol.md is the next slot                      |
| Testing/workflow directory                     | `ls docs/testing/workflow/`                                                       | Exists; smoke test runbook will be placed here                                                                       |

---

## Layer-by-Layer Changes

### Documentation / Protocols

- [ ] Create `docs/workflow/development-workflow/protocols/07-feedback-triage-protocol.md` — the primary triage protocol (see Implementation Order for full content spec)
- [ ] Create `CONTRIBUTING.md` at the repository root — directs external users to GitHub Discussions "Feedback & Ideas" category; explains triage process and signal threshold

### Infrastructure / Configuration

- [ ] Document creation of the `feedback-staging` GitHub label as a mandatory setup step inside `07-feedback-triage-protocol.md` (label creation is a `gh` CLI command; it cannot be committed to the repository)
- [ ] Document creation of the "Feedback & Ideas" GitHub Discussions category as a mandatory setup step inside `07-feedback-triage-protocol.md` (Discussions category creation is a GitHub UI action; it cannot be automated via `gh` CLI in the initial version)

### AGENTS.md / CLAUDE.md

- [ ] Add a `Run feedback triage` row to the Workflow Commands table in `AGENTS.md` (which is the same file as `CLAUDE.md` via symlink) — Claude Code column: `—` (no dedicated agent in initial version; use protocol doc), Cursor column: `—`, Codex column: `—`, Any other tool column: `Follow docs/workflow/development-workflow/protocols/07-feedback-triage-protocol.md`

---

## Testing Strategy

**Test types**: Manual (smoke test)

**Key scenarios to test**:

1. External user visits `CONTRIBUTING.md` and finds clear instructions for submitting feedback via Discussions (maps to AC-2)
2. Triage runner follows protocol against a sample Discussion that meets the signal threshold and has no duplicate — verifies a new issue is created with `feedback-staging` label and Discussion is closed with a comment (maps to AC-3, AC-4, AC-5)
3. Triage runner follows protocol against a sample Discussion whose title/body matches an existing open issue — verifies Discussion is closed with a comment linking to the existing issue (maps to AC-5)
4. Triage runner follows protocol against a Discussion that does not meet the signal threshold — verifies it is skipped (maps to AC-3, Business Rules: signal threshold)
5. Triage runner identifies a Discussion as out of scope — verifies it is closed with a polite explanatory comment (maps to AC-5, Use Case 4)
6. Verify the `feedback-staging` label exists after setup steps are followed (maps to AC-4)

**Smoke test runbook**: `docs/testing/workflow/459-external-feedback-pipeline.smoke-test.md`

---

## Seed Data

| Entity                                                 | Values / Scenario                                                                                    | File                                             |
| ------------------------------------------------------ | ---------------------------------------------------------------------------------------------------- | ------------------------------------------------ |
| GitHub Discussion (signal threshold met, no duplicate) | A discussion in "Feedback & Ideas" with ≥ 3 upvotes or ≥ 2 comments from distinct users              | Manual setup step in smoke test; no seed file    |
| GitHub Discussion (duplicate of existing issue)        | A discussion whose title/body matches an existing open issue by ≥ 3 significant keywords             | Manual setup step in smoke test; no seed file    |
| GitHub Discussion (out of scope)                       | A discussion asking a support question unrelated to template workflow improvement                    | Manual setup step in smoke test; no seed file    |
| GitHub label: `feedback-staging`                       | Label color `#0e8a16` (green), description "Issue promoted from a GitHub Discussions feedback entry" | Created via `gh label create` during setup steps |

---

## Documentation Updates

- [ ] `AGENTS.md` (same file as `CLAUDE.md` via symlink) — add `Run feedback triage` row to the Workflow Commands table and reference `07-feedback-triage-protocol.md`
- [ ] `docs/workflow/development-workflow/README.md` — add a brief mention of the feedback triage stage and a link to `07-feedback-triage-protocol.md` in the stages overview section (the "Feedback Triage" entry is a new optional lifecycle stage that maintainers may run periodically)

---

## Risks & Mitigations

| Risk                                                                               | Likelihood | Impact | Mitigation                                                                                                                                            |
| ---------------------------------------------------------------------------------- | ---------- | ------ | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| Triage runner creates duplicate issues if run twice without checking prior results | Low        | Med    | Protocol must include a step to check whether a Discussion was already processed (look for a closing comment from a prior run) before creating issues |
| "Feedback & Ideas" Discussions category not created before the protocol is used    | Med        | Med    | Document the category creation as a mandatory prerequisite in `07-feedback-triage-protocol.md` and in `CONTRIBUTING.md`                               |
| `feedback-staging` label not created before a triage run                           | Med        | Low    | Document label creation as a mandatory setup step; provide the exact `gh label create` command in the protocol                                        |
| External users open Issues instead of Discussions despite `CONTRIBUTING.md`        | Med        | Low    | `CONTRIBUTING.md` should set expectations that Issues opened by non-maintainers for feature requests will be redirected to Discussions                |
| Keyword-based duplicate detection produces false positives                         | Med        | Low    | Protocol instructs the triage runner to present matches to the maintainer for confirmation before acting (interactive mode default)                   |

---

## Implementation Order

1. **Create `CONTRIBUTING.md` at the repository root**

   Content must include:
   - A welcoming introduction for external contributors
   - A "Submitting feedback and ideas" section that:
     - Directs users to GitHub Discussions → "Feedback & Ideas" category (with a direct URL or instructions to navigate there)
     - Explains that opening a GitHub Issue for feature requests is not the right path; maintainers may redirect such issues to Discussions
     - Describes the triage process at a high level: feedback accumulates in Discussions; maintainers periodically run a triage protocol; items with sufficient community signal (3+ upvotes or 2+ comments from distinct users) and no existing duplicate may be promoted to tracked backlog issues
     - Explicitly states that submitting feedback does not guarantee implementation
   - A "What happens to my feedback?" section explaining the signal threshold values (3 upvotes or 2 comments) so contributors understand how items are evaluated
   - A note that the "Feedback & Ideas" category is moderated; support questions and project-specific downstream requests are out of scope for this tracker

   Verification: confirm `CONTRIBUTING.md` renders correctly and all links resolve.

2. **Create `docs/workflow/development-workflow/protocols/07-feedback-triage-protocol.md`**

   Content must include all of the following sections:

   **a. Purpose** — brief statement: this protocol defines how to periodically review GitHub Discussions in the "Feedback & Ideas" category and promote high-signal, in-scope items to tracked backlog issues.

   **b. Prerequisites / One-time Setup** — documented steps that must be completed before the protocol can be used:
   - Enable GitHub Discussions on the repository (if not already enabled)
   - Create a "Feedback & Ideas" Discussions category in the repository's GitHub Discussions settings (GitHub UI action; not scriptable via `gh` CLI in initial version)
   - Set the "Feedback & Ideas" category description to: "Share your feedback, ideas, or feature requests. Read CONTRIBUTING.md for details on how feedback is reviewed."
   - Create the `feedback-staging` GitHub label:
     ```bash
     gh label create "feedback-staging" \
       --description "Issue promoted from a GitHub Discussions feedback entry" \
       --color "0e8a16"
     ```

   **c. Recommended Cadence** — at least once per month; the protocol does not enforce a schedule and does not block on missing runs.

   **d. How to Invoke** — instructions for a maintainer or agent to invoke the protocol manually by following the steps below; note there is no dedicated `run-feedback-triage` command or agent in the initial version.

   **e. Triage Steps** — ordered steps the triage runner follows:
   1. Query all open Discussions in the "Feedback & Ideas" category:
      ```bash
      gh api graphql -f query='
        query($owner:String!, $repo:String!) {
          repository(owner:$owner, name:$repo) {
            discussionCategories(first:20) {
              nodes { id name }
            }
          }
        }' -f owner=OWNER -f repo=REPO
      # Then query discussions by category ID using cursor-based pagination:
      # Repeat this query, advancing $after to pageInfo.endCursor, until pageInfo.hasNextPage is false.
      gh api graphql -f query='
        query($owner:String!, $repo:String!, $categoryId:ID!, $after:String) {
          repository(owner:$owner, name:$repo) {
            discussions(first:50, after:$after, categoryId:$categoryId, states:OPEN) {
              pageInfo { hasNextPage endCursor }
              nodes {
                number title bodyText author { login }
                upvoteCount
                comments { totalCount }
              }
            }
          }
        }' -f owner=OWNER -f repo=REPO -f categoryId=CATEGORY_ID
      # On each iteration pass -f after=END_CURSOR. Stop when hasNextPage is false.
      ```
   2. For each Discussion, evaluate the signal threshold:
      - Signal threshold met: `upvoteCount >= 3` OR `comments.totalCount >= 2` from distinct users (other than the original poster)
      - Note: when checking comment count, use `comments.totalCount`; if the initial implementation cannot easily filter by distinct non-OP users, document this as a manual check step
      - If the threshold is not met, skip the Discussion (leave it open for more signal)
   3. For each Discussion that meets the threshold, check if it was already processed by a prior triage run:
      - Query the Discussion's comments for any comment that contains the text "promoted to issue" or "already tracked" or "closed as out of scope" left by a maintainer
      - If a prior-run closing comment is found, skip this Discussion
   4. For each unprocessed Discussion that meets the threshold, check for duplicates against existing issues:
      - Tokenize the Discussion title and body: extract significant keywords (words with ≥ 4 characters, excluding stopwords: "the", "a", "is", "in", "to", "of", "and", "or", "for", "that", "this", "with", "from", "are", "not", "you", "your", "but", "was", "have", "will")
      - Search open and closed issues for keyword overlap using keyword-scoped search
        (avoids a fixed-cap truncation that would silently miss issues beyond an arbitrary limit):
        ```bash
        # Run one search per significant keyword extracted from the Discussion title/body.
        # Merge results and deduplicate by issue number before checking for overlap.
        gh issue list --state all --search "KEYWORD" --json number,title,body \
          | jq '.[] | {number, title, body}'
        ```
      - A Discussion is a potential duplicate when: ≥ 3 significant keywords match between the Discussion (title + body) and an existing issue (title + body), OR when the affected file paths or protocol names are identical
      - When match confidence is ambiguous, present both the potential match and "No strong existing item found" and ask the maintainer to decide
   5. Present a preview of proposed actions to the maintainer before executing (interactive mode — default):
      - List each candidate Discussion with: title, upvote count, comment count, proposed action (promote, duplicate of #N, out of scope), and the reason for the proposed action
      - Wait for maintainer confirmation before proceeding
   6. Execute confirmed actions:
      - **Promote**: Create a new GitHub issue using the format specified in the "Promoted Issue Format" section below; close the Discussion with a comment ("Your feedback has been promoted to issue #N. Thank you for contributing!")
      - **Duplicate (open issue)**: Comment on the Discussion linking to the existing issue; close the Discussion ("Thank you for this feedback! This topic is already tracked in #N. You can follow or comment there to add your context."); leave the existing issue unchanged
      - **Duplicate (closed issue)**: Comment on the Discussion noting the issue is closed; ask the maintainer whether to reopen the existing issue or close the Discussion as already addressed
      - **Out of scope**: Close the Discussion with a polite, specific comment explaining why (e.g., "This is a support question rather than a workflow improvement request. For help with ..."); do not create an issue

   **f. Promoted Issue Format** — issues created by the triage protocol must have:
   - Title: derived from the Discussion title (verbatim or lightly edited for clarity)
   - Label: `feedback-staging`
   - Body template:

     ```
     ## Community feedback source

     GitHub Discussion: [Discussion title](Discussion URL)

     ## Summary

     [Concise description of the request, 1-3 sentences]

     ## Signal

     - Upvotes: N
     - Comments: N (at time of triage: YYYY-MM-DD)

     ## Original feedback

     > [Quoted or closely paraphrased content from the Discussion opening post]
     ```

   **g. Scope Filter** — what is in scope for promotion:
   - Template workflow improvements
   - Tooling gaps in the existing protocol scripts or agent instructions
   - Protocol deficiencies (ambiguous, incomplete, or missing protocol steps)
   - Configuration usability issues (`.ai-dev-workflow.yaml`, setup, onboarding)

   What is out of scope (close with helpful comment, do not promote):
   - Support questions ("how do I use X?")
   - Project-specific (downstream) customization requests ("can you add support for my framework?")
   - General questions not describing a deficiency or improvement
   - Requests explicitly deferred in a prior "Out of Scope" spec section

   **h. Closing Comments Are Mandatory** — every Discussion acted on by this protocol (promoted, duplicate, or out of scope) must receive a closing comment explaining the outcome. Silent closes are not permitted.

   **i. Related Documents** — links to `CONTRIBUTING.md`, `docs/workflow/development-workflow/protocols/06-retrospective-protocol.md` (adjacent periodic protocol), and `AGENTS.md` (workflow commands table).

   Verification: confirm the file renders correctly, all links resolve, and the signal threshold values (3 upvotes / 2 comments) are visible.

3. **Update `AGENTS.md` / `CLAUDE.md`**

   In the Workflow Commands table, add a new row after the `Retrospective` row:

   | Stage               | Claude Code | Cursor | Codex | Any other tool                                                                       |
   | ------------------- | ----------- | ------ | ----- | ------------------------------------------------------------------------------------ |
   | Run feedback triage | —           | —      | —     | Follow `docs/workflow/development-workflow/protocols/07-feedback-triage-protocol.md` |

   Note: `AGENTS.md` and `CLAUDE.md` are the same physical file (symlink). Only one file needs to be edited; the other reflects the change automatically.

   Verification: confirm the table row appears correctly and the link to `07-feedback-triage-protocol.md` resolves.

4. **Update `docs/workflow/development-workflow/README.md`**

   Add a brief mention of the feedback triage stage. Locate the lifecycle stages section (or the closest equivalent) and add a sentence or short paragraph noting that maintainers can periodically run the feedback triage protocol (`07-feedback-triage-protocol.md`) to promote high-signal GitHub Discussions to tracked backlog issues.

   Verification: confirm the addition renders correctly and the link resolves.

5. **Review and update the smoke test runbook**

   The runbook skeleton at `docs/testing/workflow/459-external-feedback-pipeline.smoke-test.md` was created during the Plan Ready stage. After implementation, update it to reflect any deviations from the plan (e.g., updated commands, actual Discussion category ID, actual label color) and confirm it covers AC-1 through AC-6 (see Testing Strategy scenarios above).

6. **Pre-commit lint check**

   Run `markdownlint-cli2` on all new/modified Markdown files before staging:

   ```bash
   REPO_ROOT=$(git rev-parse --git-common-dir)/..
   "$REPO_ROOT/node_modules/.bin/markdownlint-cli2" \
     "CONTRIBUTING.md" \
     "docs/workflow/development-workflow/protocols/07-feedback-triage-protocol.md" \
     "docs/testing/workflow/459-external-feedback-pipeline.smoke-test.md"
   ```

   Fix any reported violations (trailing whitespace, missing trailing newline, broken relative links) before committing.

7. **Update `CHANGELOG.md` under `[Unreleased]`**

   Add an entry:

   ```
   - **External feedback pipeline: GitHub Discussions staging and triage protocol** (#459): Adds `CONTRIBUTING.md` directing external users to submit feedback via GitHub Discussions, a triage protocol (`07-feedback-triage-protocol.md`) for periodic review and promotion of high-signal community feedback to tracked issues, and the `feedback-staging` label for promoted issues.
   ```
