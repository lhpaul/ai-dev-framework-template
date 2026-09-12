# Reviewer Preflight — Spec

---

## Overview

Nothing checks, before work is handed out, that the reviewer platforms this repository says it uses can actually review this repository. Three configuration surfaces have to agree for a review to happen at all, and each one is validated only against itself: the shared workflow reviewer configuration that names which platforms review at which stage, the machine-local override that replaces that list for one machine — narrowing it, adding to it, or both — and the reviewer platform's own configuration, which decides whether the platform will review anything at all. When they disagree, nothing says so. The run proceeds, the platform declines, and the decline looks close enough to a review that the run can report the work as reviewed.

That is not hypothetical. On the 2026-08-20/21 run, the reviewer platform's own configuration had automatic review turned off. The platform posted a "Review skipped" banner on every pull request, the reviewer loop counted the banner as review activity, and the run reported clean. An entire unattended night would have produced pull requests reported as reviewed that were never reviewed. The banner-counting half of that failure has since been fixed, so the loop no longer mistakes a decline for a review — but nothing still tells an operator, before the run starts, that every pull request it is about to open will be declined. The cost of finding out afterwards is the whole run.

This feature adds a **reviewer preflight**: a check that runs before work is dispatched, cross-checks the three surfaces against each other rather than each alone, and fails loudly and specifically when they disagree — naming the platform, the surface that disagrees, and the setting inside it that an operator would change. On a configuration where the surfaces agree, it passes and leaves nothing behind. It also makes one undocumented behaviour explicit: the reviewer platform configuration in force for a pull request is the copy on that pull request's own branch, which is why a configuration fix takes effect on the very pull request carrying it, and why a branch can quietly diverge from the review policy the repository believes it has.

---

## Use Cases

### Use Case 1: A run starts and the reviewer configuration is coherent

**Actor**: The orchestrating agent starting a batch or a single item, on behalf of the workflow operator who launched it.
**Preconditions**: The run has resolved base branches and a resolved reviewer configuration. Every reviewer platform named for this run's stages can review pull requests of the kind this run will open, against every base this run will target.

**Steps**:

1. Before the first item is dispatched, the run performs the reviewer preflight.
2. The preflight resolves the reviewer list for every lifecycle stage the run will exercise, applying the machine-local override where one is in effect.
3. For each platform in the resolved list, it reads whatever the platform's own configuration says about whether it will review, and compares that against the stage the platform is listed for and every base branch the run will target.
4. It finds no disagreement and records the outcome Passed.
5. The run dispatches work exactly as it does today.

**Postconditions**: The run proceeded. The preflight created no pull request, posted no comment, applied no label, changed no branch, and modified no tracked file. A checkout that was clean before the preflight is clean after it.

**Information shown**:

- The preflight outcome, Passed, in the run's own output before the first dispatch.
- Every platform named by the shared reviewer list or the resolved reviewer list, with its annotation: the cross-check verdict for each platform in the resolved list — including one the override added that the shared list never named — and Excluded by override for each platform the machine-local override removed, so the operator can see the review coverage the run is actually about to get.

**Actions available**:

- Nothing is required of the operator. A Passed preflight is not a confirmation the run stops to collect.

**Considerations**:

- The preflight reads the surfaces as they stand on the run's base branches. It cannot see a divergence that a not-yet-created branch will introduce, and it does not claim to — see Use Case 3.
- A platform being able to review says nothing about what it will find. A platform that passes the preflight and then fails, errors, exhausts its quota, or times out is a review failure and is reported as one, never as a preflight problem.
- Can review is a configuration-coherence verdict: it means the three configuration surfaces agree, not that the platform's installation or service availability was itself confirmed live. A platform whose GitHub App has been removed, or whose service has otherwise become unavailable, while every configuration surface still reads as agreeing, is Can review by this preflight's cross-check and then silently declines every pull request — the same limitation Step 7a's own reachability classification already documents and accepts for the same platforms (its activity-proxy check can itself be a false Reachable after an App is removed). This is not a gap the preflight closes; it surfaces the same way an in-review failure does, as a review failure when it happens, not as a preflight problem. See Out of Scope item 11 for the deferral rationale and the human confirmation it requests.

---

### Use Case 2: A surface disagrees, and the run stops before dispatching anything

**Actor**: The orchestrating agent, and the workflow operator who reads the result.
**Preconditions**: The run is about to dispatch work. At least one reviewer platform in the resolved list cannot review the pull requests this run will open — because the platform's own configuration turns automatic review off, or excludes the draft stage the platform is listed for, or covers a set of base branches that does not include every base this run expects that platform to review against.

**Steps**:

1. The run performs the reviewer preflight before dispatching anything.
2. The preflight compares each platform's own configuration against the stage it is listed for and every base this run expects that platform to review against.
3. It finds the disagreement, classifies that platform Cannot review, and records which of the three surfaces disagrees and which setting inside it produced the disagreement.
4. It records the run outcome Blocked and reports it.
5. Nothing is dispatched.

**Postconditions**: No item was dispatched, no branch was created, no pull request was opened, and no tracker status changed on account of this run. The repository is in the state it was in before the run started. The operator has a report that names the platform, the surface, the setting, and at least one action that would change the outcome.

**Information shown**:

- The run outcome, Blocked, stated before any item-level output, so it cannot be mistaken for a per-item failure.
- Each platform that cannot review, by name.
- For each, which of the three surfaces disagrees — the shared workflow reviewer configuration, the machine-local override, or the platform's own configuration — identified by the file an operator would open, and the setting inside it identified by the name an operator would edit.
- What the surfaces say that is incompatible, stated as the contradiction rather than as two isolated facts: which stage the platform is listed for against which stages it will review, or which bases this run expects that platform to review against, against which bases it covers.
- At least one action that would resolve the disagreement.

**Actions available**:

- Change the platform's own configuration so it covers this run's stage and every base it targets.
- Change the shared workflow reviewer configuration so the platform is listed for a stage it will actually review.
- Narrow the reviewer list for this machine through the machine-local override, accepting the reduced coverage deliberately rather than discovering it afterwards.
- Re-run after any of the above. The preflight is determined fresh each run and picks the change up with no further action.

**Considerations**:

- The four disagreement cases have different remedies and are never collapsed into one message. "Automatic review is off" is a different repair from "this base branch is not covered", and an operator told the wrong one will edit the wrong thing.
- A platform that the machine-local override removed is reported as excluded by the override, not as unable to review. A deliberate narrowing is not a failure, and reporting it as one would train operators to ignore the report.
- The report never blames a platform for a disagreement that belongs to another surface. If the shared configuration lists a platform at a stage the platform's own configuration excludes, the report names both sides of the contradiction and lets the operator choose which one is wrong.
- A report that is technically true and points at the wrong thing costs the operator as much as no report. This is the standard the preflight's messages are held to, and it is why every message names the file, the setting, and the contradiction rather than a symptom.

---

### Use Case 3: An operator understands which copy of the reviewer platform configuration is in force

**Actor**: The workflow operator, and any agent reasoning about why a pull request was or was not reviewed.
**Preconditions**: The operator is reading the reviewer platform's integration documentation, or is looking at a pull request whose review behaviour does not match what the integration branch's configuration says it should be.

**Steps**:

1. The operator reads the documented behaviour: the reviewer platform configuration in force for a pull request is the copy on that pull request's own branch, not the copy on the branch the pull request targets.
2. The operator reads the two consequences the documentation states: a fix to that configuration takes effect on the very pull request that carries it, and a branch can carry a configuration that differs from the repository's intended review policy without anything else noticing.
3. The operator applies that understanding — either to repair a blocked review on the pull request in front of them, or to explain a pull request that was reviewed differently from its siblings.

**Postconditions**: The operator can predict which configuration a given pull request's review will use, and can repair a broken review without waiting for a merge to the integration branch.

**Information shown**:

- The documented resolution rule, in the reviewer platform's integration documentation.
- The two consequences, stated as consequences rather than left to be inferred.
- The observation that established it, so the statement is traceable to evidence rather than to assumption.

**Actions available**:

- Fix the platform's own configuration on the branch in front of them and see the fix apply to that same pull request.
- Recognise a branch-local divergence for what it is instead of re-investigating the repository-level configuration.

**Considerations**:

- This rule is why the preflight distinguishes what it checked from what it could not check. Before a branch exists, only the base branches' copies can be read.
- The same rule means a preflight performed against an existing pull request reads that pull request's own branch, and therefore answers a stricter question than a preflight performed before any branch exists.

---

### Use Case 4: The preflight cannot determine whether a platform will review

**Actor**: The orchestrating agent, and the workflow operator who reads the result.
**Preconditions**: The run is about to dispatch work. At least one platform in the resolved list exposes no readable configuration the preflight can cross-check, or its configuration could not be read within the preflight's bound (the bound is stated as a product property in Business Rules; its concrete value is deferred to the implementation plan).

**Steps**:

1. The preflight attempts the cross-check for that platform.
2. It cannot reach a definite answer, and classifies that platform Undetermined with the reason it could not.
3. It completes the remaining platforms and reports the run outcome, distinguishing the undetermined platforms from those that passed.
4. The run proceeds if nothing else blocked it.

**Postconditions**: The run proceeded, and the run's report says plainly which platforms were not verified. No undetermined platform was reported as having passed.

**Information shown**:

- Each undetermined platform by name, with the reason: no configuration the preflight can read, or the reading did not complete.
- An explicit statement that these platforms were not verified, kept separate from the platforms that were.

**Actions available**:

- Accept the unverified coverage and continue — the default, and the reason Undetermined does not block.
- Remove the platform from the resolved list for this machine if unverifiable coverage is not wanted.

**Considerations**:

- Undetermined is not Passed and is never folded into it. Reporting an unverifiable platform as verified would recreate, in the preflight itself, the exact false assurance this feature exists to remove.
- Undetermined does not block, because a platform the preflight cannot inspect is not evidence of a misconfiguration — only of a check that does not apply. Blocking on it would make the preflight unusable for platforms that keep no configuration in the repository.
- The preflight always reaches an outcome. A check that has not reached a definite answer within the preflight's bound yields Undetermined rather than leaving the run hanging in front of a dispatch that never happens. The bound exists so the preflight can never itself stall a run; what that bound is numerically, and how it is measured, is deferred to the implementation plan — see the bound rule in Business Rules and item 10 in Out of Scope.

---

## Business Rules

Two lists are referred to throughout, and they are not the same list:

- The **shared reviewer list** is every platform the shared workflow reviewer configuration names for the lifecycle stages this run will exercise, before any machine-local override is applied. Where a run targets more than one base branch, this list is read per targeted base — each base's own copy of the shared workflow reviewer configuration, exactly as each platform's own configuration already is — and the Decision-Gate Consistency Matrix states the canonical aggregation rule.
- The **resolved reviewer list** is the platforms this machine will actually use. When a machine-local override is in effect for a lifecycle stage's list, it replaces the shared list for that stage outright rather than narrowing it: the resolved list is exactly the override's list, which may remove platforms the shared list named, add platforms the shared list never named, or both. When no override is in effect for a stage, the resolved list equals the shared list for that stage. The override itself is resolved once from the machine running the preflight and applied to each targeted base's own shared list in turn; it is never resolved per base.

Cross-checking, per-platform verdicts about ability to review, and the run outcome are determined over the resolved list alone. Reporting enumerates the union of the shared list and the resolved list: every platform named by either appears exactly once, annotated with its cross-check verdict — Can review, Cannot review, or Undetermined — when it is in the resolved list (including a platform the override added that the shared list never named), or as Excluded by override when the shared list named it but the override's replacement list does not. A platform named by neither list is not reported, because this run never expected it to review and the override never added it.

- The preflight runs before any item is dispatched in a run, and before any branch, pull request, tracker status, comment, or label is created or changed by that run. A preflight that runs after dispatch has no value, because the cost it exists to prevent has already been incurred.
- The preflight cross-checks the surfaces against each other. A surface that is internally valid but contradicts another surface is a failure, and it is the only kind of failure this feature adds — each surface already validates itself.
- Surface precedence is unchanged: the machine-local override takes precedence over the shared workflow reviewer configuration for the machine it is on. The preflight cross-checks the resolved result, not the shared configuration alone, so a run on a machine with an override is checked against the reviewers that machine will actually use.
- Every platform named by the shared reviewer list or the resolved reviewer list appears in the report exactly once — with its cross-check verdict if it is in the resolved list (including a platform the override added that the shared list never named), or as Excluded by override if the shared list named it and the override's replacement list does not. No platform is silently omitted, because a silently omitted platform is indistinguishable from one that passed.
- A platform removed by the machine-local override is reported as Excluded by override, is not cross-checked, and never affects the run outcome. A deliberate exclusion is not a disagreement.
- A Blocked outcome stops the run before dispatch. It is not a warning the run proceeds past.
- An Undetermined verdict does not block, and is never reported as a pass: it is surfaced by name instead. The Decision-Gate Consistency Matrix states this guarantee canonically, and every other statement in this spec about unverified coverage defers to it.
- A Passed preflight has no side effects: it creates no pull request, posts no comment, applies no label, creates or modifies no branch, and modifies no tracked file. The same holds for a preflight that produces Blocked, Passed some unverified, or Prerequisite not met — a preflight that reports a problem must not also create one.
- The preflight itself performs no write of any kind — no repository state, no external state, no record — and its only output is the outcome and report it returns to the process that called it. Where the enclosing run already keeps an audit record of itself using a mechanism that predates this feature, that record may fold the preflight's outcome in as one more fact in a write the run was already going to make; that fold is the enclosing run's own pre-existing state change, not one the preflight performs, requires, or causes to exist where the run would otherwise keep none. The preflight's side-effect-free guarantee — no pull request, no comment, no label, no branch, no tracked file created or modified by the preflight itself — is about the preflight's own actions and holds regardless of whether the enclosing run separately records something for reasons of its own.
- The preflight is bounded: every check it performs either reaches a definite answer or yields Undetermined within a bound, so the preflight can never hold a run open in front of a dispatch that never happens. The product property the bound must satisfy is that an unreachable or slow surface degrades to Undetermined rather than to waiting, and that the preflight's cost stays negligible against the work it guards. The bound's concrete value, and how it is measured, are deliberately not fixed in this spec and are an implementation-plan decision.
- Every failure report identifies the surface by the file an operator would open and the setting by the name an operator would edit, and states the contradiction rather than one side of it. A report an operator cannot act on directly does not satisfy this rule.
- The preflight's verdicts are determined fresh on each run. No verdict from an earlier run is an input to a later one: a record of a past run's outcome is history, not state the preflight reads or updates. Repairing the surface behind one of a platform's disagreement reasons, or one of its per-base results, removes that specific reason or result on the second run with no further action, and breaking it between two runs reintroduces it the same way; that platform's own overall verdict is then whichever the multi-reason and per-base combination rules produce from whatever reasons and per-base results remain, which is Can review only when none remain.
- The stage-excluded check is evaluated against the pull request state a platform will actually see at the moment it is dispatched, not the state at the moment the preflight runs. Where an existing, already-documented workflow behavior changes that state before a listed platform is dispatched — for example, converting a draft pull request to non-draft before dispatching a platform whose own configuration declines drafts, exactly as the internal review gate already does for a draft-declining runner reviewer — the preflight evaluates that platform against the state it will see after the adjustment. A platform is Cannot review with the reason Stage not covered only when no such existing adjustment resolves the mismatch before that platform's dispatch.
- A run may target more than one base branch, and base-branch coverage is evaluated for every targeted base that names a given platform in that base's own resolved list — not for one representative base, and not indiscriminately for every targeted base regardless of whether that base actually names the platform. A platform whose own configuration fails to cover any one of the bases that names it is Cannot review, which blocks the whole run. The Decision-Gate Consistency Matrix states this canonically.
- The preflight reports what it checked against. A preflight performed before any branch exists is checked against the base branches the run targets, and names them; it does not claim to have verified branches that do not yet exist.
- The reviewer platform configuration in force for a pull request is the copy on that pull request's own branch. A preflight performed against an existing pull request reads that pull request's branch. This rule is documented in the platform's integration documentation, not only implied by the preflight's behaviour.
- A preflight performed against an existing pull request has a single, well-defined base-branch input: that pull request's own target base, read from the pull request itself, not from any multi-base run context — a run that dispatched the item may no longer exist by the time an existing pull request is checked. Only the shared workflow reviewer configuration and each platform's own configuration switch source, to the copy on that pull request's own branch instead of the copy on a targeted base branch. The machine-local override does not switch source: it is resolved from the machine running the preflight exactly as it is for a pre-dispatch preflight, never from the pull request's branch, and it keeps the same precedence over the shared list read from that branch that it has everywhere else in this spec.
- The preflight decides whether a platform can review. It does not decide what the platform says, does not run a review, and does not change any reviewer gate's behaviour after it passes. Deciding whether a platform can review means cross-checking configuration, not confirming the platform's installation or service is live; the same limitation already applies to Step 7a's own reachability classification, whose activity-proxy check can itself be a false Reachable after a platform's GitHub App is removed.
- The preflight reports a disagreement; it never repairs one. Editing a surface on the operator's behalf would change the repository's review policy without the operator asking.

---

## Statuses / Enum Values

These are per-run classifications. They describe one preflight and do not persist: the next run determines them again from scratch, so the only transition is a re-classification on a later run.

Per-platform verdicts:

| Code value          | Display label        | Description                                                                                                                                  |
| ------------------- | -------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| `operable`          | Can review           | The three configuration surfaces agree for this platform: at the stage it is listed for, against every base this run expects it to review, nothing in configuration says it will decline. This is a configuration-coherence verdict, not a live probe of the platform's actual installation or service availability — a state that lives outside configuration, which a configuration cross-check cannot see. |
| `not-operable`      | Cannot review        | The surfaces disagree for this platform. Always accompanied by every applicable disagreement reason and the surface that disagrees for each.  |
| `undetermined`      | Undetermined         | The preflight could not reach a definite answer for this platform. Never reported as Can review.                                             |
| `override-excluded` | Excluded by override | The platform is in the shared reviewer list but not in the resolved list: the machine-local override removed it. It is reported, never cross-checked, and never affects the run outcome. Not a failure, and never reported as Cannot review. |

Disagreement reasons, reported with every Cannot review verdict:

| Code value              | Display label              | Description                                                                                                                        |
| ----------------------- | -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| `review-disabled`       | Automatic review turned off | The platform's own configuration turns automatic review off, so it will decline every pull request in this repository.             |
| `stage-excluded`        | Stage not covered          | The platform is listed for a lifecycle stage its own configuration excludes — most commonly listed as a draft reviewer while its own configuration declines drafts — and no existing workflow behavior changes the pull request's state before that platform is dispatched to resolve the mismatch. |
| `base-branch-unmatched` | Base branch not covered    | At least one base branch this run expects that platform to review against is not among the bases the platform's own configuration covers. Reported with the bases it was expected to cover and the bases covered. |
| `value-not-supported`   | Not a supported reviewer   | The configured value is not a reviewer platform this workflow supports, so no cross-check is possible and no review would happen.   |

Undetermined reasons, reported with every Undetermined verdict:

| Code value            | Display label                  | Description                                                                                              |
| --------------------- | ------------------------------ | ---------------------------------------------------------------------------------------------------------- |
| `no-readable-surface` | No configuration to cross-check | The platform exposes no configuration the preflight can read, so the cross-check does not apply to it.   |
| `check-inconclusive`  | Check did not complete          | The reading did not reach a definite yes or no within the preflight's bound — whose concrete value is deferred to the implementation plan — or ended without an answer. |

Run outcomes:

| Code value             | Display label          | Description                                                                                                     |
| ---------------------- | ---------------------- | ----------------------------------------------------------------------------------------------------------------- |
| `passed`               | Passed                 | Every platform in the resolved list is Can review; none is Cannot review and none is Undetermined. An empty resolved list qualifies. The run dispatches. |
| `passed-unverified`    | Passed, some unverified | No platform in the resolved list is Cannot review, and at least one is Undetermined. The run dispatches, and the report names the unverified platforms. |
| `blocked`              | Blocked                | At least one platform in the resolved list is Cannot review. Nothing is dispatched, and the run stops for the operator. |
| `prerequisite-failed`  | Prerequisite not met   | The run's set of targeted base branches, or the lifecycle stage or pull-request state it is dispatching, was empty, unresolved, or malformed when the preflight ran — a failure of an input the run must resolve before the preflight runs, not a per-platform verdict. Decided before any per-platform verdict is computed; the run does not dispatch. |

Platforms Excluded by override are reported but are not in the resolved list, so they never contribute to the run outcome.

---

## Operational Visibility

The preflight's only output is its report. There is no user interface, and no one is notified: the audience is the operator reading the run and the agent deciding whether to dispatch.

- **Run output, before dispatch**: the run outcome, and every platform named by the shared reviewer list or the resolved reviewer list annotated exactly once — Can review, Cannot review, or Undetermined for the platforms in the resolved list (including one the override added), Excluded by override for the platforms the override removed — emitted before any item-level output, so the outcome cannot be mistaken for a per-item result.
- **Failure report**: on Blocked, each platform that cannot review, its disagreement reason, the surface that disagrees identified by the file an operator would open, the setting identified by the name an operator would edit, the contradiction stated in full, and at least one action that would change the outcome.
- **Unverified report**: on Passed, some unverified, each undetermined platform with its reason, kept visibly separate from the platforms that passed.
- **Override notice**: when a machine-local override is in effect, the report records that it is, and which platforms it removed and which it added, so a coverage change — reduced, different, or both — is visible at the moment it is chosen rather than only when a review is missing.
- **Scope statement**: every report states what it was checked against — every base branch this run targets, or a specific pull request's branch — so a reader never has to guess whether a branch-local divergence was covered.
- **Prerequisite failure report**: on Prerequisite not met, the report says plainly which required input was empty, unresolved, or malformed — the targeted base-branch set, or the dispatching stage — and that no platform was cross-checked on this run — distinct from Passed, whose report states that every platform in the resolved list was actually checked.
- **Audit record**: where the enclosing run already keeps an audit record of itself, the preflight's outcome is folded into that record as one more fact, so a run reported as complete can be checked afterwards for whether its reviewers were verified before it started. The preflight creates no record of its own and requires no run to create one where it previously kept none; folding the outcome in is the enclosing run's own pre-existing state change, made with a mechanism that predates this feature. The no-side-effects rule AC-2 tests is about the preflight's own actions — no pull request, no comment, no label, no branch, no tracked file created or modified by the preflight itself — not about whether some other, already-existing part of the run writes state for reasons of its own.

---

## Decision-Gate Consistency Matrix

The preflight is a workflow decision gate: it takes several inputs, produces one of a fixed set of outcomes, and each outcome has a required next action. The matrix below is the canonical statement of that behaviour.

### Gate inputs

| Input                                                    | Where it comes from                                                        | Why it matters                                                                        |
| -------------------------------------------------------- | ---------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| The reviewer list for each lifecycle stage               | The shared workflow reviewer configuration, read from the branch in force — per targeted base, when a run targets more than one, exactly as each platform's own configuration already is | Names which platforms are expected to review, and at which stage, on each targeted base's own copy |
| The machine-local override, when one is in effect        | The machine-local reviewer override, resolved once from the machine running the preflight, never from any targeted base's branch | Replaces each targeted base's own shared list for that stage outright — the resolved list for that base may be a subset, a superset with platforms that base's shared list never named, or an entirely different list |
| Each platform's own review configuration                 | The platform's own configuration, read from the branch in force — per targeted base, when a run targets more than one | Decides whether the platform will review at all, at which stage, and against which bases |
| The set of base branches this run targets                | The resolved execution base of every item the run will dispatch              | A base the platform does not cover means every pull request the run opens against that base is declined |
| The pull request state the platform will actually see at dispatch | The stage the run is dispatching, adjusted by any existing workflow behavior that changes that state before a listed platform is dispatched | A draft-stage listing against a platform that declines drafts is a disagreement only when no such adjustment resolves it before that platform is dispatched |
| Whether each configured value is a supported platform    | The canonical list of supported reviewer platforms                          | An unsupported value must be reported, not dropped                                    |

Where a platform's own configuration cannot be read, that platform is Undetermined with the reason it could not be read. Where the resolved reviewer list itself cannot be read, the existing configuration-validation behaviour applies unchanged; the preflight adds no new handling for it, because a list that cannot be read names no platforms to cross-check.

**A run may target more than one base branch.** One run can dispatch items against an epic integration branch and items against the main integration branch, so the gate's base-branch input is the set of every base the run will target, never a single representative base. A branch this run creates inherits whichever copy of every repository file exists on the base it targets, and that inherited copy — not any other base's copy — is what the actual reviewer gates will read once that branch and its pull request exist (the same branch-in-force rule already stated for each platform's own configuration). The shared workflow reviewer configuration is therefore also read per targeted base, exactly as each platform's own configuration already is: the gate resolves a separate shared list for each targeted base, applies the one, single, machine-scoped override — never resolved per base, because the override comes from the machine running the preflight, not from any branch — to each base's shared list to get that base's resolved list, and reports the union of every targeted base's shared list and the union of every targeted base's resolved list. A platform present in only one targeted base's list is still reported, never silently dropped for being absent from another base's copy.

A platform's base-branch coverage is checked only against the targeted bases whose own resolved list actually names that platform — the bases this run expects that platform to review — not against every targeted base indiscriminately. A targeted base whose own resolved list does not name a platform at all places no expectation on that platform, and the platform's absence from that one base's list is not itself a disagreement. Within the bases that do name a platform, coverage combines exactly as stated below: the platform is Can review only where its own configuration covers every one of those bases, and Cannot review with the reason Base branch not covered where it covers none of them or only some.

Reading a platform's own configuration can succeed for one of the bases that names it and fail — be unreadable, or not complete within the preflight's bound — for another; the per-base results for those bases still combine into exactly one verdict for that platform, using the same severity ordering the run outcome uses (Cannot review outranks Undetermined, which outranks Can review). If one of those bases' own configuration was read and establishes any of the three disagreement reasons against that base's copy — automatic review turned off, a listed stage its own configuration excludes, or that base itself not covered — the platform is Cannot review with that reason, even if another of those bases' own configuration could not be read at all: a proven disagreement on one base's readable copy is definite evidence, and an inconclusive reading of another base cannot undo it. Only when none of those bases' own configuration establishes any disagreement reason, and at least one of them could not be read, is the platform Undetermined. A platform is Can review only when every base that names it was read and every one of them agrees.

**Under the rule this spec sets, a coverage gap on any base in that set blocks the whole run.** Such a gap is a Cannot review verdict for that platform, and Blocked is a hard whole-run stop: nothing is dispatched, for any base, including the bases the platform does cover. The gate outcome and the required next action are therefore fully determined for a run targeting several bases. Open Question 2 asks only whether a later refinement should narrow that stop to the items targeting the uncovered base; it does not leave today's outcome undefined.

### Triggers

| Trigger                                                   | Why it fires                                                                          |
| ----------------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| A run is about to dispatch its first item                 | The gate's normal entry point, and the last moment before cost is incurred            |
| A run is retried after a Blocked outcome                  | The retry is the operator's remedy path; a repaired surface must be picked up          |
| A preflight is performed against an existing pull request | Answers the stricter, branch-specific question that the pre-dispatch check cannot      |

An empty resolved reviewer list is not a trigger failure: the gate still runs, reports that no platform is configured to review, and produces Passed, because no platform in the resolved list disagrees. That is a legitimate configuration and not a disagreement.

An empty, unresolved, or malformed set of targeted base branches is not the same case and does not produce Passed by the same reasoning. The set of base branches this run targets, and the lifecycle stage or pull-request state the run is dispatching, are both required inputs the run resolves before the preflight runs, not inputs the preflight resolves for itself; a run that reaches the preflight without a non-empty, resolved base-branch set, or without a resolved dispatching stage, has already failed that prerequisite. The preflight does not run against such an input and does not report Passed on its account — an empty base-branch set would otherwise vacuously satisfy every base-branch coverage check without reading any platform's own configuration at all, and an unresolved stage would let stage-excluded checking be silently skipped for every platform, which is exactly the false assurance this feature exists to remove. Either failure is reported as the same distinct run outcome, Prerequisite not met — never folded into any of the three per-platform verdicts, and never reported as Passed, Passed some unverified, or Blocked.

### Allowed outcomes and required next actions

| Outcome                 | When it is produced                                                | Required next action                                                                     |
| ----------------------- | -------------------------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| Prerequisite not met    | The run's set of targeted base branches, or its dispatching stage, is empty, unresolved, or malformed | Nothing is dispatched. No per-platform verdict is computed. The run resolves the failed input and re-runs |
| Passed                  | No platform in the resolved list is Cannot review, and none is Undetermined | Dispatch proceeds. No operator action, no confirmation collected                |
| Passed, some unverified | No platform in the resolved list is Cannot review, and at least one is Undetermined | Dispatch proceeds. The report names every unverified platform for the operator to read |
| Blocked                 | At least one platform in the resolved list is Cannot review        | Nothing is dispatched. The operator repairs a surface, or narrows the list, and re-runs   |

**Prerequisite not met is decided first, before any per-platform verdict.** The gate cannot compute base-branch coverage — or read any per-base copy of the shared reviewer configuration — without a resolved base-branch set to evaluate against, and it cannot compute the stage-excluded check without a resolved dispatching stage to compare a platform's listing against, so it checks both prerequisites before computing any platform's verdict. Where either fails, the gate reports Prerequisite not met and stops there; no platform is classified Can review, Cannot review, or Undetermined for that run, because none of those verdicts was actually computed — an unresolved stage is never treated as silently satisfying the stage-excluded check for every platform. Where both prerequisites are met, the gate proceeds to per-platform verdicts as stated below.

**Outcome determination is otherwise total and mutually exclusive.** Once the base-branch prerequisite is met, every platform in the resolved list carries exactly one of Can review, Cannot review, or Undetermined, and the outcome is the most severe verdict present: Blocked if any platform is Cannot review; otherwise Passed, some unverified if any platform is Undetermined; otherwise Passed. Exactly one outcome therefore applies to any configuration, including one where a platform is Cannot review and another is Undetermined — that configuration is Blocked, and the undetermined platform is still reported as Undetermined. Platforms Excluded by override are reported but are not in the resolved list and never change the outcome.

**A platform's Cannot review verdict names every disagreement reason that applies to it, not one.** The three disagreement checks — automatic review turned off, a listed stage its own configuration excludes, and an uncovered base branch — are independent of each other, and a platform can fail more than one at once: a platform can simultaneously have automatic review off, be listed for a stage its own configuration declines, and cover a set of bases that omits one this run expects it to review against. The gate runs all applicable checks for every platform in the resolved list and reports the complete set of disagreement reasons that apply on that platform's single Cannot review verdict. No check is skipped because another already produced Cannot review, and no precedence between the reasons is defined, because a report that names every applicable reason needs none — precedence would only be necessary to pick one reason to the exclusion of others, and this gate never does that.

**Unverified coverage is surfaced, never assumed clean.** This is the canonical statement of the guarantee, and every other statement in this spec about Undetermined defers to it. An Undetermined platform is never counted as Can review and never disappears into a Passed outcome. Dispatch may proceed while a platform is unverified, but only under Passed, some unverified, which requires the report to name that platform as unverified. What is forbidden is dispatching while treating an unverified platform as though it had been verified; what is required is that the operator is told, before the first item goes out, exactly which coverage was assumed rather than checked. No outcome repairs a surface.

### Mirror surfaces

| Surface                                                   | What it must say                                                                                             |
| ----------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| The batch orchestration protocol                          | That the preflight runs before the first dispatch, and that a Blocked outcome stops the batch before mutation |
| The single-item orchestration protocol                    | That the preflight runs before the run's first mutation — before any branch is created — not merely before the reviewer gates, and that the gates themselves run after a preflight that did not block, with their own behaviour otherwise unchanged |
| The reviewer platform's integration documentation         | The branch-in-force resolution rule, its two consequences, and the four disagreement cases with their remedies |
| The workflow configuration's own commentary               | Nothing that contradicts the cross-check rule or describes single-surface validation as sufficient           |

### Examples

Worked examples are part of the changed surface wherever a disagreement case is described. Each of the four disagreement cases below shows the same shape — the inputs, the contradiction the preflight finds, the report it produces, and the remedy it points to — so an operator can match a report to an example without translating between them. A fifth example follows the same nominal shape as one of the four but resolves to Can review, to show that the stage check is decided against the pull request state at actual dispatch, not against the nominal listed stage alone.

**Example: Automatic review turned off.** The shared reviewer list names `platform-x` as a draft-stage reviewer for this run. No machine-local override is in effect. `platform-x`'s own configuration turns automatic review off for this repository. Contradiction: the shared list expects `platform-x` to review this run's draft-stage pull requests; `platform-x`'s own configuration will decline every one of them. Report: Cannot review, reason Automatic review turned off, surface `platform-x`'s own configuration, naming the setting that turns review off. Remedy: turn automatic review on in `platform-x`'s own configuration, or remove `platform-x` from the shared reviewer list, and re-run.

**Example: Stage not covered.** The shared reviewer list names `platform-y` as a draft-stage reviewer. `platform-y`'s own configuration declines drafts and reviews only non-draft pull requests. Contradiction: the shared list lists `platform-y` at the draft stage; `platform-y`'s own configuration excludes drafts. Report: Cannot review, reason Stage not covered, both sides stated — listed for draft, covers non-draft only — and the setting in `platform-y`'s own configuration that excludes drafts. Remedy: change `platform-y`'s own configuration to cover drafts, or move `platform-y` to a stage its own configuration covers in the shared reviewer list, and re-run.

**Example: Base branch not covered.** This run targets two base branches — an epic integration branch and the main integration branch. `platform-z`'s own configuration covers the main integration branch but not the epic integration branch. Contradiction: the run targets both bases; `platform-z`'s own configuration covers only one of them. Report: Cannot review, reason Base branch not covered, naming both the bases targeted (both) and the bases covered (the main integration branch only), surface `platform-z`'s own configuration. Remedy: add the epic integration branch to the set `platform-z`'s own configuration covers, or narrow this machine's reviewer list through the machine-local override to exclude `platform-z` for this run, and re-run.

**Example: Not a supported reviewer.** The shared reviewer list names `platform-w` as a draft-stage reviewer, but `platform-w` is not one of the reviewer platforms this workflow supports — a typo, a retired integration, or a platform this repository has never onboarded. Contradiction: the shared list configures this workflow to use `platform-w`; the canonical list of supported reviewer platforms does not include it, so no cross-check against its own configuration is even possible. Report: Cannot review, reason Not a supported reviewer, naming the offending value exactly as configured, surface the shared workflow reviewer configuration (the file an operator would open). Remedy: correct the value to a supported platform's name, or remove it from the shared reviewer list, and re-run.

**Example: a resolved mismatch is not a disagreement.** The shared reviewer list names a platform as a draft-stage runner reviewer whose own configuration declines drafts — the same shape as the Stage not covered example above. Unlike that example, the internal review gate already converts this pull request from draft to non-draft before dispatching that platform, exactly as it already does for a draft-declining runner reviewer. The platform will therefore see a non-draft pull request at the moment it is actually dispatched, not the draft state the preflight observes when it runs before dispatch. Because the mismatch is resolved before dispatch by an adjustment the workflow already makes, the preflight does not classify this platform Cannot review with the reason Stage not covered — the same nominal listed-stage-versus-own-configuration shape produces a different verdict depending on whether an existing adjustment resolves it before dispatch. Assuming this platform's own configuration otherwise agrees — automatic review on, and every base this run expects it to review against covered — its overall verdict is Can review; either of those other checks failing would still make it Cannot review for that independent reason.

---

## Acceptance Criteria

### A disagreement is reported before dispatch, naming the surface (AC-1)

- [ ] With a platform listed in the resolved reviewer list whose own configuration turns automatic review off, the preflight produces Blocked, classifies that platform Cannot review with the reason Automatic review turned off, and names the platform's own configuration as the surface that disagrees.
- [ ] With a platform listed as a draft-stage reviewer whose own configuration excludes drafts, and no existing workflow behavior adjusts the pull request's state before that platform is dispatched, the preflight produces Blocked, classifies that platform Cannot review with the reason Stage not covered, and states both sides of the contradiction: the stage it is listed for and the stages its own configuration covers.
- [ ] With a platform listed as a draft-stage reviewer whose own configuration excludes drafts, where an existing workflow behavior converts the pull request to non-draft before that platform is dispatched (as the internal review gate's draft-declining-runner-reviewer conversion already does), the preflight does not classify that platform Cannot review with the reason Stage not covered — that disagreement is resolved before the platform ever sees the draft state it declines. The platform's overall verdict still follows the other, independent checks: it is Cannot review with Automatic review turned off or Base branch not covered if either of those disagreements independently applies to it, and Can review only when every check agrees.
- [ ] With a platform whose own configuration covers a set of base branches that does not include every base this run expects that platform to review against, the preflight produces Blocked, classifies that platform Cannot review with the reason Base branch not covered, and names both the bases it was expected to cover and the bases covered.
- [ ] Each of the four disagreement reasons is reported distinctly; none is reported in place of another, and none is reported as a generic configuration error.
- [ ] With a platform for which more than one disagreement reason applies at once — for example automatic review turned off and a covered-base-set gap on the same platform — the preflight's single Cannot review verdict for that platform names every applicable reason, not only the first one found.
- [ ] Every Cannot review report names the file an operator would open and the setting an operator would edit, and gives at least one action that would change the outcome.
- [ ] On Blocked, no item is dispatched: no branch is created, no pull request is opened, no tracker status changes, and no comment or label is applied by that run.
- [ ] The Blocked outcome is reported before any item-level output, so it is not mistakable for a single item's failure.
- [ ] With a platform removed by the machine-local override, the preflight reports it as Excluded by override and does not produce Blocked on its account.
- [ ] With the shared configuration and the machine-local override naming different reviewer lists, the preflight cross-checks the resolved list — the one this machine will use — and the report states that an override was in effect.
- [ ] With a configured value in the resolved list that is not a supported reviewer platform, the preflight classifies it Cannot review with the reason Not a supported reviewer, names the offending value, and therefore produces Blocked. It is never silently dropped.
- [ ] Every platform named by the shared reviewer list or the resolved reviewer list appears in the report exactly once: with its cross-check verdict if it is in the resolved list — including the ones that passed and any the override added that the shared list never named — or as Excluded by override if the shared list named it and the override's replacement list does not.
- [ ] With the machine-local override naming a platform absent from the shared reviewer list, the preflight adds that platform to the resolved list, cross-checks it exactly as it would any other resolved-list platform, and reports its verdict. It is never silently dropped for being absent from the shared list.
- [ ] The preflight repairs nothing: after a Blocked outcome, every surface is byte-for-byte as it was before the preflight ran.
- [ ] With the run's set of targeted base branches empty, unresolved, or malformed, the preflight produces Prerequisite not met rather than Passed, does not compute a Can review / Cannot review / Undetermined verdict for any platform, and does not dispatch. An empty base-branch set does not vacuously pass every base-branch coverage check.
- [ ] With the run's dispatching stage or pull-request state empty, unresolved, or malformed, the preflight produces Prerequisite not met rather than Passed, and does not silently skip the stage-excluded check for any platform by treating the unresolved stage as agreement.

### A correct configuration passes without side effects (AC-2)

- [ ] With all three surfaces in agreement and every platform in the resolved list verified as Can review, the preflight produces Passed and the run dispatches exactly as it does today.
- [ ] A Passed preflight creates no pull request, posts no comment, applies no label, creates or modifies no branch, changes no tracker status, and modifies no tracked file. Running it on a clean checkout leaves the checkout clean and leaves the repository's pull request list unchanged.
- [ ] A preflight that produces Blocked, Passed some unverified, or Prerequisite not met has the same absence of side effects as a Passed one.
- [ ] A Passed preflight runs no review and dispatches no reviewer.
- [ ] A Passed preflight collects no operator confirmation and does not pause the run.
- [ ] This repository's own shipped configuration deliberately keeps the platform that carries a repository configuration file out of every lifecycle stage, while that file's own automatic review is off. Because that platform is not listed for any stage this run exercises, it is in neither list, contributes no Cannot review verdict, and its absence never produces Blocked on its own account — a platform that is not listed for any stage is not a platform this run expects to review. The run's actual outcome for this configuration is whichever of Passed or Passed, some unverified the cross-check of the platforms the shared reviewer list does name produces, following the canonical outcome-determination rule; this platform's absence does not by itself require Passed over Passed, some unverified.
- [ ] The preflight reaches an outcome without operator intervention even when a platform's configuration cannot be read, rather than leaving the run waiting in front of a dispatch that never happens.
- [ ] Verdicts are determined fresh each run: on the second run, repairing the surface that made a platform Cannot review for a given reason removes that specific disagreement, and breaking it between two runs reintroduces the same disagreement, in both cases with no other change. That platform's own overall verdict on the second run is whichever the per-base combination rule (where the run targets more than one base naming that platform) and the disagreement-reason rule (where more than one reason applied) produce from the reasons and per-base results that remain — Can review only if repairing that one disagreement leaves none of the others outstanding and every base naming the platform was read and agrees, Undetermined if a base naming it remains unreadable with no other disagreement proven, or still Cannot review if another disagreement or an unreadable-yet-disagreeing base remains; repairing one disagreement is not asserted to guarantee that platform's own verdict becomes Can review by itself. The run outcome that follows is, in turn, whichever the canonical outcome rule produces from every platform's verdict in the resolved list — including the repaired platform's own resulting verdict, not only every other platform's: Blocked if the repaired platform or any other remains Cannot review; otherwise Passed, some unverified if the repaired platform or any other remains Undetermined; otherwise Passed. No earlier run's recorded outcome is consulted.
- [ ] The preflight itself persists nothing: no repository state, no external state, no record. Its outcome reaches the operator as run output. Where the enclosing run already keeps a record of itself using a pre-existing mechanism, that record may fold the outcome in as one more fact in a write the run was already making; that fold is the enclosing run's own state change, not one the preflight performs, requires, or causes to exist where the run would otherwise keep none. The absence-of-side-effects criteria above are about the preflight's own actions and hold regardless of what the enclosing run separately records.

### Unverifiable platforms are never reported as verified

- [ ] A platform that exposes no configuration the preflight can read is classified Undetermined with the reason No configuration to cross-check. Where no platform in the resolved list is Cannot review, the run outcome is then Passed, some unverified — never Passed. Where some other platform is Cannot review, the run outcome is Blocked and that platform is still reported as Undetermined; the two criteria never demand different outcomes for the same configuration.
- [ ] A platform whose configuration could not be read within the preflight's bound — whose concrete value the implementation plan sets — is classified Undetermined with the reason Check did not complete, distinct from No configuration to cross-check, provided no targeted base's own configuration otherwise establishes a disagreement reason for that platform; when one does, the platform is Cannot review with that reason instead, per the per-base combination rule. The preflight reaches its outcome rather than waiting on that platform.
- [ ] The report keeps undetermined platforms visibly separate from platforms that passed.
- [ ] An Undetermined verdict does not block dispatch on its own.

### The branch-in-force resolution behaviour is documented (AC-3)

- [ ] The reviewer platform's integration documentation states that the platform's own configuration is read from the pull request's own branch, not from the branch the pull request targets.
- [ ] It states the consequence that a configuration fix takes effect on the very pull request that carries it, so a broken review can be repaired on the branch in front of the operator without waiting for a merge.
- [ ] It states the consequence that a branch can carry a configuration that differs from the repository's intended review policy, without anything else reporting the divergence.
- [ ] It records the observation that established the behaviour, so the statement is traceable to evidence.
- [ ] The documentation states that a pre-dispatch preflight is checked against the base branches the run targets and therefore cannot see a divergence introduced by a branch that does not yet exist.
- [ ] No workflow surface contradicts the resolution rule or describes the integration-branch copy as the one in force.

### A preflight against an existing pull request asserts operability, scoped to that branch (B-5)

- [ ] When the preflight is performed against an existing pull request rather than before any branch exists, its base-branch input is that pull request's own target base — a single, well-defined value read from the pull request itself, not a multi-base run context that may no longer exist by the time an existing pull request is checked. It cross-checks each platform's own configuration as read from that pull request's own branch — not the branch it targets — against the stage and that one target base, and reaches the same Can review / Cannot review / Undetermined per-platform verdicts and the same Passed / Passed, some unverified / Blocked run outcome that a pre-dispatch preflight with a single targeted base would reach. The shared workflow reviewer configuration is read from that same pull request branch; the machine-local override is resolved from the machine running the preflight, exactly as it is for a pre-dispatch preflight, and keeps its usual precedence over that branch's shared list.
- [ ] A preflight performed against an existing pull request states, per the Scope statement rule, that it was checked against that specific pull request's branch rather than against the run's base branches, so a reader never has to guess which scope a given report covers.
- [ ] This is the preflight's asserted-operability path against a real pull request that brief objective B-5 requires; creating a scratch pull request to exercise this same path remains deferred under Out of Scope entry 1. This path cross-checks configuration only, so the live-installation limitation in Out of Scope entry 11 applies to it exactly as it does to the pre-dispatch path — it does not detect a platform whose installation was removed while its configuration still reads as agreeing.

### The preflight is reachable where it is needed, and consistent across surfaces

- [ ] A batch run performs the preflight before dispatching its first item, and a Blocked outcome stops the batch before any item is dispatched.
- [ ] A single-item run performs the preflight before its first mutation — before any branch is created, any pull request is opened, or any tracker status changes — not merely before its reviewer gates run; for a single-item run, the reviewer gates run only after a branch, and often a draft pull request, already exists, so requiring the preflight only before the gates would let mutation happen unchecked first.
- [ ] The batch orchestration protocol, the single-item orchestration protocol, and the reviewer platform's integration documentation describe the same outcomes, the same verdicts, and the same display labels, with no surface naming a verdict the others do not.
- [ ] The four disagreement cases are each illustrated with a worked example wherever they are described.
- [ ] The preflight changes no reviewer gate's behaviour after it passes: which reviewers run, what they look for, their verdict semantics, and their cycle limits are unchanged.

---

## Out of Scope (MVP)

1. **Creating a scratch pull request to test reviewer operability.** The brief offers "a real or scratch PR" as the thing the preflight asserts against. Deferral rationale: creating a pull request is a side effect, and AC-2 requires a correct configuration to pass without side effects. The preflight therefore cross-checks configuration and may read an existing pull request, but does not create one. Human confirmation requested: yes — this narrows an option the brief explicitly offered.

2. **Choosing where the preflight lives.** The brief offers a dedicated mode on the reviewer loop or a step in the bounded prelude. Deferral rationale: this is an implementation-surface choice with no product-visible difference, and the spec deliberately does not pick one. To be decided in the implementation plan. Human confirmation requested: no.

3. **The false-clean banner counting.** The brief names it as already addressed by prior work. This spec does not re-open it, and assumes a declined review is already distinguishable from a completed one. Human confirmation requested: no.

4. **Verifying that a platform will produce a good review.** The preflight decides whether a platform can review, not what it says. Review prompts, severity classification, verdict semantics, and cycle caps are untouched.

5. **Repairing a disagreeing surface automatically.** The preflight reports; the operator decides. Editing a surface on the operator's behalf would change review policy without being asked.

6. **Extending the cross-check beyond reviewer configuration.** Tracker configuration, guardrails, branch policy, and release configuration are out of scope even though they are read from the same files.

7. **Fixing unrelated misleading workflow diagnostics.** A workflow helper currently reports a tracker as unconfigured when it is correctly configured but the helper was loaded from an unsupported shell. It is the same class of failure — a diagnostic that names the wrong cause — and it informs the reporting standard this spec sets, but repairing it is separate work.

8. **Changing any reviewer platform's own behaviour, or the branch it reads its configuration from.** That behaviour is the platform's, and this feature documents it rather than altering it.

9. **Re-reviewing pull requests from runs that had no preflight.** The check applies to runs from the change forward.

10. **Fixing the preflight's time bound to a concrete value.** This spec requires a bound and states the product property it must satisfy — the preflight always reaches an outcome, and an unreachable or slow surface degrades to Undetermined rather than to waiting — but deliberately sets no number and does not say how the bound is measured. Deferral rationale: a defensible bound depends on how and where the check is performed, which item 2 also leaves open. To be decided in the implementation plan. Human confirmation requested: no.

11. **Detecting a live installation or service-availability loss that leaves every configuration surface unchanged** — for example, a platform's GitHub App removed, or its service otherwise made unavailable, after its own configuration file was last read, so `.coderabbit.yaml` (or the equivalent) still reads as enabled. Deferral rationale: the preflight's cross-check is a configuration read; detecting this failure mode needs a materially different mechanism — a live external-service probe — which Step 7a's own reachability classification already attempts and already documents as imperfect (its activity-proxy check can itself be a false Reachable after an App is removed; see `docs/workflow/development-workflow/integrations/coderabbit.md`). Extending this preflight's cross-check to the same kind of probe is deferred rather than duplicated ad hoc. Until it is added, Can review is a configuration-coherence verdict, not an absolute guarantee that a platform will actually review — including on the existing-pull-request path (the "A preflight against an existing pull request asserts operability" AC group), which also cross-checks configuration only. A platform whose installation was removed after its configuration was last read still declines silently; that decline is reported as a review failure when it happens, not as a preflight problem, exactly like the already-established "passes the preflight and then fails" case. Human confirmation requested: yes — this narrows brief objective B-5's "asserted operability" framing and the Overview's headline promise for this specific failure mode, and a human should decide whether that narrowing is acceptable or whether a live probe belongs in this feature's first iteration.

---

## Open Questions

1. May an operator override a Blocked outcome for a single run — proceeding deliberately with a platform that cannot review — and if so, must the override be recorded in that run's audit record? The argument for allowing it is that an operator who has read the report and accepts reduced coverage should not have to edit a surface to proceed. The argument against is that an override is exactly how the silent failure returns. No answer is assumed; the spec currently treats Blocked as a stop.

2. When the disagreement affects only part of a batch — for example a base branch coverage gap that applies to items targeting an epic integration branch but not to items targeting the main integration branch — should the preflight block the whole batch, or only the affected items? Blocking everything is safer and simpler to report; blocking only the affected items preserves throughput but makes the outcome harder to state in one line. No answer is assumed; the spec currently treats Blocked as a whole-run stop.
