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

---

### Use Case 2: A surface disagrees, and the run stops before dispatching anything

**Actor**: The orchestrating agent, and the workflow operator who reads the result.
**Preconditions**: The run is about to dispatch work. At least one reviewer platform in the resolved list cannot review the pull requests this run will open — because the platform's own configuration turns automatic review off, or excludes the draft stage the platform is listed for, or covers a set of base branches that does not include every base this run targets.

**Steps**:

1. The run performs the reviewer preflight before dispatching anything.
2. The preflight compares each platform's own configuration against the stage it is listed for and every base this run targets.
3. It finds the disagreement, classifies that platform Cannot review, and records which of the three surfaces disagrees and which setting inside it produced the disagreement.
4. It records the run outcome Blocked and reports it.
5. Nothing is dispatched.

**Postconditions**: No item was dispatched, no branch was created, no pull request was opened, and no tracker status changed on account of this run. The repository is in the state it was in before the run started. The operator has a report that names the platform, the surface, the setting, and at least one action that would change the outcome.

**Information shown**:

- The run outcome, Blocked, stated before any item-level output, so it cannot be mistaken for a per-item failure.
- Each platform that cannot review, by name.
- For each, which of the three surfaces disagrees — the shared workflow reviewer configuration, the machine-local override, or the platform's own configuration — identified by the file an operator would open, and the setting inside it identified by the name an operator would edit.
- What the surfaces say that is incompatible, stated as the contradiction rather than as two isolated facts: which stage the platform is listed for against which stages it will review, or which bases the run targets against which bases it covers.
- At least one action that would resolve the disagreement.

**Actions available**:

- Change the platform's own configuration so it covers this run's stage and every base it targets.
- Change the shared workflow reviewer configuration so the platform is listed for a stage it will actually review.
- Narrow the reviewer list for this machine through the machine-local override, accepting the reduced coverage deliberately rather than discovering it afterwards.
- Re-run after any of the above. The preflight is determined fresh each run and picks the change up with no further action.

**Considerations**:

- The three disagreement cases have different remedies and are never collapsed into one message. "Automatic review is off" is a different repair from "this base branch is not covered", and an operator told the wrong one will edit the wrong thing.
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

- The **shared reviewer list** is every platform the shared workflow reviewer configuration names for the lifecycle stages this run will exercise, before any machine-local override is applied.
- The **resolved reviewer list** is the platforms this machine will actually use. When a machine-local override is in effect for a lifecycle stage's list, it replaces the shared list for that stage outright rather than narrowing it: the resolved list is exactly the override's list, which may remove platforms the shared list named, add platforms the shared list never named, or both. When no override is in effect for a stage, the resolved list equals the shared list for that stage.

Cross-checking, per-platform verdicts about ability to review, and the run outcome are determined over the resolved list alone. Reporting enumerates the union of the shared list and the resolved list: every platform named by either appears exactly once, annotated with its cross-check verdict — Can review, Cannot review, or Undetermined — when it is in the resolved list (including a platform the override added that the shared list never named), or as Excluded by override when the shared list named it but the override's replacement list does not. A platform named by neither list is not reported, because this run never expected it to review and the override never added it.

- The preflight runs before any item is dispatched in a run, and before any branch, pull request, tracker status, comment, or label is created or changed by that run. A preflight that runs after dispatch has no value, because the cost it exists to prevent has already been incurred.
- The preflight cross-checks the surfaces against each other. A surface that is internally valid but contradicts another surface is a failure, and it is the only kind of failure this feature adds — each surface already validates itself.
- Surface precedence is unchanged: the machine-local override takes precedence over the shared workflow reviewer configuration for the machine it is on. The preflight cross-checks the resolved result, not the shared configuration alone, so a run on a machine with an override is checked against the reviewers that machine will actually use.
- Every platform named by the shared reviewer list or the resolved reviewer list appears in the report exactly once — with its cross-check verdict if it is in the resolved list (including a platform the override added that the shared list never named), or as Excluded by override if the shared list named it and the override's replacement list does not. No platform is silently omitted, because a silently omitted platform is indistinguishable from one that passed.
- A platform removed by the machine-local override is reported as Excluded by override, is not cross-checked, and never affects the run outcome. A deliberate exclusion is not a disagreement.
- A Blocked outcome stops the run before dispatch. It is not a warning the run proceeds past.
- An Undetermined verdict does not block, and is never reported as a pass: it is surfaced by name instead. The Decision-Gate Consistency Matrix states this guarantee canonically, and every other statement in this spec about unverified coverage defers to it.
- A Passed preflight has no side effects: it creates no pull request, posts no comment, applies no label, creates or modifies no branch, and modifies no tracked file. The same holds for a Blocked or Undetermined preflight — a preflight that reports a problem must not also create one.
- The preflight persists nothing of its own. Its outcome is run output. Where the enclosing run already keeps an audit record of itself, that existing record carries the preflight outcome as one more fact about a run already under way; the preflight never writes a record of its own and never causes a record to be written where the run would otherwise write none. Recording the outcome therefore changes no repository state and no external state, which is what lets a Passed preflight be side-effect-free.
- The preflight is bounded: every check it performs either reaches a definite answer or yields Undetermined within a bound, so the preflight can never hold a run open in front of a dispatch that never happens. The product property the bound must satisfy is that an unreachable or slow surface degrades to Undetermined rather than to waiting, and that the preflight's cost stays negligible against the work it guards. The bound's concrete value, and how it is measured, are deliberately not fixed in this spec and are an implementation-plan decision.
- Every failure report identifies the surface by the file an operator would open and the setting by the name an operator would edit, and states the contradiction rather than one side of it. A report an operator cannot act on directly does not satisfy this rule.
- The preflight's verdicts are determined fresh on each run. No verdict from an earlier run is an input to a later one: a record of a past run's outcome is history, not state the preflight reads or updates. A surface repaired between two runs flips the verdict on the second run with no further action, and a surface broken between two runs flips it back.
- A run may target more than one base branch, and base-branch coverage is evaluated for every base in the set the run targets, not for one representative base. A platform whose own configuration fails to cover any one of those bases is Cannot review, which blocks the whole run. The Decision-Gate Consistency Matrix states this canonically.
- The preflight reports what it checked against. A preflight performed before any branch exists is checked against the base branches the run targets, and names them; it does not claim to have verified branches that do not yet exist.
- The reviewer platform configuration in force for a pull request is the copy on that pull request's own branch. A preflight performed against an existing pull request reads that pull request's branch. This rule is documented in the platform's integration documentation, not only implied by the preflight's behaviour.
- The preflight decides whether a platform can review. It does not decide what the platform says, does not run a review, and does not change any reviewer gate's behaviour after it passes.
- The preflight reports a disagreement; it never repairs one. Editing a surface on the operator's behalf would change the repository's review policy without the operator asking.

---

## Statuses / Enum Values

These are per-run classifications. They describe one preflight and do not persist: the next run determines them again from scratch, so the only transition is a re-classification on a later run.

Per-platform verdicts:

| Code value          | Display label        | Description                                                                                                                                  |
| ------------------- | -------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| `operable`          | Can review           | The surfaces agree for this platform: it will review pull requests of the kind this run opens, at the stage it is listed for, against every base this run targets. |
| `not-operable`      | Cannot review        | The surfaces disagree for this platform. Always accompanied by every applicable disagreement reason and the surface that disagrees for each.  |
| `undetermined`      | Undetermined         | The preflight could not reach a definite answer for this platform. Never reported as Can review.                                             |
| `override-excluded` | Excluded by override | The platform is in the shared reviewer list but not in the resolved list: the machine-local override removed it. It is reported, never cross-checked, and never affects the run outcome. Not a failure, and never reported as Cannot review. |

Disagreement reasons, reported with every Cannot review verdict:

| Code value              | Display label              | Description                                                                                                                        |
| ----------------------- | -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| `review-disabled`       | Automatic review turned off | The platform's own configuration turns automatic review off, so it will decline every pull request in this repository.             |
| `stage-excluded`        | Stage not covered          | The platform is listed for a lifecycle stage its own configuration excludes — most commonly listed as a draft reviewer while its own configuration declines drafts. |
| `base-branch-unmatched` | Base branch not covered    | At least one base branch this run targets is not among the bases the platform's own configuration covers. Reported with the bases targeted and the bases covered. |
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

Platforms Excluded by override are reported but are not in the resolved list, so they never contribute to the run outcome.

---

## Operational Visibility

The preflight's only output is its report. There is no user interface, and no one is notified: the audience is the operator reading the run and the agent deciding whether to dispatch.

- **Run output, before dispatch**: the run outcome, and every platform named by the shared reviewer list or the resolved reviewer list annotated exactly once — Can review, Cannot review, or Undetermined for the platforms in the resolved list (including one the override added), Excluded by override for the platforms the override removed — emitted before any item-level output, so the outcome cannot be mistaken for a per-item result.
- **Failure report**: on Blocked, each platform that cannot review, its disagreement reason, the surface that disagrees identified by the file an operator would open, the setting identified by the name an operator would edit, the contradiction stated in full, and at least one action that would change the outcome.
- **Unverified report**: on Passed, some unverified, each undetermined platform with its reason, kept visibly separate from the platforms that passed.
- **Override notice**: when a machine-local override is in effect, the report records that it is, and which platforms it removed and which it added, so a coverage change — reduced, different, or both — is visible at the moment it is chosen rather than only when a review is missing.
- **Scope statement**: every report states what it was checked against — every base branch this run targets, or a specific pull request's branch — so a reader never has to guess whether a branch-local divergence was covered.
- **Audit record**: the preflight outcome is carried by the record the enclosing run already keeps of itself, so a run reported as complete can be checked afterwards for whether its reviewers were verified before it started. This is one more fact added to a record the run was already producing — the preflight creates no record of its own, and causes no record to exist where the run would otherwise keep none. Nothing the preflight does changes repository or external state, which is why carrying the outcome does not breach the no-side-effects rule that AC-2 tests.

---

## Decision-Gate Consistency Matrix

The preflight is a workflow decision gate: it takes several inputs, produces one of a fixed set of outcomes, and each outcome has a required next action. The matrix below is the canonical statement of that behaviour.

### Gate inputs

| Input                                                    | Where it comes from                                                        | Why it matters                                                                        |
| -------------------------------------------------------- | ---------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| The reviewer list for each lifecycle stage               | The shared workflow reviewer configuration                                  | Names which platforms are expected to review, and at which stage                      |
| The machine-local override, when one is in effect        | The machine-local reviewer override                                         | Replaces the shared list for that stage outright — the resolved list may be a subset, a superset with platforms the shared list never named, or an entirely different list |
| Each platform's own review configuration                 | The platform's own configuration, read from the branch in force             | Decides whether the platform will review at all, at which stage, and against which bases |
| The set of base branches this run targets                | The resolved execution base of every item the run will dispatch              | A base the platform does not cover means every pull request the run opens against that base is declined |
| The kind of pull request the run will open               | The stage the run is dispatching                                            | A draft-stage listing against a platform that declines drafts is a disagreement       |
| Whether each configured value is a supported platform    | The canonical list of supported reviewer platforms                          | An unsupported value must be reported, not dropped                                    |

Where a platform's own configuration cannot be read, that platform is Undetermined with the reason it could not be read. Where the resolved reviewer list itself cannot be read, the existing configuration-validation behaviour applies unchanged; the preflight adds no new handling for it, because a list that cannot be read names no platforms to cross-check.

**A run may target more than one base branch.** One run can dispatch items against an epic integration branch and items against the main integration branch, so the gate's base-branch input is the set of every base the run will target, never a single representative base. Base-branch coverage is evaluated for every base in that set: a platform in the resolved list is Can review only where its own configuration covers all of them, and is Cannot review with the reason Base branch not covered where it covers none of them or only some. Where the surfaces differ between two targeted bases, each base is evaluated against the copy of the surfaces on that base, and the report names every base that was checked.

**Under the rule this spec sets, a coverage gap on any base in that set blocks the whole run.** Such a gap is a Cannot review verdict for that platform, and Blocked is a hard whole-run stop: nothing is dispatched, for any base, including the bases the platform does cover. The gate outcome and the required next action are therefore fully determined for a run targeting several bases. Open Question 2 asks only whether a later refinement should narrow that stop to the items targeting the uncovered base; it does not leave today's outcome undefined.

### Triggers

| Trigger                                                   | Why it fires                                                                          |
| ----------------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| A run is about to dispatch its first item                 | The gate's normal entry point, and the last moment before cost is incurred            |
| A run is retried after a Blocked outcome                  | The retry is the operator's remedy path; a repaired surface must be picked up          |
| A preflight is performed against an existing pull request | Answers the stricter, branch-specific question that the pre-dispatch check cannot      |

An empty resolved reviewer list is not a trigger failure: the gate still runs, reports that no platform is configured to review, and produces Passed, because no platform in the resolved list disagrees. That is a legitimate configuration and not a disagreement.

### Allowed outcomes and required next actions

| Outcome                 | When it is produced                                                | Required next action                                                                     |
| ----------------------- | -------------------------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| Passed                  | No platform in the resolved list is Cannot review, and none is Undetermined | Dispatch proceeds. No operator action, no confirmation collected                |
| Passed, some unverified | No platform in the resolved list is Cannot review, and at least one is Undetermined | Dispatch proceeds. The report names every unverified platform for the operator to read |
| Blocked                 | At least one platform in the resolved list is Cannot review        | Nothing is dispatched. The operator repairs a surface, or narrows the list, and re-runs   |

**Outcome determination is total and mutually exclusive.** Every platform in the resolved list carries exactly one of Can review, Cannot review, or Undetermined, and the outcome is the most severe verdict present: Blocked if any platform is Cannot review; otherwise Passed, some unverified if any platform is Undetermined; otherwise Passed. Exactly one outcome therefore applies to any configuration, including one where a platform is Cannot review and another is Undetermined — that configuration is Blocked, and the undetermined platform is still reported as Undetermined. Platforms Excluded by override are reported but are not in the resolved list and never change the outcome.

**A platform's Cannot review verdict names every disagreement reason that applies to it, not one.** The three disagreement checks — automatic review turned off, a listed stage its own configuration excludes, and an uncovered base branch — are independent of each other, and a platform can fail more than one at once: a platform can simultaneously have automatic review off, be listed for a stage its own configuration declines, and cover a set of bases that omits one this run targets. The gate runs all applicable checks for every platform in the resolved list and reports the complete set of disagreement reasons that apply on that platform's single Cannot review verdict. No check is skipped because another already produced Cannot review, and no precedence between the reasons is defined, because a report that names every applicable reason needs none — precedence would only be necessary to pick one reason to the exclusion of others, and this gate never does that.

**Unverified coverage is surfaced, never assumed clean.** This is the canonical statement of the guarantee, and every other statement in this spec about Undetermined defers to it. An Undetermined platform is never counted as Can review and never disappears into a Passed outcome. Dispatch may proceed while a platform is unverified, but only under Passed, some unverified, which requires the report to name that platform as unverified. What is forbidden is dispatching while treating an unverified platform as though it had been verified; what is required is that the operator is told, before the first item goes out, exactly which coverage was assumed rather than checked. No outcome repairs a surface.

### Mirror surfaces

| Surface                                                   | What it must say                                                                                             |
| ----------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| The batch orchestration protocol                          | That the preflight runs before the first dispatch, and that a Blocked outcome stops the batch before mutation |
| The single-item orchestration protocol's reviewer gates   | That the gates run after a preflight that did not block, and that their own behaviour is unchanged           |
| The reviewer platform's integration documentation         | The branch-in-force resolution rule, its two consequences, and the three disagreement cases with their remedies |
| The workflow configuration's own commentary               | Nothing that contradicts the cross-check rule or describes single-surface validation as sufficient           |

### Examples

Worked examples are part of the changed surface wherever a disagreement case is described. Each of the three disagreement cases is illustrated with the contradiction it produces and the remedy it calls for, so an operator can match a report to an example without translating between them.

---

## Acceptance Criteria

### A disagreement is reported before dispatch, naming the surface (AC-1)

- [ ] With a platform listed in the resolved reviewer list whose own configuration turns automatic review off, the preflight produces Blocked, classifies that platform Cannot review with the reason Automatic review turned off, and names the platform's own configuration as the surface that disagrees.
- [ ] With a platform listed as a draft-stage reviewer whose own configuration excludes drafts, the preflight produces Blocked, classifies that platform Cannot review with the reason Stage not covered, and states both sides of the contradiction: the stage it is listed for and the stages its own configuration covers.
- [ ] With a platform whose own configuration covers a set of base branches that does not include every base this run targets, the preflight produces Blocked, classifies that platform Cannot review with the reason Base branch not covered, and names both the bases targeted and the bases covered.
- [ ] Each of the three disagreement reasons is reported distinctly; none is reported in place of another, and none is reported as a generic configuration error.
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

### A correct configuration passes without side effects (AC-2)

- [ ] With all three surfaces in agreement and every platform in the resolved list verified as Can review, the preflight produces Passed and the run dispatches exactly as it does today.
- [ ] A Passed preflight creates no pull request, posts no comment, applies no label, creates or modifies no branch, changes no tracker status, and modifies no tracked file. Running it on a clean checkout leaves the checkout clean and leaves the repository's pull request list unchanged.
- [ ] A Blocked or Undetermined preflight has the same absence of side effects as a Passed one.
- [ ] A Passed preflight runs no review and dispatches no reviewer.
- [ ] A Passed preflight collects no operator confirmation and does not pause the run.
- [ ] This repository's own shipped configuration deliberately keeps the platform that carries a repository configuration file out of every lifecycle stage, while that file's own automatic review is off. Because that platform is not listed for any stage this run exercises, it is in neither list, contributes no Cannot review verdict, and its absence never produces Blocked on its own account — a platform that is not listed for any stage is not a platform this run expects to review. The run's actual outcome for this configuration is whichever of Passed or Passed, some unverified the cross-check of the platforms the shared reviewer list does name produces, following the canonical outcome-determination rule; this platform's absence does not by itself require Passed over Passed, some unverified.
- [ ] The preflight reaches an outcome without operator intervention even when a platform's configuration cannot be read, rather than leaving the run waiting in front of a dispatch that never happens.
- [ ] Verdicts are determined fresh each run: repairing a surface between two runs flips Blocked to Passed on the second run with no other change, and breaking it flips the verdict back. No earlier run's recorded outcome is consulted.
- [ ] The preflight persists nothing of its own. Its outcome reaches the operator as run output, and where the enclosing run already keeps a record of itself, that existing record carries the outcome; the preflight writes no record of its own and causes none to be written where the run would keep none. Recording the outcome changes no repository state and no external state, so it is consistent with the absence of side effects required above.

### Unverifiable platforms are never reported as verified

- [ ] A platform that exposes no configuration the preflight can read is classified Undetermined with the reason No configuration to cross-check. Where no platform in the resolved list is Cannot review, the run outcome is then Passed, some unverified — never Passed. Where some other platform is Cannot review, the run outcome is Blocked and that platform is still reported as Undetermined; the two criteria never demand different outcomes for the same configuration.
- [ ] A platform whose configuration could not be read within the preflight's bound — whose concrete value the implementation plan sets — is classified Undetermined with the reason Check did not complete, distinct from No configuration to cross-check. The preflight reaches its outcome rather than waiting on that platform.
- [ ] The report keeps undetermined platforms visibly separate from platforms that passed.
- [ ] An Undetermined verdict does not block dispatch on its own.

### The branch-in-force resolution behaviour is documented (AC-3)

- [ ] The reviewer platform's integration documentation states that the platform's own configuration is read from the pull request's own branch, not from the branch the pull request targets.
- [ ] It states the consequence that a configuration fix takes effect on the very pull request that carries it, so a broken review can be repaired on the branch in front of the operator without waiting for a merge.
- [ ] It states the consequence that a branch can carry a configuration that differs from the repository's intended review policy, without anything else reporting the divergence.
- [ ] It records the observation that established the behaviour, so the statement is traceable to evidence.
- [ ] The documentation states that a pre-dispatch preflight is checked against the base branches the run targets and therefore cannot see a divergence introduced by a branch that does not yet exist.
- [ ] No workflow surface contradicts the resolution rule or describes the integration-branch copy as the one in force.

### The preflight is reachable where it is needed, and consistent across surfaces

- [ ] A batch run performs the preflight before dispatching its first item, and a Blocked outcome stops the batch before any item is dispatched.
- [ ] A single-item run performs the preflight before its reviewer gates run.
- [ ] The batch orchestration protocol, the single-item orchestration protocol, and the reviewer platform's integration documentation describe the same outcomes, the same verdicts, and the same display labels, with no surface naming a verdict the others do not.
- [ ] The three disagreement cases are each illustrated with a worked example wherever they are described.
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

---

## Open Questions

1. May an operator override a Blocked outcome for a single run — proceeding deliberately with a platform that cannot review — and if so, must the override be recorded in that run's audit record? The argument for allowing it is that an operator who has read the report and accepts reduced coverage should not have to edit a surface to proceed. The argument against is that an override is exactly how the silent failure returns. No answer is assumed; the spec currently treats Blocked as a stop.

2. When the disagreement affects only part of a batch — for example a base branch coverage gap that applies to items targeting an epic integration branch but not to items targeting the main integration branch — should the preflight block the whole batch, or only the affected items? Blocking everything is safer and simpler to report; blocking only the affected items preserves throughput but makes the outcome harder to state in one line. No answer is assumed; the spec currently treats Blocked as a whole-run stop.
