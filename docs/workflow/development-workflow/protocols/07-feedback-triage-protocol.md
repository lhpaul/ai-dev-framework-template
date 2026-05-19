# Protocol: Feedback Triage — GitHub Discussions Staging and Promotion

**Protocol**: `07-feedback-triage-protocol.md`
**Related documents**: [`CONTRIBUTING.md`](../../../../CONTRIBUTING.md),
[`06-retrospective-protocol.md`](06-retrospective-protocol.md),
[`AGENTS.md`](../../../../AGENTS.md)

---

## Purpose

This protocol defines how to periodically review open GitHub Discussions in the
"Feedback & Ideas" category and promote high-signal, in-scope items to tracked backlog
issues. It is intended to be run by a maintainer or AI agent on a regular cadence to
prevent high-quality community feedback from going unnoticed while keeping the Issues
backlog free of unfiltered, potentially duplicate, or low-signal items.

---

## Prerequisites / One-time Setup

Complete these steps once before using this protocol for the first time.

### 1. Enable GitHub Discussions

Confirm Discussions is enabled on the repository:

```bash
gh repo view --json hasDiscussionsEnabled --jq '.hasDiscussionsEnabled'
# Expected: true
```

If `false`, enable it via **Repository Settings → Features → Discussions**.

### 2. Create the "Feedback & Ideas" Discussions category

GitHub Discussions categories cannot be created via `gh` CLI in the initial version.
Use the GitHub UI:

1. Go to **Repository Settings → Discussions → Categories**.
2. Click **New category**.
3. Name: `Feedback & Ideas`
4. Description: `Share your feedback, ideas, or feature requests. Read CONTRIBUTING.md
for details on how feedback is reviewed.`
5. Format: **Open-ended discussion** (not Q&A or Poll).
6. Save.

### 3. Create the `feedback-staging` label

Issues promoted from Discussions must carry this label to distinguish them from
internally generated backlog items.

```bash
gh label create "feedback-staging" \
  --description "Issue promoted from a GitHub Discussions feedback entry" \
  --color "0e8a16"
```

Verify:

```bash
gh label list | grep feedback-staging
```

---

## Recommended Cadence

Run this protocol at least once per month. The cadence is a guideline — the protocol
does not enforce a schedule and does not block on missing runs. High-traffic repositories
may benefit from bi-weekly triage; low-traffic repositories can triage quarterly.

---

## How to Invoke

This protocol has no dedicated agent or CLI command in the initial version. To run a
triage session, a maintainer (or an AI agent acting as a triage runner) follows the
Triage Steps below manually or by pasting them into an AI assistant session.

Future automation (scheduled GitHub Action, dedicated agent) is out of scope for this
release and can be added as a follow-up.

---

## Triage Steps

### Step 1: Query open Discussions in the "Feedback & Ideas" category

First, retrieve the category ID:

```bash
gh api graphql -f query='
  query($owner:String!, $repo:String!) {
    repository(owner:$owner, name:$repo) {
      discussionCategories(first:100) {
        nodes { id name }
      }
    }
  }' -f owner=OWNER -f repo=REPO
```

Replace `OWNER` and `REPO` with the repository owner and name (e.g., from
`gh repo view --json nameWithOwner`). Note the `id` value for the
`Feedback & Ideas` category.

Then retrieve all open discussions using cursor-based pagination. Repeat the query
below, advancing `$after` to `pageInfo.endCursor`, until `pageInfo.hasNextPage` is
`false`:

```bash
gh api graphql -f query='
  query($owner:String!, $repo:String!, $categoryId:ID!, $after:String) {
    repository(owner:$owner, name:$repo) {
      discussions(first:50, after:$after, categoryId:$categoryId) {
        pageInfo { hasNextPage endCursor }
        nodes {
          number title bodyText author { login }
          upvoteCount
          comments { totalCount }
        }
      }
    }
  }' -f owner=OWNER -f repo=REPO -f categoryId=CATEGORY_ID
# On each subsequent iteration, add: -f after=END_CURSOR
```

Collect all returned Discussion nodes before proceeding.

### Step 2: Evaluate the signal threshold

For each Discussion, check whether either condition is met:

- `upvoteCount >= 3` (at least 3 upvote reactions on the opening post), **OR**
- `comments.totalCount >= 2` from distinct users other than the original poster

**Note on comment count**: `comments.totalCount` counts all comments including replies
from the original poster. The threshold requires **at least two distinct non-author
comments** (not just non-zero non-author engagement). For **every** discussion that
meets `comments.totalCount >= 2`, manually verify that the count includes at least
two distinct users other than the original poster before treating the threshold as
met — even when `totalCount` is high. A discussion with 4+ comments can still have
only one non-author participant (e.g., one maintainer comment plus author replies),
which does **not** satisfy the threshold.

If the threshold is **not** met, skip the Discussion — leave it open so community
signal can continue to accrue.

### Step 3: Check for prior triage processing

For each Discussion that meets the threshold, check whether it was already processed by
a prior triage run. Query the Discussion's comments and look for any comment containing
one of the following phrases:

- `"promoted to issue"`
- `"already tracked"`
- `"closed as out of scope"`

If a prior-run closing comment is found, skip this Discussion — it has already been
handled.

### Step 4: Check for duplicates against existing issues

For each unprocessed Discussion that meets the threshold:

**Tokenise the Discussion title and body**: extract significant keywords — words with
4 or more characters, excluding stopwords: `the`, `a`, `is`, `in`, `to`, `of`, `and`,
`or`, `for`, `that`, `this`, `with`, `from`, `are`, `not`, `you`, `your`, `but`,
`was`, `have`, `will`.

**Search open and closed issues** using keyword-scoped search. Run one search per
significant keyword and merge results, deduplicating by issue number:

```bash
# Run for each significant keyword extracted from the Discussion title/body.
# Merge and deduplicate by issue number before checking overlap.
# --limit 500 avoids the default 30-item cap for repositories with many issues.
gh issue list --state all --search "KEYWORD" --limit 500 --json number,title,body \
  | jq '.[] | {number, title, body}'
```

**A Discussion is a potential duplicate when**:

- **3 or more significant keywords** match between the Discussion (title + body) and an
  existing issue (title + body), **OR**
- The affected **file paths or protocol names** are identical between the Discussion and
  an existing issue.

**When match confidence is ambiguous**: present both the potential match and
"No strong existing item found" to the maintainer and ask them to decide.

Note: duplicate detection covers **both open and closed issues**. If the best match is a
closed issue (resolved or won't-fix), surface it as a "potential resolved duplicate" and
ask the maintainer whether to reopen or close the Discussion as already addressed.

### Step 5: Present a preview to the maintainer (interactive mode — default)

Before executing any action, present a preview listing each candidate Discussion with:

- Discussion number and title
- Upvote count and comment count
- Proposed action: `promote`, `duplicate of #N`, or `out of scope`
- Reason for the proposed action

Wait for maintainer confirmation before proceeding. The maintainer may:

- **Approve** the proposed action for any individual Discussion
- **Override** the proposed action (e.g., classify a proposed "promote" as "out of scope")
- **Defer** a Discussion (leave it open for more signal, even if it meets the threshold)

Do not execute any action without maintainer confirmation.

### Step 6: Execute confirmed actions

#### Promote

1. Create a new GitHub issue using the format in the
   [Promoted Issue Format](#promoted-issue-format) section.
2. Close the Discussion with the following comment:

   > Your feedback has been promoted to issue #N. Thank you for contributing!
   > The issue will be reviewed alongside other backlog items and prioritized based on
   > roadmap fit and community signal.

#### Duplicate (open issue)

1. Comment on the Discussion:

   > Thank you for this feedback! This topic is already tracked in #N. You can follow or
   > comment there to add your context.

2. Close the Discussion.
3. Leave the existing issue unchanged (do not relabel or reprioritize automatically).

#### Duplicate (closed issue)

1. Comment on the Discussion noting that the issue is closed and showing the issue link.
2. Ask the maintainer (if not already done in Step 5) whether to:
   - Reopen the existing closed issue, or
   - Close the Discussion as already addressed.
3. Execute the maintainer's choice.

#### Out of scope

1. Close the Discussion with a polite, specific comment. **A generic "out of scope"
   comment without a brief explanation is not acceptable.** Use plain language explaining
   why the feedback is not being promoted. Examples:
   - "This appears to be a support question rather than a workflow template improvement
     request. For help configuring the template for your project, ..."
   - "This request is specific to a downstream project customisation rather than a
     change to the shared template workflow. The template intentionally leaves this
     configuration to individual project teams."

2. Do not create an issue.

---

## Promoted Issue Format

Issues created by this protocol must use the following template:

```markdown
## Community feedback source

GitHub Discussion: [Discussion title](Discussion URL)

## Summary

[Concise description of the request, 1–3 sentences]

## Signal

- Upvotes: N
- Comments: N (at time of triage: YYYY-MM-DD)

## Original feedback

> [Quoted or closely paraphrased content from the Discussion opening post]
```

**Required label**: `feedback-staging`

**Title**: derived from the Discussion title (verbatim or lightly edited for clarity).

---

## Scope Filter

### In scope for promotion

- Template workflow improvements (new or improved protocols, agent instructions, scripts)
- Tooling gaps in existing protocol scripts or agent instructions
- Protocol deficiencies (ambiguous, incomplete, or missing protocol steps)
- Configuration usability issues (`.ai-dev-workflow.yaml`, setup, onboarding)

### Out of scope (close with helpful comment, do not promote)

- Support questions ("How do I use X?")
- Project-specific (downstream) customisation requests ("Can you add support for my
  framework?")
- General questions not describing a deficiency or improvement
- Requests explicitly deferred in a prior "Out of Scope" spec section

When in doubt, default to the interactive mode and ask the maintainer.

---

## Closing Comments Are Mandatory

Every Discussion acted on by this protocol — whether promoted, marked as a duplicate,
or closed as out of scope — **must** receive a closing comment explaining the outcome
before it is closed. Silent closes are not permitted.

The comment must be specific. Do not use generic phrases like "closing this" or
"out of scope" without context. See the [Execute confirmed actions](#step-6-execute-confirmed-actions)
section for example wording.

---

## Related Documents

- [`CONTRIBUTING.md`](../../../../CONTRIBUTING.md) — directs external users to the
  "Feedback & Ideas" Discussions category and explains the triage process.
- [`06-retrospective-protocol.md`](06-retrospective-protocol.md) — adjacent periodic
  protocol for reviewing completed work.
- [`AGENTS.md`](../../../../AGENTS.md) — workflow commands table listing this protocol.
