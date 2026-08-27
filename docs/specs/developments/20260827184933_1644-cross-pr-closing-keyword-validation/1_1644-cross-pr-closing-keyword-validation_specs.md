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

1. The author opens the pull request, or updates its description or commits.
2. The validation reads the pull request's own declared closing keywords.
3. For each issue named, it establishes whether this pull request is the one carrying that issue's work.
4. It finds at least one issue that this pull request does not appear to carry.
5. It reports the mismatch on the pull request.

**Postconditions**: The mismatch is visible on the pull request, and the pull request remains mergeable. No issue, label, or milestone has been changed.

**Information shown**:

- Which issue numbers look out of scope for this pull request.
- For each one, why it looks out of scope — the other pull request that appears to carry it, or the absence of any evidence that this pull request does.
- What to do next: remove the keyword, or record that closing several issues is intentional.

**Actions available**:

- Edit the pull request to drop the closing keyword for work it does not carry.
- Record the multi-issue intent, after which the warning stops.
- Do nothing — the pull request can still merge.

**Considerations**:

- Closing keywords that appear inside quoted prose or a code sample are not live references and must not be reported.
- An issue that no other pull request carries is not, on its own, evidence of a mistake — a pull request may legitimately be the first and only one to address it.
- The check must re-run when the pull request text changes, so a corrected pull request stops warning without anyone re-triggering it by hand.

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
2. The author records the multi-issue intent on the pull request.
3. The validation runs again on the next update.

**Postconditions**: The pull request carries a durable, visible record that its multi-issue scope is deliberate, and the warning no longer appears.

**Information shown**:

- The opt-out is visible on the pull request itself, so a reviewer can see that the multi-issue scope was a decision rather than an oversight.

**Considerations**:

- The opt-out silences the warning for the whole pull request, not for one issue at a time. A per-issue opt-out is a finer instrument than the problem needs.
- Removing the opt-out brings the warning back on the next update, so it cannot be set once and silently outlive the reason for it.

---

## Business Rules

- The validation is **advisory only**. It never blocks a merge, never changes the mergeability of a pull request, and never edits an issue, label, milestone, or release.
- The validation reports on a pull request's **own declared closing keywords**, and only those. It does not infer that a pull request ought to close something.
- An issue named by a closing keyword is **in scope** for a pull request when that pull request is identifiably the one carrying its implementation. An issue whose implementation is identifiably carried by a different pull request is **out of scope** and is reported.
- When scope cannot be established either way, the validation **stays silent**. A warning that fires on absence of evidence would train people to ignore it.
- Closing keywords that appear inside quoted prose or a code sample are **not live references** and are never reported. This matches how the existing post-merge cleanup already reads pull request text, so the two cannot disagree about what a pull request claims to close.
- A pull request that records **intentional multi-issue scope** produces no warning, regardless of how many issues it names.
- The result is **recomputed** whenever the pull request's text changes. A stale warning must not survive the edit that fixed it.
- The validation is **read-only with respect to project state**: it may post or update its own report on the pull request, and does nothing else.

---

## Operational Visibility

- **Where the warning appears**: on the pull request itself, as a single report that is updated in place rather than re-posted, so a pull request that is corrected and re-checked does not accumulate a stack of contradictory warnings.
- **What a clean result looks like**: nothing is posted. Silence is the clean signal.
- **Audit trail**: the opt-out is recorded on the pull request, so a reviewer or a later release reconciliation can see that a multi-issue pull request was deliberate.

---

## Acceptance Criteria

- [ ] A pull request whose description declares a closing keyword for an issue that a different open pull request identifiably carries produces a warning naming that issue number, and the pull request remains mergeable.
- [ ] The warning names, for each reported issue, the pull request that appears to carry it.
- [ ] A pull request whose declared closing keywords all name work it carries produces no warning and no comment.
- [ ] A pull request that declares no closing keywords produces no warning and no comment.
- [ ] A closing keyword that appears only inside a fenced code sample or a quoted line in the pull request description is not reported.
- [ ] A word that merely contains a closing keyword as a substring — for example "disclose" or "hotfix" — is not reported.
- [ ] A pull request that records intentional multi-issue scope produces no warning, even when its closing keywords name issues that another pull request carries.
- [ ] Removing the record of intentional multi-issue scope makes the warning reappear on the next run.
- [ ] Editing a warned pull request to drop the out-of-scope closing keyword makes the warning clear on the next run, without leaving a stale warning behind.
- [ ] When scope cannot be established for an issue, no warning is produced for it.
- [ ] Running the validation twice on an unchanged pull request leaves a single report, not two.

---

## Out of Scope (MVP)

- **Blocking mode.** The issue offers "warn or block"; this iteration warns only. Nothing here prevents a later decision to escalate.
- **A blocking or important finding in the automated reviewer loop.** Option 2 of the issue.
- **A release-cleanup report for merged issues absent from an assembled changelog section.** Option 3 of the issue, which the issue itself marks optional and frames as a complement to the existing ancestry gate.
- **Per-issue opt-out.** The opt-out is per pull request.
- **Retroactive scanning of already-merged pull requests.** This feature looks at open pull requests going forward; it does not reconcile history.
- **Changing how closing keywords are parsed anywhere else.** The existing post-merge cleanup and graduation closeout keep their current behavior; this feature reads, it does not redefine.
- **Any automatic correction.** The validation never edits a pull request description, reopens an issue, or restores a milestone.
