# Cross-PR Closing Keyword Validation — Spec

---

## Overview

When several implementation pull requests run in parallel, one of them can declare a closing keyword for work that is actually shipping in a sibling pull request. GitHub then closes that issue as soon as the wrong pull request merges, and the issue drops out of the release it really belongs to — it lands on the board as merged, with no milestone, and nobody notices until someone reconciles the release by hand.

This feature warns the pull request author when a pull request declares that it closes an issue it does not appear to carry. The warning is advisory: it never blocks a merge, and a pull request that deliberately closes several issues can silence it. The intent is to surface a likely mistake while the batch is still in flight, when it costs one edit, rather than after a release has been assembled around the wrong scope.

---

## Use Cases

### Use Case 1: A pull request claims an issue that belongs to a sibling

**Actor**: The author of an implementation pull request — an agent running the development workflow, or a maintainer working by hand.
**Preconditions**: The pull request is open against an integration or development branch, and its text declares at least one closing keyword.

**Steps**:

1. The author opens the pull request, updates its description, or changes its labels.
2. The validation reads the closing keywords declared in the pull request description.
3. For each issue named, it establishes whether this pull request is the one carrying that issue's work.
4. It finds at least one issue that a *different* open pull request identifiably carries.
5. It reports the mismatch on the pull request.

**Postconditions**: The mismatch is visible on the pull request, and the pull request remains mergeable. No issue, label, or milestone has been changed.

**Information shown**:

- Which issue numbers look out of scope for this pull request.
- For each one, the other pull request that appears to carry it. A warning is only produced when that sibling can be named; the absence of evidence is never itself the reason.
- What to do next: remove the keyword, or record that closing several issues is intentional.

**Actions available**:

- Edit the pull request to drop the closing keyword for work it does not carry.
- Record the multi-issue intent, after which the warning stops.
- Do nothing — the pull request can still merge.

**Considerations**:

- Closing keywords that appear inside quoted prose or a code sample are not live references and must not be reported.
- An issue that no other pull request carries is not, on its own, evidence of a mistake — a pull request may legitimately be the first and only one to address it.
- The check must re-run when the pull request description changes, when its labels change, and when an open pull request whose branch names one of the issues appears or departs, so a corrected pull request stops warning — and a newly conflicted one starts — without anyone re-triggering it by hand.

---

### Use Case 2: A pull request closes only its own work

**Actor**: The author of an implementation pull request.
**Preconditions**: The pull request declares closing keywords, and every issue named is work this pull request carries.

**Steps**:

1. The author opens or updates the pull request.
2. The validation reads the declared closing keywords and finds every issue in scope.

**Postconditions**: No warning is produced, and nothing is added to the pull request.

**Information shown**:

- Nothing. A clean result is silent, so the warning keeps its signal value.

**Considerations**:

- A pull request that declares no closing keywords at all is also silent — this feature does not ask for closing keywords, it only checks the ones that are there.

---

### Use Case 3: A pull request deliberately closes several issues

**Actor**: The author of an implementation pull request that genuinely resolves more than one tracked item.
**Preconditions**: The pull request declares closing keywords for issues that the validation would otherwise report as out of scope.

**Steps**:

1. The author reads the warning and confirms the pull request really does resolve all of the issues named.
2. The author applies the label **`multi-issue-intentional`** to the pull request.
3. Applying the label re-runs the validation on its own; the author does not have to push anything.

**Postconditions**: The pull request carries the `multi-issue-intentional` label, and the warning no longer appears. Any warning already posted is cleared on the next run.

**Information shown**:

- The label is visible in the pull request's own label list, so a reviewer sees that the multi-issue scope was a decision rather than an oversight, without opening a comment thread.

**Considerations**:

- The label silences the warning for the whole pull request, not for one issue at a time. A per-issue opt-out is a finer instrument than the problem needs.
- Removing the label re-runs the validation and brings the warning back, with no push required, so the opt-out cannot be set once and silently outlive the reason for it.
- A label was chosen over a marker in the pull request description because the description is the very text this feature reads: an opt-out living there would have to be excluded from closing-keyword parsing, and an author editing the description to fix a keyword could drop the opt-out by accident.

---

## Business Rules

- The validation is **advisory only**. It never blocks a merge, never changes the mergeability of a pull request, and never edits an issue, label, milestone, or release.
- The validation reports on a pull request's **own declared closing keywords**, and only those. It does not infer that a pull request ought to close something.
- An issue named by a closing keyword is **in scope** for a pull request when that pull request is identifiably the one carrying its implementation, established from the ownership rule below. An issue identifiably carried by a *different* open pull request is **out of scope** and is reported.
- When ownership cannot be established either way, the validation **stays silent**. A warning that fires on absence of evidence would train people to ignore it.
- The validation reads the **pull request description**. It does not read the title or the commit messages.
- Within the description, what counts as quoted prose or a code sample — and is therefore **not a live reference** — follows the **filtering semantics of the canonical parser** (the one post-merge cleanup uses). This is agreement about how text is filtered, not about which text is read: the canonical parser additionally reads the title and the commit messages, and this feature deliberately does not.
- Because the input surfaces differ, a closing keyword that appears **only** in the title or in a commit message is outside what this feature examines. That gap is recorded in Out of Scope rather than papered over.
- The graduation closeout recognizes a narrower set of excluded constructs today. That difference is pre-existing, is neither introduced nor widened here, and reconciling the two parsers is not part of this feature.
- A pull request labelled **`multi-issue-intentional`** produces no warning, regardless of how many issues it names. The label is the only opt-out; there is no per-issue variant and no description marker.
- The opt-out is evaluated **at the time the validation runs**. Applying the label does not retroactively rewrite history, and removing it restores the warning on the next run.
- The result is **recomputed** whenever any input to it changes. Because ownership evidence lives on *other* pull requests, that is more than this pull request's own edits:
  - its description changes;
  - its labels change;
  - **ownership evidence for an issue it names changes** — another pull request whose branch names that issue opens, closes, or merges.
- A stale warning must not survive the edit that fixed it, and a stale **silence** must not survive the sibling that created the conflict. A pull request that was silent because no sibling existed must warn once a sibling appears, without anyone touching it.
- **Readiness backstop**: the result is re-evaluated when the pull request reaches readiness for human review, so no pull request can carry a silence that went stale while it waited.
- The validation is **read-only with respect to project state**: it may post or update its own report on the pull request, and does nothing else.

---

### Establishing ownership

"Identifiably carries" is not a judgement call. An open pull request carries an issue when, and only when, **its branch names that issue**. This repository's implementation branches are `<prefix>/<issue-number>-<slug>`, and the branch-name guard already enforces a bare numeric identifier, so the signal is set when the branch is cut and is what the rest of the workflow already keys off.

There is deliberately **one** signal. An earlier draft added the issue's tracker link as a second, lower-ranked signal, to catch work whose branch predates the convention or was renamed. It was removed: the platform creates an issue-to-pull-request link from the very closing keyword this feature examines, so a pull request that wrongly claimed an issue would be linked to it *because* of that claim, read as the issue's owner, and suppress the warning it was supposed to produce. Distinguishing a deliberately recorded link from a platform-derived one is not reliably observable, and a signal that cannot be classified deterministically is worse than no signal. Ownership by tracker linkage is recorded in Out of Scope.

Rules:

- **No open pull request's branch names the issue** → ownership is unestablished. Silent.
- **Two or more open pull requests' branches name the same issue** → ownership is contested, not established. Silent, because guessing which sibling is "the" owner is exactly the mistake this feature exists to catch.
- **The pull request being validated is itself the owner** → the issue is in scope. Silent.
- **A different open pull request is the owner** → the issue is out of scope. Reported.
- A closed or merged pull request is not considered. Only open pull requests can be a sibling owner, because only they represent work still in flight in the same batch.
- No link the platform derives from a closing keyword makes a pull request an owner, of its own issues or anyone else's.

---

## Operational Visibility

- **Where the warning appears**: on the pull request itself, as a single report that is updated in place rather than re-posted, so a pull request that is corrected and re-checked does not accumulate a stack of contradictory warnings.
- **What a clean result looks like**: nothing is posted. Silence is the clean signal.
- **Audit trail**: the `multi-issue-intentional` label stays on the pull request after merge, so a later release reconciliation can tell a deliberate multi-issue pull request from an accidental one.

---

## Decision-Gate Consistency Matrix

This feature is a workflow decision gate: its outcome depends on several inputs, and its filtering has to agree with the canonical parser that decides what actually gets closed. The matrix below is the canonical statement of that behavior; every row is reflected in an acceptance criterion.

### Gate inputs

| Input | Where it comes from | Why it matters |
| --- | --- | --- |
| Declared closing keywords in the pull request description | The description only — not the title, not the commit messages — filtered by the canonical parser's semantics | The set of issues the description claims to close |
| Sibling ownership of each named issue | The branch names of the other **open** pull requests | Establishes whether a different pull request identifiably carries that issue |
| `multi-issue-intentional` label | The pull request's labels | Author's recorded statement that multi-issue scope is deliberate |
| Existing validation report | The pull request's own prior report, if any | Decides whether to update or clear rather than post again |
| Sibling lifecycle events | Another pull request whose branch names the same issue opening, closing, or merging | Ownership evidence is mutable and lives outside this pull request, so it is an input in its own right |

The gate re-evaluates on a change to any of its inputs: the pull request's description, its labels, or the set of open pull requests whose branches name the issues it declares. A label change is a trigger in its own right — applying the opt-out clears an existing warning, and removing it restores one, without waiting for a push. A sibling opening, closing, or merging is likewise a trigger for every pull request whose result could turn on it, and readiness re-evaluates as a backstop.

### Allowed outcomes and required next actions

| Inputs | Outcome | What the validation does | Author's next action |
| --- | --- | --- | --- |
| No declared closing keywords | Silent | Nothing posted; any prior report cleared | None |
| All named issues carried by this pull request | Silent | Nothing posted; any prior report cleared | None |
| At least one named issue identifiably carried by a sibling, label absent | **Warning** | Posts or updates one report naming each out-of-scope issue and its sibling | Drop the keyword, or apply `multi-issue-intentional` |
| At least one named issue identifiably carried by a sibling, label present | Silent | Clears any prior report | None |
| Ownership cannot be established for a named issue — no signal on any open pull request | Silent **for that issue** | That issue is not reported; other issues are judged on their own | None |
| Ownership is contested — the same rank points at two or more open pull requests | Silent **for that issue** | Not reported; guessing an owner is the mistake this feature exists to catch | None |

No input combination blocks a merge, changes mergeability, or edits an issue, label, milestone, or release.

### Mirror surfaces

| Surface | Relationship | Consistency requirement |
| --- | --- | --- |
| Post-merge cleanup's closing-keyword reading | Decides what actually gets closed; reads the title, description, and commit messages | **Canonical for filtering semantics only.** Within the description, the validation must exclude exactly what this parser excludes, so a warning cannot contradict what gets closed. The input surfaces are *not* identical — this feature reads the description alone. |
| Graduation closeout's closing-keyword reading | Same parsing question on graduation pull requests | **Deliberately not mirrored.** It recognizes a narrower set of non-live references than the canonical parser does today. Unchanged by this feature, and reconciling the two is out of scope. |
| Release-scope ancestry gate | Consumes the consequences of a wrongly closed issue | Out of scope here; this feature reduces how often that gate sees the problem, and changes none of its behavior |

### Examples

| Pull request text | Outcome | Reason |
| --- | --- | --- |
| `Closes #1630` where a sibling pull request carries #1630 | Warning | The originating incident: a sibling's issue closed early |
| `Closes #1630` inside a fenced code sample | Silent | Not a live reference |
| `This does not disclose #1630` | Silent | `disclose` merely contains a closing keyword as a substring |
| `Closes #1630` with `multi-issue-intentional` applied | Silent | Author recorded deliberate multi-issue scope |
| `Closes #1630` where no pull request carries #1630 | Silent | Ownership not established; absence of evidence is not a warning |

### Issue-objective traceability

| #1644 objective | Disposition |
| --- | --- |
| PR validation, warn or block | Covered as **warn** over the description; blocking, and keywords outside the description, are Out of Scope |
| Reviewer-loop or prepare-commit blocking finding | Out of Scope, item 2 |
| Release-cleanup report for merged-but-omitted items | Out of Scope, item 3 |
| False positives minimized | Business Rules, including the single-signal ownership rule and the exclusion of platform-derived links; ACs 5-7, 12-17 |
| Documented opt-out for intentional multi-issue pull requests | Use Case 3; ACs 8-10 |
| Tests for parser and validator edge cases | ACs 5-7 and 12-20 — AC 6 covers parity with every construct the canonical parser excludes; ACs 12-17 the ownership rule with its contested, no-signal, platform-link and closed-sibling cases; ACs 18-20 the sibling-lifecycle and readiness triggers |

---

## Acceptance Criteria

- [ ] A pull request whose description declares a closing keyword for an issue that a different open pull request identifiably carries produces a warning naming that issue number, and the pull request remains mergeable.
- [ ] The warning names, for each reported issue, the pull request that appears to carry it.
- [ ] A pull request whose declared closing keywords all name work it carries produces no warning and no comment.
- [ ] A pull request that declares no closing keywords produces no warning and no comment.
- [ ] A closing keyword that appears only inside a fenced code sample or a quoted line in the pull request description is not reported.
- [ ] A closing keyword in the description is not reported when it appears inside any construct the canonical parser excludes: a backtick fence, a tilde fence, an inline code span, a code span spanning several lines, a blockquote, or a fence left unclosed. A keyword outside all of these is treated as a live reference and proceeds to scope evaluation; it is reported only when a sibling identifiably carries the issue and the `multi-issue-intentional` label is absent.
- [ ] A word that merely contains a closing keyword as a substring — for example "disclose" or "hotfix" — is not reported.
- [ ] A pull request carrying the `multi-issue-intentional` label produces no warning, even when its closing keywords name issues that another pull request carries.
- [ ] Applying the `multi-issue-intentional` label to an already-warned pull request clears the existing warning, without any push to the pull request.
- [ ] Removing the `multi-issue-intentional` label makes the warning reappear, without any push to the pull request.
- [ ] Editing a warned pull request to drop the out-of-scope closing keyword makes the warning clear on the next run, without leaving a stale warning behind.
- [ ] When no open pull request carries an issue named by a closing keyword, no warning is produced for it.
- [ ] When two open pull requests both name the same issue in their branch, ownership is contested and no warning is produced for that issue.
- [ ] A pull request whose only connection to an issue is the platform link derived from its own closing keyword is **not** treated as that issue's owner, and still produces a warning when a sibling's branch names the issue.
- [ ] A pull request whose branch does not name an issue it declares is not treated as that issue's owner, whatever the issue's tracker item links.
- [ ] A closed or merged pull request is never treated as the sibling owner.
- [ ] A pull request that was silent because no sibling carried the issue warns once a sibling pull request naming that issue opens, without any change to the pull request being warned.
- [ ] A pull request that was warning stops warning once the sibling that carried the issue closes or merges, without any change to the pull request being warned.
- [ ] A pull request reaching readiness for human review has its result re-evaluated, so a silence that went stale while it waited is corrected before a human reviews it.
- [ ] Running the validation twice on an unchanged pull request leaves a single report, not two.

---

## Out of Scope (MVP)

- **Blocking mode.** The issue offers "warn or block"; this iteration warns only. Nothing here prevents a later decision to escalate.
- **A blocking or important finding in the automated reviewer loop.** Option 2 of the issue.
- **A release-cleanup report for merged issues absent from an assembled changelog section.** Option 3 of the issue, which the issue itself marks optional and frames as a complement to the existing ancestry gate.
- **Per-issue opt-out.** The opt-out is the `multi-issue-intentional` label, which applies to the whole pull request.
- **Any opt-out mechanism other than the label** — a description marker, a checkbox, or a magic comment.
- **Retroactive scanning of already-merged pull requests.** This feature looks at open pull requests going forward; it does not reconcile history.
- **Closing keywords outside the description.** The canonical parser also honours the title and the commit messages, so a cross-PR keyword placed there is not caught here. This follows the agreed scope — pull request *description* validation — and is a known residual gap, not an oversight.
- **Changing how closing keywords are parsed anywhere else.** The existing post-merge cleanup and graduation closeout keep their current behavior; this feature reads, it does not redefine.
- **Ownership established by tracker linkage.** Branch naming is the only ownership signal. A pull request whose branch does not name an issue is never treated as its owner, so work whose branch predates the naming convention or was renamed produces silence rather than a warning.
- **Reconciling the two existing parsers with each other.** They disagree today about which non-live references to exclude. This feature follows the canonical one and leaves the divergence exactly as it found it; unifying them is separate work.
- **Any automatic correction.** The validation never edits a pull request description, reopens an issue, or restores a milestone.
