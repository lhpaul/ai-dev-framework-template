# Cross-PR Closing Keyword Validation — Spec

---

## Overview

When several implementation pull requests run in parallel, one of them can declare a closing keyword for work that is actually shipping in a sibling pull request. GitHub then closes that issue as soon as the wrong pull request merges, and the issue drops out of the release it really belongs to — it lands on the board as merged, with no milestone, and nobody notices until someone reconciles the release by hand.

This feature warns the pull request author when a pull request declares that it closes an issue it does not appear to carry. The warning is advisory: it never blocks a merge, and a pull request that deliberately closes several issues can silence it. The intent is to surface a likely mistake while the batch is still in flight, when it costs one edit, rather than after a release has been assembled around the wrong scope.

---

## Use Cases

### Use Case 1: A pull request claims an issue that belongs to a sibling

**Actor**: The author of an implementation pull request — an agent running the development workflow, or a maintainer working by hand.
**Preconditions**: The pull request is an open implementation pull request **originating from a branch in this repository**, and its description declares at least one closing keyword. The base branch does not decide **whether** a pull request is validated — a hotfix targeting the default branch can close a sibling's issue just as an ordinary fix targeting the development branch can, so none is exempt. It does decide **how**: it selects which closer will act, and therefore whether the title contributes filtering state. See the filtering table in Business Rules.

Fork-originated pull requests are out of scope. This repository requires a same-repository guard on every automated step that writes to it — posting comments included — so a warning could not be posted on a fork pull request without breaking that rule. The residual risk is recorded in Out of Scope rather than left implied.

**Steps**:

1. The author opens the pull request, updates its description, or changes its labels.
2. The validation reads the closing keywords declared in the pull request description.
3. For each issue named, it establishes whether this pull request is the one carrying that issue's work.
4. It finds at least one issue that a *different* open pull request identifiably carries.
5. It reports the mismatch on the pull request.

**Postconditions**: The mismatch is visible on the pull request, and the pull request remains mergeable. No issue, milestone or release has been changed, and no label has been applied to or removed from any pull request. The `multi-issue-intentional` label may have been *created* in the repository if it did not exist, so the author can reach the opt-out the warning points them at.

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

- The validation is **advisory only**. It never blocks a merge, never changes the mergeability of a pull request, and never edits an issue, milestone or release. It never applies or removes a label on any pull request — applying and removing the opt-out is the author's act, never the validation's. Creating the `multi-issue-intentional` label in a repository that lacks it is the single exception, and it is definitional rather than incidental: an opt-out an author cannot reach is not an opt-out.
- The validation reports on a pull request's **own declared closing keywords**, and only those. It does not infer that a pull request ought to close something.
- An issue named by a closing keyword is **in scope** for a pull request when that pull request is identifiably the one carrying its implementation, established from the ownership rule below. An issue identifiably carried by a *different* open pull request is **out of scope** and is reported.
- When ownership cannot be established either way, the validation **stays silent**. A warning that fires on absence of evidence would train people to ignore it.
- The validation **reports** only closing keywords found in the **pull request description**. It never reports one found only in the title or in a commit message.
- **Which filtering applies depends on who will do the closing.** Two different closers exist, and the validation must agree with whichever one will act on this pull request:

| Pull request merges to | Who closes the issue | Filtering the validation must match |
| --- | --- | --- |
| A branch that is **not** the default branch — the ordinary development and integration case | The repository's own cleanup, which reads the title and description as one piece of text before filtering | Filtering state is established from the **title and description together**, so an unclosed fence opened in the title suppresses what follows it in the description |
| The **default branch** — the hotfix case | The platform, natively, from the description | The **description is filtered on its own**; a fence opened in the title does not suppress anything, because the platform never saw the title as part of that text |

- In both cases, reporting still comes from the description alone. What changes between them is only which text establishes filtering state.
- Matching the wrong closer in either direction would break the guarantee: filtering the description in isolation for a development pull request would report a keyword the cleanup will never act on, and inheriting title state for a hotfix would stay silent on a keyword the platform will act on.
- Within the description, what counts as quoted prose or a code sample — and is therefore **not a live reference** — follows the **filtering semantics of the canonical parser** (the one post-merge cleanup uses). This is agreement about how text is filtered, not about which text is read: the canonical parser additionally reads the title and the commit messages, and this feature deliberately does not.
- Because the input surfaces differ, a closing keyword that appears **only** in the title or in a commit message is outside what this feature examines. That gap is recorded in Out of Scope rather than papered over.
- The graduation closeout recognizes a narrower set of excluded constructs today. That difference is pre-existing, is neither introduced nor widened here, and reconciling the two parsers is not part of this feature.
- A pull request labelled **`multi-issue-intentional`** produces no warning, regardless of how many issues it names. The label is the only opt-out; there is no per-issue variant and no description marker.
- The opt-out is evaluated **at the time the validation runs**. Applying the label does not retroactively rewrite history, and removing it restores the warning on the next run.
- The result is **recomputed** whenever any input to it changes. Because ownership evidence lives on *other* pull requests, that is more than this pull request's own edits:
  - its description changes;
  - **its title changes**, for a pull request merging to a non-default branch, where the title contributes filtering state — adding or removing an unclosed fence in the title flips whether a description reference is live, with the description untouched;
  - its labels change;
  - **its base branch changes** — retargeting between the default branch and a non-default branch swaps which closer will act, and therefore which filtering applies, without a single character of the description changing;
  - **ownership evidence for an issue it names changes** — another pull request whose branch names that issue opens, closes, or merges.
- A stale warning must not survive the edit that fixed it, and a stale **silence** must not survive the sibling that created the conflict. A pull request that was silent because no sibling existed must warn once a sibling appears, without anyone touching it.
- **Readiness backstop**: the result is re-evaluated when the pull request reaches readiness for human review, so no pull request can carry a silence that went stale while it waited.
- The validation is **read-only with respect to project state**, with one exception: it may post or update its own report on the pull request, and it may create the `multi-issue-intentional` label if the repository does not have it yet. It does nothing else.
- **The opt-out label must exist before an author can use it.** A fresh installation of this template does not have it, and the workflow's own bootstrap provisions only the readiness labels. The validation therefore creates it idempotently on first use — the same pattern the repository already uses for `ready-for-regression`, including tolerating a concurrent creator. An opt-out an author cannot reach is not an opt-out.
- **A failed label creation does not suppress the warning.** Provisioning is a convenience, not an input to the decision: if creating the label fails — a transient error, or insufficient permission — the validation still knows whether the pull request claims a sibling's issue, and still says so. The report additionally states that the opt-out label could not be created and names it, so an author who needs the opt-out knows what to create by hand. Treating this as indeterminate would suppress a true warning over a label, which is the wrong trade in a feature whose whole purpose is to raise that warning.
- **A later result always wins.** Triggers overlap — a sibling can open moments before an author applies the opt-out — so two runs can be in flight at once and finish out of order. Two rules together make the outcome deterministic:
  - **Freshness.** A run publishes only if the inputs it read are still current at the moment it writes. If any of them moved while it was working, it discards its result and leaves the newer run's standing.
  - **Ordering.** Writes for one pull request are serialized, and each published result records which run produced it. A run never overwrites a result published by a run that started later than itself, even when both read identical inputs — duplicate deliveries and manual re-runs produce exactly that case, and freshness alone cannot see it, because neither run observes an input moving.
- Between them: an older run must never restore a warning a newer one cleared, clear one a newer one raised, or replace a newer conclusive check with "did not conclude".
- **A failure is never read as a clean result.** If **any** gate input cannot be read — the description or its filtering, the open pull requests, the opt-out label, the base branch, or this pull request's existing report — the outcome is *indeterminate*. The rule is deliberately about the whole input set rather than a list of the likeliest failures: treating an unreadable label as absent would warn despite an opt-out, an unreadable base branch would pick the wrong filtering, and an unreadable existing report would post a duplicate. In every case the outcome is the same: any existing report is left untouched and no new report is posted. The canonical parser already draws this distinction deliberately, and for the same reason — a transient platform error must not be allowed to erase a valid warning by looking like "no closing keywords found".
- **A conclusive run always supersedes an indeterminate one.** Every conclusive outcome — silent or warning — replaces the check conclusion left by an earlier indeterminate run on the same pull request, so the neutral "did not conclude" signal never outlives the failure that caused it. A clean result that posts no report still updates that check; otherwise the documented re-run would never produce an unambiguously conclusive state.
- **An indeterminate run is visible without being blocking.** It is surfaced in two places: the run's own log, which names what could not be read, and a **neutral**, non-blocking check conclusion on the pull request, so an author can see that the validation did not conclude. It is never a failing check. Nothing about it changes mergeability, contributes a required check, or blocks a merge — the advisory-only guarantee holds for failures exactly as it holds for warnings. An author who wants a conclusive result re-runs it once the transient condition clears; nobody is required to.
- The validation is **never posted on a fork-originated pull request**, because this repository forbids automated writes on those. Such a pull request is not validated at all rather than validated silently.

---

### Establishing ownership

"Identifiably carries" is not a judgement call. An open pull request carries an issue when, and only when, **its branch names that issue**. The signal is set when the branch is cut, and it is what the rest of the workflow already keys off.

Only an **implementation** pull request can own an issue. Its branch prefix must be one of `feature/`, `fix/`, `refactor/`, `hotfix/`, or `backport/hotfix/`. A `spec/` or `implementation-plan/` branch names the same issue number by design — those are the earlier stages of the same item — but it carries the item's documentation, not its implementation, and treating one as the owner would produce a false warning against a sibling, or make ownership look contested when it is not.

A branch names an issue in either of the two forms the branch-name guard accepts:

| Form | Example | The issue it names |
| --- | --- | --- |
| Bare number | `fix/1858-some-slug` | 1858 |
| Team-prefixed | `fix/lh-97-some-slug` | 97 |

**The issue is the numeric part, with any team prefix ignored.** A team-prefixed branch names the same issue as the bare-number form, so a sibling on `fix/lh-97-some-slug` is the owner of issue 97 exactly as one on `fix/97-some-slug` would be. Reading only the bare-number form would leave every team-prefixed sibling invisible, and the warning would go silent on precisely the mistake it exists to catch.

There is deliberately **one** signal. An earlier draft added the issue's tracker link as a second, lower-ranked signal, to catch work whose branch predates the convention or was renamed. It was removed: the platform creates an issue-to-pull-request link from the very closing keyword this feature examines, so a pull request that wrongly claimed an issue would be linked to it *because* of that claim, read as the issue's owner, and suppress the warning it was supposed to produce. Distinguishing a deliberately recorded link from a platform-derived one is not reliably observable, and a signal that cannot be classified deterministically is worse than no signal. Ownership by tracker linkage is recorded in Out of Scope.

Rules:

- **No open implementation pull request's branch names the issue** → ownership is unestablished. Silent. Open `spec/` or `implementation-plan/` pull requests for the same issue do not count and do not change this.
- **Two or more open implementation pull requests' branches name the same issue** → ownership is contested, not established. Silent, because guessing which sibling is "the" owner is exactly the mistake this feature exists to catch.
- **The pull request being validated is itself the owner** → the issue is in scope. Silent.
- **A different open pull request is the owner** → the issue is out of scope. Reported.
- A closed or merged pull request is not considered. Only open pull requests can be a sibling owner, because only they represent work still in flight in the same batch.
- No link the platform derives from a closing keyword makes a pull request an owner, of its own issues or anyone else's.

---

## Operational Visibility

- **Where the warning appears**: on the pull request itself, as a single report that is updated in place rather than re-posted, so a pull request that is corrected and re-checked does not accumulate a stack of contradictory warnings.
- **Where an indeterminate run appears**: as a neutral, non-blocking check conclusion plus a log line naming what could not be read. Never as a failing check, and never as a change to mergeability. The next conclusive run replaces that check, whatever its outcome.
- **What a clean result looks like**: nothing is posted. Silence is the clean signal.
- **Label provisioning**: the `multi-issue-intentional` label is created on first use in repositories that do not have it, idempotently, so the opt-out works on a fresh template installation without a manual setup step. When creation fails, the warning is still posted and its report names the label the author needs.
- **Audit trail**: the `multi-issue-intentional` label stays on the pull request after merge, so a later release reconciliation can tell a deliberate multi-issue pull request from an accidental one.

---

## Decision-Gate Consistency Matrix

This feature is a workflow decision gate: its outcome depends on several inputs, and its filtering has to agree with the canonical parser that decides what actually gets closed. The matrix below is the canonical statement of that behavior; every row is reflected in an acceptance criterion.

### Gate inputs

| Input | Where it comes from | Why it matters |
| --- | --- | --- |
| Declared closing keywords in the pull request description | Reported from the description only — never from the title or the commit messages. Filtered as the closer for this pull request filters: title and description together when it merges to a non-default branch, the description alone when it merges to the default branch | The set of issues the description claims to close |
| Sibling ownership of each named issue | The branch names of the other open **implementation** pull requests (`feature/`, `fix/`, `refactor/`, `hotfix/`, `backport/hotfix/`), in either the bare-number or the team-prefixed form | Establishes whether a different pull request identifiably carries that issue |
| `multi-issue-intentional` label | The pull request's labels | Author's recorded statement that multi-issue scope is deliberate |
| The pull request's base branch | Whether it is the repository's default branch | Selects which closer will act, and therefore which filtering the validation must match |
| Existing validation report | The pull request's own prior report, if any | Decides whether to update or clear rather than post again |
| Sibling lifecycle events | Another **implementation** pull request whose branch names the same issue opening, closing, or merging | Ownership evidence is mutable and lives outside this pull request, so it is an input in its own right |

The gate re-evaluates on a change to any of its inputs: the pull request's description, its title where the title contributes filtering state, its labels, its base branch, or the set of open implementation pull requests whose branches name the issues it declares. A label change is a trigger in its own right — applying the opt-out clears an existing warning, and removing it restores one, without waiting for a push. A sibling opening, closing, or merging is likewise a trigger for every pull request whose result could turn on it, and readiness re-evaluates as a backstop.

### Allowed outcomes and required next actions

| Inputs | Outcome | What the validation does | Author's next action |
| --- | --- | --- | --- |
| The pull request originates from a fork | **Not validated** | Nothing posted; no label created | None available here — see Out of Scope |
| No declared closing keywords | Silent | Nothing posted; any prior report cleared and any prior indeterminate check superseded | None |
| All named issues carried by this pull request | Silent | Nothing posted; any prior report cleared and any prior indeterminate check superseded | None |
| At least one named issue identifiably carried by a sibling, label absent | **Warning** | Posts or updates one report naming each out-of-scope issue and its sibling; supersedes any prior indeterminate check | Drop the keyword, or apply `multi-issue-intentional` |
| The same, but the `multi-issue-intentional` label is missing and could not be created | **Warning** | Same report, plus a line saying the opt-out label could not be created and naming it | Drop the keyword, or create the label by hand and apply it |
| At least one named issue identifiably carried by a sibling, label present | Silent | Clears any prior report and supersedes any prior indeterminate check | None |
| Ownership cannot be established for a named issue — no signal on any open pull request | Silent **for that issue** | That issue is not reported; other issues are judged on their own | None |
| Ownership is contested — the same rank points at two or more open pull requests | Silent **for that issue** | Not reported; guessing an owner is the mistake this feature exists to catch | None |
| **Any** gate input cannot be read — description or its filtering, open pull requests, opt-out label, base branch, or the existing report | **Indeterminate** | Any existing report is left exactly as it is; a neutral, non-blocking check conclusion and a log line record what could not be read | Optionally re-run once the transient condition clears; nothing is blocked meanwhile |
| An input moved while this run was working | **Superseded** | This run discards its result and writes nothing; the newer run's report stands | None — the newer run already covers it |
| A run that started later has already published for this pull request | **Superseded** | This run discards its result and writes nothing, even though its own inputs never moved | None — the later run already covers it |

No input combination blocks a merge, changes mergeability, or edits an issue, milestone or release, and none applies or removes a label on a pull request. The one repository-level write anywhere in this gate is creating the `multi-issue-intentional` label when it is missing.

### Mirror surfaces

| Surface | Relationship | Consistency requirement |
| --- | --- | --- |
| Post-merge cleanup's closing-keyword reading | Decides what gets closed for pull requests merging to a non-default branch; reads the title, description, and commit messages, concatenating title and description before filtering | **Canonical for those pull requests.** The validation must exclude exactly what this parser excludes, including the effect of fence state opened in the title. It differs in what it *reports*: the description only. |
| The platform's own closing-keyword handling | Decides what gets closed for pull requests merging to the default branch, natively, from the description | **Canonical for those pull requests.** The description is filtered on its own; title fence state does not apply, because the platform never read the title as part of that text. |
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
| `Closes #97` where a sibling is on `fix/lh-97-some-slug` | Warning | A team-prefixed branch names issue 97 just as a bare-number branch would |
| A title opening an unclosed fence, `Closes #1630` in the description, merging to a non-default branch | Silent | The cleanup that will close it reads title and description together, so the fence suppresses the reference |
| The same pull request merging to the default branch | Warning | The platform closes from the description alone and never saw the title, so the reference is live |

### Issue-objective traceability

| #1644 objective | Disposition |
| --- | --- |
| PR validation, warn or block | Covered as **warn**, reporting from the description for every implementation branch type including hotfixes, with filtering selected by the closer the base branch implies; ACs 1-4, 10, 17, 26-42. Blocking, and reporting keywords found only outside the description, are Out of Scope |
| Reviewer-loop or prepare-commit blocking finding | Out of Scope, item 2 |
| Release-cleanup report for merged-but-omitted items | Out of Scope, item 3 |
| False positives minimized | Business Rules, including the implementation-only, single-signal ownership rule and the exclusion of platform-derived links; ACs 5-7, 9, 11-12, 19, 20, 22-25 |
| Documented opt-out for intentional multi-issue pull requests | Use Case 3; ACs 13-17, including label provisioning on a fresh installation and a failed provisioning that still warns |
| Tests for parser and validator edge cases | ACs 5-12 and 19-42 — ACs 5-9 and 11 cover parity with what each closer excludes, including the divergent handling of title fence state; ACs 18-24 the ownership rule with its contested, no-signal, team-prefixed, platform-link, documentation-stage and closed-sibling cases; ACs 25-29 the sibling-lifecycle, title, retarget and readiness triggers; ACs 31-38 the indeterminate outcome across every gate input, how it stays non-blocking and how a conclusive re-run supersedes it; ACs 39-41 the superseded-run freshness and ordering rules; AC 12 the fork-origin exclusion and AC 42 idempotence |

---

## Acceptance Criteria

- [ ] A pull request whose description declares a closing keyword for an issue that a different open pull request identifiably carries produces a warning naming that issue number, and the pull request remains mergeable.
- [ ] The warning names, for each reported issue, the pull request that appears to carry it.
- [ ] A pull request whose declared closing keywords all name work it carries produces no warning and no comment.
- [ ] A pull request that declares no closing keywords produces no warning and no comment.
- [ ] A closing keyword that appears only inside a fenced code sample or a quoted line in the pull request description is not reported.
- [ ] A closing keyword in the description is not reported when it appears inside any construct the canonical parser excludes: a backtick fence, a tilde fence, an inline code span, a code span spanning several lines, a blockquote, or a fence left unclosed. A keyword outside all of these is treated as a live reference and proceeds to scope evaluation; it is reported only when a sibling identifiably carries the issue and the `multi-issue-intentional` label is absent.
- [ ] For a pull request merging to a non-default branch, a closing keyword in the description is not reported when an unclosed fence opened in the title suppresses it, matching what the repository's cleanup excludes.
- [ ] For a hotfix pull request merging to the default branch, a closing keyword in the description **is** reported despite an unclosed fence opened in the title, because the platform closes from the description alone.
- [ ] A closing keyword that appears only in the pull request title is not reported, even when no fence is involved.
- [ ] A hotfix pull request targeting the default branch is validated rather than exempted, and warns when its description claims a sibling's issue.
- [ ] A word that merely contains a closing keyword as a substring — for example "disclose" or "hotfix" — is not reported.
- [ ] A fork-originated pull request is not validated: no report is posted on it and no label is created, whatever its description declares.
- [ ] In a repository that does not yet have the `multi-issue-intentional` label, an author can still apply it — the validation creates it on first use, and creating it a second time concurrently does not fail.
- [ ] When the `multi-issue-intentional` label is missing and cannot be created, a warranted warning is still posted, and its report says the opt-out label could not be created and names it.
- [ ] A pull request carrying the `multi-issue-intentional` label produces no warning, even when its closing keywords name issues that another pull request carries.
- [ ] Applying the `multi-issue-intentional` label to an already-warned pull request clears the existing warning, without any push to the pull request.
- [ ] Removing the `multi-issue-intentional` label makes the warning reappear, without any push to the pull request.
- [ ] Editing a warned pull request to drop the out-of-scope closing keyword makes the warning clear on the next run, without leaving a stale warning behind.
- [ ] When no open pull request carries an issue named by a closing keyword, no warning is produced for it.
- [ ] When two open pull requests both name the same issue in their branch, ownership is contested and no warning is produced for that issue.
- [ ] A sibling whose branch names the issue in team-prefixed form is recognized as the owner, and produces the same warning as a sibling whose branch names it in bare-number form.
- [ ] A pull request whose only connection to an issue is the platform link derived from its own closing keyword is **not** treated as that issue's owner, and still produces a warning when a sibling's branch names the issue.
- [ ] A pull request whose branch does not name an issue it declares is not treated as that issue's owner, whatever the issue's tracker item links.
- [ ] An open `spec/` or `implementation-plan/` pull request naming the issue is never treated as its owner, and does not make ownership contested.
- [ ] A closed or merged pull request is never treated as the sibling owner.
- [ ] A pull request that was silent because no sibling carried the issue warns once a sibling pull request naming that issue opens, without any change to the pull request being warned.
- [ ] A pull request that was warning stops warning once the sibling that carried the issue closes or merges, without any change to the pull request being warned.
- [ ] For a pull request merging to a non-default branch, adding or removing an unclosed fence in the title re-evaluates it, so a warning appears or disappears with the description untouched.
- [ ] Retargeting a pull request between the default branch and a non-default branch re-evaluates it, so a warning that only the old base suppressed does not survive the change and a silence that only the new base justifies is not delayed.
- [ ] A pull request reaching readiness for human review has its result re-evaluated, so a silence that went stale while it waited is corrected before a human reviews it.
- [ ] When the description cannot be fetched or filtered, an existing warning on that pull request is left in place rather than cleared, and the run does not report a clean result.
- [ ] When the open pull requests cannot be listed, an existing warning is left in place and the run does not report a clean result.
- [ ] When the opt-out label cannot be read, the run is indeterminate rather than warning — an unreadable label is never treated as an absent one.
- [ ] When the base branch cannot be read, the run is indeterminate rather than guessing which filtering to apply.
- [ ] When the existing report cannot be read, the run is indeterminate rather than posting a second report.
- [ ] An indeterminate run leaves a neutral, non-blocking check conclusion and a log line naming what could not be read; it never leaves a failing check.
- [ ] A pull request whose validation is indeterminate remains exactly as mergeable as it was before the run.
- [ ] After an indeterminate run, a conclusive re-run on the same commit replaces the neutral "did not conclude" check, including when the conclusive result is silent and posts no report.
- [ ] When two runs read identical inputs and the later-started one finishes first with a conclusive result, an earlier-started indeterminate run finishing afterwards does not replace that conclusive check with "did not conclude".
- [ ] When two runs overlap and the later one clears a warning, an earlier run finishing afterwards does not restore it.
- [ ] When two runs overlap and the later one raises a warning, an earlier run finishing afterwards does not clear it.
- [ ] Running the validation twice on an unchanged pull request leaves a single report, not two.

---

## Out of Scope (MVP)

- **Blocking mode.** The issue offers "warn or block"; this iteration warns only. Nothing here prevents a later decision to escalate.
- **A blocking or important finding in the automated reviewer loop.** Option 2 of the issue.
- **A release-cleanup report for merged issues absent from an assembled changelog section.** Option 3 of the issue, which the issue itself marks optional and frames as a complement to the existing ancestry gate.
- **Per-issue opt-out.** The opt-out is the `multi-issue-intentional` label, which applies to the whole pull request.
- **Any opt-out mechanism other than the label** — a description marker, a checkbox, or a magic comment.
- **Retroactive scanning of already-merged pull requests.** This feature looks at open pull requests going forward; it does not reconcile history.
- **Reporting closing keywords found outside the description.** The repository's cleanup also honours the title and the commit messages, so a cross-PR keyword placed only in one of those is not reported here. This follows the agreed scope — pull request *description* validation — and is a known residual gap, not an oversight. Where the title affects filtering, it is still read for that purpose, so the two never disagree about what counts as a live reference.
- **Changing how closing keywords are parsed anywhere else.** The existing post-merge cleanup and graduation closeout keep their current behavior; this feature reads, it does not redefine.
- **Ownership established by tracker linkage.** Branch naming is the only ownership signal. A pull request whose branch does not name an issue is never treated as its owner, so work whose branch predates the naming convention or was renamed produces silence rather than a warning.
- **Reconciling the two existing parsers with each other.** They disagree today about which non-live references to exclude. This feature follows the canonical one and leaves the divergence exactly as it found it; unifying them is separate work.
- **Any automatic correction.** The validation never edits a pull request description, reopens an issue, or restores a milestone.
- **Fork-originated pull requests.** This repository forbids automated writes on them, so they are not validated. A fork pull request can still claim a sibling's issue without a warning; that residual risk is accepted here rather than worked around.
