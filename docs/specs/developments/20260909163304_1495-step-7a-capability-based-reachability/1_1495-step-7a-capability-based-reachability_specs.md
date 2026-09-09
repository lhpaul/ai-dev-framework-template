# Step 7a Capability-Based Reviewer Reachability — Spec

---

## Overview

The internal review gate decides, before it dispatches anyone, which of the configured reviewers it can actually use. Today it decides that from the identity of the runner driving the gate: a fixed table says the Codex reviewer is unreachable whenever the driving runner is not Codex, no matter what is installed on the machine. The shipped configuration names Codex as the only internal reviewer, so on any other supported runner the gate finds nothing to dispatch and blocks — even when the Codex command is installed, on the path, and about to be used successfully by the next gate in the same pipeline.

This feature makes the decision follow capability instead of identity: a reviewer counts as reachable when the gate can actually invoke it in the environment it is running in, at the moment it runs. It also changes the shipped default configuration so that a repository using it out of the box never blocks this gate purely because of who is driving it. When a reviewer genuinely cannot be invoked, the gate still stops or warns exactly as the configured policy says — but it names the reviewer, says which kind of thing was missing, and says what the operator can do about it.

The problem is recurrent, not hypothetical: four occurrences are on record for this repository, across a plan-stage pull request, an implementation-stage fast-track pull request, a framework dogfood run, and the run that produced this spec. Each one was resolved by a human choosing and applying a machine-local override, or by standing up a second runner purely to satisfy the gate.

---

## Use Cases

### Use Case 1: A configured reviewer's runtime is present, and the gate uses it

**Actor**: The Work Item Runner — the agent driving a work item through the internal review gate.
**Preconditions**: A draft pull request has reached the internal review gate. The resolved configuration names at least one supported reviewer. That reviewer's runtime is present and callable in the environment the gate is running in. The runner driving the gate is not the reviewer's own native runner.

**Steps**:

1. The runner resolves the configured reviewer list, applying the machine-local override file when one is in effect.
2. Before dispatching anyone, the runner determines each configured reviewer's availability against the environment it is running in.
3. It finds the reviewer's runtime present and classifies it Reachable.
4. It dispatches that reviewer and waits for a verdict.

**Postconditions**: The reviewer ran and returned a verdict. The gate proceeded on its own, without a human being asked to choose a workaround, without a machine-local override being written, and without a second runner being started.

**Information shown**:

- The gate summary on the pull request lists every configured reviewer and its availability verdict.
- No warning about an unreachable reviewer, because there is none.

**Actions available**:

- Nothing is required of the operator. The run continues to the next gate.

**Considerations**:

- The availability decision is made fresh each time the gate runs. A runtime installed between two runs makes the reviewer reachable on the second run with no configuration change, and a runtime removed makes it unreachable again.
- The reviewer being reachable says nothing about whether it will approve. A reachable reviewer that then fails, errors, or times out mid-review is a review failure and is reported as one — never as unreachable.

---

### Use Case 2: A configured reviewer genuinely cannot be invoked

**Actor**: The Work Item Runner, and the operator who reads the result.
**Preconditions**: A draft pull request has reached the internal review gate. At least one configured reviewer cannot be invoked in this environment — its runtime is absent, a prerequisite outside the environment is missing, the availability determination could not be completed within its bound, or the configured value is not a reviewer this workflow supports.

**Steps**:

1. The runner resolves the configured reviewer list and determines availability for each entry.
2. It classifies the reviewer Unreachable and records which kind of thing was missing.
3. It applies the configured unavailable-reviewer policy to the resulting set.
4. It reports the outcome on the pull request.

**Postconditions**: Either the gate proceeded with the reviewers it could reach, or it blocked. In both cases the report names each unreachable reviewer, the kind of thing that was missing, and at least one action the operator can take. Nothing was installed, provisioned, or substituted on the operator's behalf.

**Information shown**:

- Each unreachable reviewer by name.
- For each, one of the defined reason categories — the runtime is not present, a prerequisite outside this environment is missing, the determination did not complete, or the configured value is not a supported reviewer.
- At least one action that would change the outcome: make the runtime available, satisfy the named prerequisite, correct the configured value, or narrow the reviewer list for this machine.
- When the gate blocked, whether a machine-local override was in effect, reported from what was actually resolved rather than inferred.

**Actions available**:

- Make the missing runtime or prerequisite available and re-run the gate.
- Narrow the reviewer list for this machine through the machine-local override file.
- Accept reduced coverage, when the policy in force allows it.

**Considerations**:

- "The runtime is not present" and "a prerequisite outside this environment is missing" are different problems with different remedies, so they are never collapsed into one message.
- A determination that cannot be completed promptly is treated as unreachable rather than left to hang. The gate always reaches a verdict.
- A configured value the workflow does not support is reported by name. It is never silently dropped, because silently dropping it would reduce review coverage invisibly.

---

### Use Case 3: A repository runs the gate on the shipped default configuration

**Actor**: An operator — human or agent — running the workflow in a repository that has not customized its reviewer configuration.
**Preconditions**: The repository uses the shipped default configuration unchanged. No machine-local override file exists. A supported runner is driving the gate.

**Steps**:

1. The operator starts a work item that reaches the internal review gate.
2. The runner resolves the default reviewer list and determines availability.
3. At least one reviewer is reachable, and the gate dispatches it.

**Postconditions**: The gate produced a verdict. The operator was not asked to write an override file, switch runners, or start a second runner to get past the gate.

**Information shown**:

- The gate summary, listing the configured reviewers and which of them ran.

**Considerations**:

- This holds for every supported runner, not only for the one the template happens to favor.
- The shipped configuration's own commentary must agree with this. A shipped comment that describes blocking on a supported runner as expected behavior would contradict the guarantee and mislead the operator into thinking a real block is normal.
- This use case does not promise a reviewer in an environment where no supported runner is driving the gate at all. It promises that the runner driving the gate is never, by itself, the reason there is nothing to dispatch.

---

### Use Case 4: An operator deliberately narrows the reviewer list for one machine

**Actor**: An operator working on a machine that intentionally lacks some reviewers.
**Preconditions**: The machine-local override file names a subset of reviewers. The gate is about to run.

**Steps**:

1. The runner resolves the configured list, and the machine-local override takes precedence.
2. Reviewers that the override leaves out are recorded as Excluded by override.
3. Availability is determined only for the reviewers the override kept.

**Postconditions**: The gate ran the intended subset. Reviewers the operator deliberately removed produced no unreachability warning, because their absence was a decision rather than a failure.

**Information shown**:

- That an override was in effect, which file it came from, and the list it replaced.
- The excluded reviewers, marked Excluded by override rather than Unreachable.

**Considerations**:

- The resolved configuration is the only way to remove a reviewer from this gate. There is no second opt-out — no label, no environment flag, no per-pull-request escape.
- A reviewer that the override kept is still subject to the availability determination. Keeping it in the list does not assert that it can be invoked.

---

## Business Rules

- A reviewer is Reachable when the gate can actually invoke it in the environment the gate is running in, at the moment the gate runs. It is Unreachable otherwise.
- The identity of the runner driving the gate is not, on its own, grounds for classifying a reviewer Unreachable. The driving runner counts as one of the runtimes present in the environment; it does not exclude the others.
- Availability is determined fresh on every gate run. No verdict is cached across runs, and no verdict is carried between pull requests.
- Determining availability must not review anything, must not post comments, must not change the pull request's state, and must not modify the repository.
- Determining availability is bounded in time, and the bound is a fixed property of the gate rather than something an operator sets per run. Resolving the whole configured list takes at most ten seconds; any single determination still unanswered at that point yields Unreachable with the reason that it did not complete, so the gate always reaches a verdict. Ten seconds is a ceiling, not a target — the check precedes a review that takes minutes, so it should be imperceptible in practice, and the implementation may set any shorter per-reviewer bound.
- Being reachable is a statement about invocability only. A reviewer that is dispatched and then fails, errors, or times out is reported as a review failure, and the distinction between the two is visible to the operator.
- The gate never installs a missing runtime, never provisions a missing prerequisite, and never substitutes a different reviewer for an unreachable one. Where the resolved configuration names reviewers, those are the only ones dispatched; the fallback above applies only where it names none.
- Naming a reviewer in the resolved configuration is the authorization to invoke it. The gate does not ask for separate confirmation before invoking a configured reviewer whose runtime is present.
- Evaluation order is fixed, and every outcome below is stated under it: resolve the configured list (machine-local override first, shipped configuration otherwise), mark the reviewers the override left out as Excluded by override, determine availability for each remaining reviewer, then apply the unavailable-reviewer policy to the result.
- The resolved configuration is the single source of truth for which reviewers this gate runs. The unavailable-reviewer policy is the single source of truth for what happens when one of them is unreachable. Neither has a second source.
- When neither the shipped configuration nor the machine-local override defines a reviewer list, and when a defined list resolves to no entries at all, the gate falls back to running the stage-appropriate default reviewer once and records that it did. The gate never reports success having dispatched nobody.
- The stage-appropriate default reviewer is the reviewer the runner currently driving the gate provides for the pull request's stage — the spec reviewer for a spec pull request, the plan reviewer for an implementation plan, the code reviewer for an implementation change. It is selected by the stage and by the driving runner, never from a fixed reviewer name, so the fallback is reachable by construction: the runner asked to supply it is the one already running the gate. This is what makes the fallback safe to rely on rather than a second way to reach the same block.
- A configured entry that is not a supported reviewer value is classified Unreachable, is reported by name, and is never silently discarded.
- The unavailable-reviewer policy keeps its existing meanings and its existing default. This feature changes what makes a reviewer unreachable, not what the gate does about it.
- The shipped default reviewer list must name at least one reviewer that is reachable in any environment where a supported runner is driving the gate.
- An availability determination that ends without a definite answer is Unreachable with the reason that the check did not complete, whether it ran out of time or ended early without one. It is never read as either a present or an absent runtime: an errored or refused prerequisite check has not shown the prerequisite to be missing, only that the question went unanswered, and reporting it as Prerequisite missing would send the operator to fix something that may be fine. This reason applies only to a determination the gate started and could not finish; a value it never had to check is covered by the supported-value rules instead.
- Every workflow surface that states which reviewers this gate supports, or how their availability is decided, must agree with the canonical protocol statement. No surface may name a reviewer value the canonical protocol does not list, and no surface may attribute availability to runner identity.

---

## Statuses / Enum Values

These are per-run classifications recorded for each configured reviewer. They describe one gate run and do not persist: the next run determines them again from scratch, so the only transition is a re-classification on a later run.

| Code value          | Display label        | Description                                                                                                    |
| ------------------- | -------------------- | -------------------------------------------------------------------------------------------------------------- |
| `reachable`         | Reachable            | The gate can invoke this reviewer in the current environment. Whether it is actually dispatched is decided afterwards by the policy outcome, not by this classification. |
| `unreachable`       | Unreachable          | The gate cannot invoke this reviewer in the current environment. Always accompanied by a reason category.       |
| `override-excluded` | Excluded by override | The machine-local override left this reviewer out. Not a failure, and never reported as unreachable.            |

Reason categories, reported with every Unreachable classification:

| Code value              | Display label                    | Description                                                                                                     |
| ----------------------- | -------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| `runtime-absent`        | Runtime not present              | The reviewer's runtime is not installed or not callable in this environment.                                    |
| `prerequisite-missing`  | Prerequisite missing             | Something outside this environment that the reviewer needs — an installed app, an access grant — is not in place. |
| `check-inconclusive`    | Availability check did not complete | The determination did not reach a definite yes or no. Covers both a check that exceeds its time bound and one that ends promptly without an answer, such as a prerequisite check that errors or is refused. |
| `value-not-supported`   | Not a supported reviewer         | The configured value is not a reviewer this workflow supports.                                                   |

Gate outcomes for one run:

| Code value                | Display label                  | Description                                                                                     |
| ------------------------- | ------------------------------ | ------------------------------------------------------------------------------------------------- |
| `proceeded`               | Proceeded                      | Every configured reviewer that the override kept was reachable, and all of them ran.            |
| `proceeded-reduced`       | Proceeded with reduced coverage | At least one reviewer was unreachable, at least one was reachable, and the policy allowed it.   |
| `blocked`                 | Blocked                        | No reviewer was dispatched. The pull request stays draft and the run escalates to a human.      |

---

## Operational Visibility

- **Gate summary on the pull request**: every configured reviewer with its display label — Reachable, Unreachable, or Excluded by override — and, for each Unreachable one, its reason category. The summary states the gate outcome.
- **Reduced-coverage warning**: when the gate proceeds with a subset, it names each unreachable reviewer, its reason, the reviewers that will run, and how far coverage was reduced.
- **Block report**: when the gate blocks, it says so on the pull request, names every reviewer with its verdict and reason, states which policy produced the block, gives at least one action that would change the outcome, and reports whether a machine-local override was in effect — taken from what was actually resolved, never inferred.
- **Override notice**: when a machine-local override is in effect, the gate records which file it came from and the list it replaced, before availability is determined.
- **Run log**: the same per-reviewer verdicts and reasons appear in the run's console output, so a run that never reached the point of commenting is still diagnosable.

---

## Decision-Gate Consistency Matrix

The internal review gate is a workflow decision gate: its outcome depends on several inputs, and this feature changes one of them. The matrix below is the canonical statement of the changed behavior. Outcomes are enumerated under the evaluation order stated in Business Rules; combinations that order makes unreachable are noted where they would otherwise look missing.

### Gate inputs

| Input                                       | Where it comes from                                                                | Why it matters                                                                     |
| ------------------------------------------- | ---------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| The configured reviewer list                | The shipped repository configuration, or the machine-local override when in effect | Names which reviewers this gate is meant to run                                    |
| Which reviewers the override left out       | Comparing the override list to the shipped list                                    | Distinguishes a deliberate exclusion from a failure                                |
| Whether each reviewer can be invoked here   | The environment the gate is running in, determined at the moment the gate runs     | **Changed by this feature.** Was the driving runner's identity; is now capability  |
| The reason a reviewer cannot be invoked     | The same determination                                                             | Decides what the operator is told and what remedy is offered                       |
| The unavailable-reviewer policy             | The shipped configuration, or the machine-local override when in effect            | Decides whether an unreachable reviewer warns or blocks                            |
| Whether each configured value is supported  | The canonical list of supported reviewer values                                    | An unsupported value must be reported, not dropped                                 |

Every row is state the gate reads. Where the gate cannot complete a per-reviewer availability determination, that reviewer is Unreachable with the reason that the determination did not complete; it never proceeds as though the reviewer were fine. The two rows that are read once for the whole run rather than per reviewer — the configured reviewer list and the unavailable-reviewer policy — behave differently when unreadable, because neither identifies a reviewer to classify: they block the gate, as set out below.

The unavailable-reviewer policy is itself one of these inputs, and its own absent, empty, malformed, and unsupported states are defined rather than left to inference. Absent or empty means no policy was expressed, so the shipped default applies: an unreachable reviewer warns and the reachable ones still run. A value that is present but is not one of the supported policy values, or a policy input the gate cannot read at all, is not treated as the default — the operator expressed a policy and the gate cannot tell which, and guessing the permissive one would let a run proceed with reduced coverage that the operator may have meant to forbid. Those states block the gate and name the offending value or the input that could not be read.

### Triggers

Triggers are events. They decide when the gate runs, are never read as inputs, and their absence is not a failure.

| Trigger                                                     | Why it fires                                                                             |
| ----------------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| A draft pull request reaches the internal review gate       | The gate's normal entry point                                                            |
| The gate restarts a review cycle after fixes                | Availability is determined again, because the environment may have changed mid-run       |
| The run is retried after a block                            | The retry is the operator's remedy path; a newly available runtime must be picked up     |

Input states that are absent, empty, or malformed do not suppress the gate. No configured list in either file, and a defined list that resolves to no entries, both fall back to the stage-appropriate default reviewer. An unsupported value is classified Unreachable and reported by name. A determination that will not complete is bounded and classified Unreachable.

A malformed reviewer list is treated differently from an absent or empty one, and the distinction is deliberate. Absent and empty are legible states: they say the operator configured no reviewers, and falling back to the default reviewer honours that. Malformed means the operator did configure something and the gate cannot tell what — the file will not parse, or the reviewer list is present but is not a list of values. Falling back there would silently substitute the gate's guess for an intent the operator expressed and got wrong, which is the same invisible loss of coverage this feature exists to prevent. So a malformed input blocks, names the file and the input that could not be read, and leaves the pull request draft. Nothing about a malformed input is inferred, and no reviewer is dispatched on the strength of a guess.

### Allowed outcomes and required next actions

| Inputs                                                                                     | Outcome                          | What the gate does                                                                    | Operator's next action                                       |
| ------------------------------------------------------------------------------------------ | -------------------------------- | ------------------------------------------------------------------------------------- | ------------------------------------------------------------ |
| No reviewer list defined anywhere, or a defined list resolving to no entries               | Proceeded                        | Runs the stage-appropriate default reviewer once and records that the fallback applied | None                                                         |
| Every reviewer the override kept is reachable                                              | Proceeded                        | Dispatches all of them; no warning comment                                            | None                                                         |
| Some reviewers excluded by the override, every remaining one reachable                     | Proceeded                        | Dispatches the kept subset; excluded ones marked Excluded by override, not warned about | None                                                         |
| At least one reviewer unreachable, at least one reachable, policy allows reduced coverage  | Proceeded with reduced coverage  | Warns, naming each unreachable reviewer and its reason, then dispatches the rest       | Optionally restore the missing runtime or prerequisite       |
| At least one reviewer unreachable, at least one reachable, policy forbids reduced coverage | Blocked                          | Dispatches nobody; reports the policy as the cause; pull request stays draft            | Restore the missing reviewer, or change the policy for this machine |
| No reviewer reachable, under any policy                                                    | Blocked                          | Dispatches nobody; reports every reviewer and reason, and the override state           | Restore a runtime or prerequisite, or narrow the list locally |
| No unavailable-reviewer policy configured anywhere, or a configured policy that resolves to nothing | Follows the policy rows above     | Applies the shipped default policy, under which an unreachable reviewer warns rather than blocks | None                                                         |
| The unavailable-reviewer policy is set to an unsupported value, or cannot be read              | Blocked                          | Dispatches nobody; names the offending policy value or the input that could not be read          | Correct the policy value                                     |
| The reviewer list is defined but cannot be read as a list of values, or its file will not parse | Blocked                          | Dispatches nobody; names the file and the input that could not be read; does not fall back to the default reviewer | Correct the malformed input                                  |
| A configured value is not supported, and something else is reachable                       | Follows the policy rows above    | Reports the unsupported value by name alongside the other verdicts                     | Correct the configured value                                 |
| A configured value is not supported, and it is the only entry                              | Blocked                          | Reports the unsupported value by name as the cause                                     | Correct the configured value                                 |
| A reviewer is reachable, is dispatched, and then fails or errors                           | Not an availability outcome      | Reported as a review failure through the gate's existing review-outcome handling        | Address the review failure                                   |

The combination "excluded by the override and also unreachable" cannot occur: under the stated order, exclusion is settled before availability is determined, and excluded reviewers are never examined. No outcome installs software, provisions access, substitutes a reviewer, or converts the pull request out of draft.

### Mirror surfaces

| Surface                                                                  | Relationship                                                                    | Consistency requirement                                                                                             |
| ------------------------------------------------------------------------ | ------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| The internal review gate section of the work item runner protocol        | **Canonical.** States the supported reviewer values and the availability rule    | Must state capability, not runner identity, and must carry the outcome and reason vocabulary defined here          |
| The Claude and Cursor work item runner agent definitions                 | Restate reviewer dispatch, and today name a reviewer value the protocol does not | Must not name an unsupported reviewer value, and must not attribute availability to runner identity                |
| The shipped repository configuration and its commentary                  | Ships the default list and explains it to operators                             | Must not describe blocking on a supported runner as expected behavior, and must match the default guarantee        |
| The CodeRabbit integration guidance                                      | Already determines that reviewer's availability from runtime conditions          | Unchanged. This feature aligns the other reviewers with it rather than altering it                                 |
| The Codex skills and the Cursor workflow rules                           | Point at the configuration key without restating the availability rule           | Must stay silent on the rule or match the canonical statement; pointing at the key is not a restatement            |

### Examples

| Situation                                                                                        | Outcome                         | Reason                                                                                   |
| ------------------------------------------------------------------------------------------------ | ------------------------------- | ------------------------------------------------------------------------------------------ |
| Sole configured reviewer is Codex; a different supported runner drives the gate; the Codex command is installed and callable | Proceeded                       | Capability is present; the driving runner's identity is not a reason to skip it           |
| The same repository on a machine where the Codex command is not installed                        | Blocked                         | Nothing is reachable — reported as Runtime not present, with the remedies                  |
| Two reviewers configured; one runtime present, one absent; policy allows reduced coverage        | Proceeded with reduced coverage | One reviewer ran; the warning named the other and why                                     |
| The same, with the policy that forbids reduced coverage                                          | Blocked                         | The policy, not the classification, is the cause — and the report says so                  |
| The machine-local override keeps one of two reviewers, and that one is reachable                 | Proceeded                       | The removed reviewer is Excluded by override, and produces no warning                     |
| CodeRabbit configured, its app not installed on the repository                                   | Unreachable                     | Prerequisite missing — a different remedy from an absent runtime, so a different reason    |
| A reviewer is reachable, is dispatched, and then errors partway through                          | Review failure                  | Availability and review outcome are separate; calling this unreachable would misdirect     |
| The configured list contains a value the workflow does not support                               | Unreachable                     | Reported by name as Not a supported reviewer; dropping it would cut coverage invisibly     |

### Issue-objective traceability

Acceptance criteria are referenced by group — the sub-headings under **Acceptance Criteria** — because criterion numbers shift during review while group names do not.

| Objective from issue #1495                                                                                        | Disposition                                                                                                                                                                                                          |
| ----------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Direction 1 — determine reachability from actual capability instead of a static identity-based classification      | Covered. Groups: *Reachability follows capability*, *Configuration inputs that are absent, empty, malformed, or unsupported*                                                                                                     |
| Direction 1 — invoke the reviewer automatically when a working path exists, rather than escalating                 | Covered. Group: *Reachability follows capability* — a reachable reviewer is dispatched with no human step                                                                                                            |
| Direction 2 — ship a default configuration that does not block a repository out of the box on a supported runner   | Covered. Group: *The shipped default never traps*                                                                                                                                                                    |
| Direction 2 — the alternative of documented local-override guidance instead of a fixed default                     | Out of Scope, item 1. The human chose both directions, which makes the guidance-only alternative moot: an override the operator must write is the workaround this item exists to remove                              |
| Direction 2's framing as a substitute for direction 1 ("keep identity-based classification")                       | Superseded by the confirmed decision to do both. Recorded here so the brief's wording is not read as a live constraint                                                                                                |
| Eliminate the recurring block-and-escalate cycle on every run driven by a non-Codex supported runner               | Covered. Groups: *Reachability follows capability*, *The shipped default never traps*                                                                                                                                |
| Keep the operator able to tell what happened when a reviewer really is unavailable                                 | Covered. Group: *The operator can tell why*                                                                                                                                                                          |
| From the issue comments — record a standing decision to satisfy the gate by starting a second runner               | Out of Scope, item 2. It is a workaround for the defect this spec removes, and the comment itself scopes it to "until #1495 advances"                                                                                 |
| Surfaces that contradict the canonical supported-reviewer list                                                     | Covered as a consistency requirement. Group: *Surfaces agree*. Which way to resolve the specific contradiction is Open Question 1                                                                                     |

---

## Acceptance Criteria

### Reachability follows capability

- [ ] With a supported reviewer configured whose runtime is present and callable in the environment, and a different supported runner driving the gate, the gate dispatches that reviewer and produces its verdict — with no block, no human escalation, and no machine-local override file present.
- [ ] A configured reviewer is not classified Unreachable solely because a different runner is driving the gate. Where its runtime is present in the environment, it is classified Reachable.
- [ ] With the same configuration on a machine where that reviewer's runtime is absent, the gate classifies it Unreachable and reports the reason as Runtime not present.
- [ ] Availability is determined fresh on each run: making a runtime available between two runs on the same pull request flips the verdict from Unreachable to Reachable with no configuration change, and removing it flips the verdict back.
- [ ] Determining availability posts no comment, changes no pull request state, and modifies no tracked file. Running the gate up to the point of dispatch on a clean checkout leaves the checkout clean.
- [ ] A reviewer that is classified Reachable, is dispatched, and then fails or errors is reported as a review failure and not as unreachable.

### The shipped default never traps

- [ ] A repository using the shipped default configuration unchanged, with no machine-local override file, reaches a dispatched reviewer and a gate verdict on every supported runner.
- [ ] The shipped default reviewer list names at least one reviewer that is reachable in any environment where a supported runner is driving the gate.
- [ ] The shipped configuration's own commentary does not describe blocking this gate on a supported runner as expected behavior, and describes the default in terms that match the guarantee above.

### The operator can tell why

- [ ] Every reviewer classified Unreachable is reported with its name, exactly one of the defined reason categories, and at least one action the operator can take that would change the outcome.
- [ ] The report distinguishes Runtime not present, Prerequisite missing, Availability check did not complete, and Not a supported reviewer from one another; it never reports one in place of another.
- [ ] The gate summary lists every configured reviewer with its verdict, including reviewers that ran.
- [ ] A reviewer removed by the machine-local override is reported as Excluded by override and produces no unreachability warning.
- [ ] A block report names which policy produced the block, and reports the machine-local override state from what was actually resolved — no override in effect, an override applied, or an override present but not resolved from this working directory — without guessing.
- [ ] No reported message attributes a reviewer's unavailability to the identity of the driving runner.

### Configuration inputs that are absent, empty, malformed, or unsupported

- [ ] With no reviewer list defined in either configuration file, the gate runs the stage-appropriate default reviewer once and records in its summary that the fallback applied.
- [ ] The reviewer the fallback runs is the driving runner's own reviewer for the pull request's stage, and it is reachable on every supported runner, so the fallback never produces a block.
- [ ] With a reviewer list that resolves to no entries at all, the gate behaves as in the previous criterion. It never reports a successful gate having dispatched no reviewer.
- [ ] A configured entry that is not a supported reviewer value is classified Unreachable with the reason Not a supported reviewer, and the offending value is named in the report.
- [ ] With a reviewer list that is defined but cannot be read as a list of values, the gate blocks, dispatches nobody, leaves the pull request draft, and names the file and the input that could not be read. It does not fall back to the default reviewer.
- [ ] With a configuration file that will not parse at all, the gate blocks and names that file, rather than proceeding as though no reviewer list were configured.
- [ ] When an unsupported value is the only configured entry, the gate blocks and names that value as the cause.
- [ ] An availability determination that cannot be completed within its bound yields Unreachable with the reason Availability check did not complete, and the gate still reaches a verdict rather than hanging. With an unresponsive reviewer in the list, the gate reaches that verdict within ten seconds of starting to resolve the list, without operator intervention.
- [ ] An availability determination that ends promptly without an answer — a prerequisite check that errors or is refused — yields the same Unreachable classification and the same Availability check did not complete reason as one that times out, and is not reported as Runtime not present or Prerequisite missing.

### Policy behavior is preserved

- [ ] With at least one reviewer unreachable, at least one reachable, and the policy that allows reduced coverage in force, the gate warns naming each unreachable reviewer and its reason, then dispatches the reachable subset.
- [ ] With the policy that forbids reduced coverage in force and any reviewer unreachable, the gate blocks, dispatches nobody, leaves the pull request draft, and names the policy as the cause.
- [ ] With no reviewer reachable, the gate blocks under either policy, leaves the pull request draft, does not convert it to ready, and escalates to a human.
- [ ] With every configured reviewer reachable, the gate posts no unreachability warning and behaves exactly as it does today.
- [ ] With no unavailable-reviewer policy configured in either file, the gate applies the shipped default under which an unreachable reviewer warns and the reachable reviewers still run.
- [ ] With the unavailable-reviewer policy set to a value that is not one of the supported policy values, the gate blocks, dispatches nobody, and names the offending value. It does not silently apply the default policy.
- [ ] With a reachable reviewer present but the policy forbidding reduced coverage, that reviewer is still classified Reachable in the report even though it is not dispatched, so the classification and the dispatch decision stay legible as separate facts.
- [ ] The gate never installs a missing runtime, provisions a missing prerequisite, or substitutes a different reviewer for an unreachable one. Where the resolved configuration names reviewers, those are the only ones dispatched; the fallback reviewer is dispatched only in the defined case where the configuration names none at all, which is not a substitution for a reviewer that could not be run.

### Surfaces agree

- [ ] The supported reviewer values, and the rule for deciding each one's availability, are stated consistently across the canonical protocol and every workflow surface that restates them.
- [ ] No workflow surface names a reviewer value that the canonical protocol does not list as supported.
- [ ] No workflow surface states or implies that availability is decided by the identity of the driving runner.
- [ ] The guidance that determines CodeRabbit's availability from runtime conditions is unchanged, and does not contradict the general rule.

---

## Out of Scope (MVP)

1. **Shipping local-override guidance instead of a working default.** The issue offers this as an alternative to changing the default configuration. Deferral rationale: the confirmed decision is to do both directions, and an override the operator has to write by hand is precisely the workaround this item exists to remove. No human confirmation requested — the decision is already recorded.

2. **Standardizing "start a second runner to satisfy the gate" as the remedy.** An issue comment proposes recording this as a standing decision. Deferral rationale: the comment scopes it explicitly to the period before this item lands, and the retrospective it came from documents it as more expensive than the override it replaced. No human confirmation requested.

3. **Changing what reviewers look for or how good their reviews are.** This feature decides whether a reviewer can be invoked, not what it says. Review prompts, verdict semantics, review-cycle caps, and the two-pass rules for implementation pull requests are untouched.

4. **The external automated reviewer stage that runs after this gate.** Its reviewer selection, its availability handling, and its loop behavior are separate and unchanged, even though the contradiction that motivated this item is visible at the boundary between the two.

5. **Changing how CodeRabbit's availability is determined.** It already reads runtime conditions rather than runner identity. It is in scope only as a surface that must not end up contradicting the general rule.

6. **Automatically installing or provisioning a missing reviewer runtime or prerequisite.** The gate reports what is missing; making it available stays the operator's decision.

7. **Substituting a different reviewer when a configured one is unreachable.** Choosing a stand-in changes review coverage without the operator asking for it. Reduced coverage under the existing policy, reported plainly, is the behavior this spec keeps.

8. **Changing the unavailable-reviewer policy's allowed values, its meanings, or its default.** Only the input to the policy changes.

9. **Changing which pipeline stages run this gate, or when.**

10. **Re-opening or re-deciding runs that were already blocked by the current behavior.** The fix applies to runs from the change forward.

---

## Open Questions

1. One workflow surface names a reviewer value — a review triggered through the hosted service rather than a local runtime — that the canonical protocol does not list as supported, and describes it as reachable from every runner. Two resolutions both satisfy the *Surfaces agree* criteria: recognize the value canonically, with its availability decided at runtime like any other; or remove the claim from the surfaces that make it. Recognizing it is the recommendation, because the dispatch mechanism it refers to is already shipped in this repository and two surfaces already document it — but the choice is the human's, and either resolution unblocks the implementation plan. If no answer arrives before planning, the recommendation applies.
