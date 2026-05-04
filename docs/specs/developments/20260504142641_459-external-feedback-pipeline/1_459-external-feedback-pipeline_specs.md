# External Feedback Pipeline: GitHub Discussions Staging and Triage Protocol — Spec

**Issue**: #459

---

## Overview

External users of the template repository currently have no structured way to contribute feedback without opening GitHub issues directly, which pollutes the backlog with unfiltered, potentially duplicate, or low-signal items. This feature introduces a two-part feedback pipeline: a GitHub Discussions category as a public staging area for external feedback, and a triage protocol that periodically reviews staged discussions, filters by community signal, deduplicates against the existing backlog, and deliberately promotes high-quality items into tracked issues.

---

## Brief Coverage

| Brief Objective | Spec Trace |
|---|---|
| Enable GitHub Discussions with a "Feedback & Ideas" category as the public intake point | AC-1, Use Case 1 |
| Add a `CONTRIBUTING.md` or README section directing external users to Discussions (not Issues) | AC-2, Use Case 1 |
| Add a feedback triage protocol defining cadence, promotion criteria, and duplicate handling | AC-3, AC-4, Use Cases 2–4, Business Rules |
| Optionally update the retrospective protocol to include a triage step | Out of scope (MVP) — see Out of Scope section |

---

## Use Cases

### Use Case 1: External User Submits Feedback via Discussions

**Actor**: External user (template consumer or community member without write access to the repository)
**Preconditions**: GitHub Discussions is enabled on the template repository with a "Feedback & Ideas" category

**Steps**:
1. The external user visits the repository and finds a link to GitHub Discussions in `CONTRIBUTING.md` or the repository README
2. The user opens a new Discussion in the "Feedback & Ideas" category describing their feedback, problem, or idea
3. Other community members can upvote (thumbs-up reaction on the opening post) or comment on the Discussion
4. The Discussion remains open and visible until a maintainer triages it

**Postconditions**: The feedback exists as a GitHub Discussion entry, separate from the Issues backlog, with community signal accruing over time

**Information shown**:
- The Discussion title, body, author, creation date, reaction count (upvotes), and comment count are all visible on the repository's Discussions page
- The Discussions page shows all entries in the "Feedback & Ideas" category

**Actions available**:
- Any GitHub user can react (upvote) or comment on the Discussion
- The Discussion author can edit their post
- Maintainers can close, lock, or convert the Discussion

**Considerations**:
- External users are not required to have write access to the repository
- The Discussions intake is not a commitment to implement any item; CONTRIBUTING.md should set this expectation
- If a user opens a GitHub Issue instead of a Discussion, maintainers may redirect them to Discussions and close the issue

---

### Use Case 2: Maintainer Runs the Feedback Triage Protocol

**Actor**: Maintainer (repository owner or designated triage runner) invoking the triage protocol periodically
**Preconditions**: GitHub Discussions is enabled; the "Feedback & Ideas" category has at least one open Discussion

**Steps**:
1. The maintainer invokes the triage protocol (e.g., via `/run-feedback-triage` or by following the protocol document)
2. The triage runner queries all open Discussions in the "Feedback & Ideas" category
3. For each Discussion, the runner evaluates the signal threshold (see Business Rules)
4. Discussions that meet the signal threshold are candidates for promotion; those that do not are skipped
5. For each candidate Discussion, the runner checks for duplicates against existing open backlog issues (see Business Rules)
6. If a duplicate is found, the runner comments on the Discussion linking to the existing issue and marks the Discussion as a duplicate (closes it with a note)
7. If no duplicate is found and the Discussion is in scope, the runner creates a structured backlog issue linked to the Discussion
8. The Discussion is closed with a comment explaining the outcome (promoted to issue, duplicate, or out of scope)

**Postconditions**: Each candidate Discussion has been either promoted to a backlog issue, linked to an existing duplicate, or explicitly closed as out of scope

**Information shown**:
- For each processed Discussion: its title, signal metrics (upvote count, comment count), the outcome (promoted, duplicate, out of scope), and — if promoted — the newly created issue number and URL

**Actions available**:
- The maintainer may override the triage runner's assessment for any individual Discussion before it is acted on
- The maintainer may defer a Discussion (leave it open for more signal) even if it meets the threshold

**Considerations**:
- The triage protocol is run on-demand, not automatically; the cadence is a guideline (see Business Rules), not a hard trigger
- The runner should present a preview of proposed actions and wait for maintainer confirmation before creating issues or closing Discussions in the default (interactive) mode
- A non-interactive mode (for scripted or CI use) is out of scope for the initial version

---

### Use Case 3: Duplicate Found During Triage

**Actor**: Triage runner (agent or maintainer following the protocol)
**Preconditions**: A candidate Discussion has met the signal threshold; a matching open backlog issue already exists

**Steps**:
1. The triage runner identifies a duplicate match between the Discussion and an existing open issue (see Business Rules: Duplicate detection)
2. The runner comments on the Discussion with a message acknowledging the feedback and linking to the existing issue
3. The runner closes the Discussion

**Postconditions**: The Discussion is closed; the existing issue is unchanged (or optionally updated with a note that community interest exists)

**Information shown**:
- Comment on the Discussion: "Thank you for this feedback! This topic is already tracked in [issue link]. You can follow or comment there to add your context."

**Actions available**:
- The maintainer may choose to update the linked issue with a note that community interest was signaled via Discussion

**Considerations**:
- The existing issue is not automatically relabeled or reprioritized; the triage runner surfaces the signal and leaves prioritization to the maintainer
- If the existing issue is closed (resolved or won't-fix), the triage runner notes this and lets the maintainer decide whether to reopen

---

### Use Case 4: Triage Runner Classifies a Discussion as Out of Scope

**Actor**: Triage runner (agent or maintainer following the protocol)
**Preconditions**: A candidate Discussion met the signal threshold but its content is outside the template's defined scope, is a support request, or is a duplicate of a previously closed and resolved issue

**Steps**:
1. The triage runner identifies the Discussion as out of scope (not a template workflow improvement, not actionable as a backlog item, or requesting something explicitly excluded)
2. The runner closes the Discussion with a polite, informative comment explaining why the feedback is not being promoted

**Postconditions**: The Discussion is closed with a clear explanation

**Information shown**:
- Comment on the Discussion: a brief acknowledgment of the feedback, a clear explanation of why it is not being promoted (e.g., out of scope, a support question rather than a feature request, or already resolved upstream), and optionally a pointer to where the user can get help or follow up

**Considerations**:
- "Out of scope" determinations should use plain language; the triage runner should not be dismissive
- In interactive mode, the maintainer confirms the out-of-scope classification before the Discussion is closed

---

## Business Rules

- **Signal threshold**: A Discussion is a candidate for promotion when it has at least 3 upvote reactions on the opening post OR at least 2 comments from distinct users (other than the original poster). Both conditions are checked independently — meeting either one qualifies the Discussion.
- **Triage cadence**: The triage protocol is recommended to run at least once per month. The cadence is a guideline; the protocol does not enforce a schedule and does not block on missing runs.
- **Duplicate detection**: A Discussion is considered a duplicate when the Discussion title and body share 3 or more significant keywords with an existing issue's title or body, or when the affected file paths or protocol names are identical. Duplicate detection covers both open **and closed** issues: if the best match is a closed issue (resolved or won't-fix), the triage runner surfaces it as a "potential resolved duplicate" and asks the maintainer to decide whether to reopen or close the Discussion as already addressed. Keyword matching excludes common stopwords ("the", "a", "is", "in", "to", "of", "and", "or", "for"). When match confidence is ambiguous, the triage runner presents both the potential match and "No strong existing item found" and asks the maintainer to decide.
- **Scope filter**: Only Discussions describing template workflow improvements, tooling gaps, protocol deficiencies, or configuration usability issues are in scope for promotion. Support questions, project-specific (downstream) customization requests, and general questions are out of scope and should be closed with a helpful comment rather than promoted.
- **No automatic backlog population**: No Discussion is automatically converted to an issue without a triage run. Community signal accumulates passively; conversion is always a deliberate, reviewed decision.
- **Label discipline**: Issues created from triaged Discussions must be labeled `feedback-staging` to distinguish them from internally generated backlog items. The `feedback-staging` label indicates the item originated from a community Discussion rather than a retrospective or internal planning session.
- **Promoted issue format**: Issues created by the triage protocol must include: a title derived from the Discussion title, a body with the following sections — "Community feedback source" (link to the originating Discussion), "Summary" (concise description of the request), "Signal" (upvote count and comment count at time of triage), and "Original feedback" (quoted or paraphrased content from the Discussion). The issue must be labeled `feedback-staging`.
- **Closing comments are mandatory**: Every Discussion acted on by the triage protocol (promoted, duplicate, or out of scope) must receive a closing comment explaining the outcome before it is closed. Silent closes are not permitted.
- **Interactive mode is the default**: When the triage protocol is followed by an agent, the default behavior is to present a preview of proposed actions and wait for maintainer confirmation before executing. Batch execution without confirmation is not permitted in the initial version.

---

## UX Rules

- CONTRIBUTING.md (or the equivalent README section) must be written in a welcoming, clear tone that explains both how to submit feedback and what to expect (no guaranteed implementation, periodic triage, community signal matters)
- The signal threshold values (3 upvotes or 2 comments) must be visible in the triage protocol document so that external users who read `CONTRIBUTING.md` can understand how feedback is evaluated
- Closing comments on Discussions must always be polite and specific; a generic "closing as out of scope" without a brief explanation is not acceptable
- The "Feedback & Ideas" category description (set in GitHub Discussions settings) should briefly explain the purpose and point to CONTRIBUTING.md for full details

---

## Acceptance Criteria

- [ ] AC-1: A "Feedback & Ideas" GitHub Discussions category exists on the repository (documented as a setup step in the triage protocol or CONTRIBUTING.md, since category creation is a manual GitHub UI action)
- [ ] AC-2: A `CONTRIBUTING.md` file exists in the repository root (or an equivalent section in README.md if the project already has one) that directs external users to submit feedback via GitHub Discussions rather than opening Issues, and briefly explains the triage process and signal threshold
- [ ] AC-3: A triage protocol document exists at `docs/workflow/development-workflow/protocols/07-feedback-triage-protocol.md` (or as a clearly titled standalone document) that defines: how to query open Discussions in the "Feedback & Ideas" category, the signal threshold (3 upvotes OR 2 comments), duplicate detection criteria, scope filter criteria, the format for promoted issues, and the closing comment requirements
- [ ] AC-4: The `feedback-staging` label exists in the repository (or is documented as a setup step) and its purpose is described in the triage protocol
- [ ] AC-5: A triage run following the protocol against a sample Discussion (real or simulated) produces the correct outcome: a Discussion meeting the threshold and not matching any existing issue results in a new issue labeled `feedback-staging` with a link to the originating Discussion; a duplicate Discussion is closed with a comment linking to the existing issue; an out-of-scope Discussion is closed with a polite explanatory comment
- [ ] AC-6: The triage protocol specifies the recommended cadence (at least monthly) and documents how to invoke it (command, agent name, or manual steps)

---

## Out of Scope (MVP)

- Automatic triage without maintainer confirmation (non-interactive batch mode)
- Integration with issue trackers other than GitHub Issues / GitHub Projects (Linear, Jira, etc.) — the initial version is GitHub-only
- Automated signal monitoring (e.g., a scheduled GitHub Action that notifies the maintainer when a Discussion reaches the threshold) — this can be added in a follow-up
- Updating the retrospective protocol (06-retrospective-protocol.md) to include a triage step — this is desirable but deferred to avoid expanding the scope of this item; it can be added as a follow-up item once the triage protocol is established
- Weighting or scoring of Discussions beyond the simple threshold (e.g., sentiment analysis, author reputation)
- A script or CLI tool for automated Discussion querying — the initial version documents the manual `gh` CLI steps in the protocol; automation can be added in a follow-up
- Moderation features (marking Discussions as spam, blocking users)
