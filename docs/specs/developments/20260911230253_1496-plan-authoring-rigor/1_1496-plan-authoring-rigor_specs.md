# Plan-Authoring Rigor for Factual Claims in Implementation Plans — Spec

---

## Overview

An implementation plan is read as fact. The implementer executes its steps without re-deriving them, and every later reader trusts its counts, its statements about what exists in the codebase, and its descriptions of how the system behaves. The plan review gate today reasons about the plan's diff and the plan's internal consistency, so a plan can be entirely self-consistent, survive many rounds of automated review, and still be wrong about the world outside the document.

This feature gives the plan author a small set of authoring rules that make a plan's factual claims and conditional obligations verifiable, and gives the plan reviewer the matching backstop check. Each rule fires only when the plan contains a claim of the class it governs, each requires evidence recorded in the plan itself, and each resolves to an unambiguous pass or fail for a reader who re-runs the recorded evidence. The rules are derived from failure modes observed on real work items — five from a retrospective in this repository, one contributed by a downstream repository that consumes this framework. Every one of them reached a merged plan, none was caught by the review loop, and several drove wrong implementation work.

Because this repository ships as a framework template, every rule must be expressed so that any repository adopting the framework inherits it unchanged, regardless of language, stack, or test runner.

---

## Use Cases

### Use Case 1: The plan author's design depends on text produced outside the project

**Actor**: The plan author — the role writing an implementation plan.
**Preconditions**: The design under consideration reads, matches, classifies, or enumerates free text that some system outside this project produces: a third-party service, another team's tool, or a generative model.

**Steps**:

1. The author recognizes that the design's correctness depends on the wording or shape of output they do not control.
2. Before committing to a design, the author gathers real occurrences of that output and records the sampling under Rule 1.
3. The author checks whether the producer publishes a contract fixing the set of possible outputs, and cites it if one exists.
4. With no such contract, the author designs for an open set and states in the plan what the system does when an unseen output arrives.

**Postconditions**: The plan's design and its sampling record are both in the plan. A reader can see how much of the distribution was observed, and whether the design would survive an output the sample did not contain.

**Information shown**:

- The sampling record, as defined in Rule 1.
- Either the cited producer contract or the stated behavior on an unseen variant.

**Actions available**:

- Bind to a fixed set of literal outputs, when a producer contract is cited.
- Design tolerantly against the stable part of the output, otherwise.

**Considerations**:

- A large sample does not turn an observed set into a fixed one. Only the producer can fix its own output set, and only by saying so.
- The failure this case prevents is silent and late: a design that matches every captured example passes review and then fails on the first output nobody captured.

---

### Use Case 2: The plan author states how many artifacts exist in the codebase

**Actor**: The plan author.
**Preconditions**: The plan needs to say how many files, tests, call sites, or configuration entries of some kind exist, and the number affects scope, effort, or what an implementation step touches.

**Steps**:

1. The author derives the number directly, with a command or query run against the repository.
2. The author records the derivation under Rule 3, together with the population the number counts over.
3. Where the number decides which artifacts a step touches, the author keeps the enumeration the derivation produced and carries it into the step.

**Postconditions**: Every quantity in the plan is reproducible by a reader at the recorded revision, and every step whose scope is set by a quantity names the artifacts, not only the count.

**Information shown**:

- The command or query, the repository revision it was run at, and the population it counts over.
- The enumeration, wherever a quantity decides scope.

**Actions available**:

- Derive a further quantity directly with its own command.
- Combine quantities arithmetically, only under the partition condition in Rule 3.

**Considerations**:

- The failure this case prevents is a number that is arithmetically defensible and factually wrong, because the sets subtracted were not parts of one homogeneous whole. Such a number does not merely misinform: it sends the implementer to touch artifacts the change has nothing to do with.

---

### Use Case 3: The plan author receives a claim that something does or does not exist

**Actor**: The plan author, working from a delegated investigation, an earlier document, or a prior conversation.
**Preconditions**: A claim of the form "this test already exists", "there is no such helper", or "that concern is already covered" is about to enter the plan, and its support is not a reproducible search recorded in the plan.

**Steps**:

1. The author treats the claim as unverified regardless of its source.
2. The author runs a direct search against the repository, covering the places the thing could live.
3. The author records the search and its result under Rule 4, and either states the claim with that support or drops it.

**Postconditions**: Every existence claim in the plan has support a reader can reproduce.

**Information shown**:

- The search, the revision it was run at, and, for a non-existence claim, the places it covered.

**Actions available**:

- State the claim, with its recorded search.
- Drop the claim and plan without it.

**Considerations**:

- A delegated summary can be confidently wrong in a way that reads exactly like a correct one. The cost of re-running the search is a minute; the cost of a fabricated fact is an implementation step built on something that was never there.
- A plan-wide assertion that everything was checked is itself one of these claims, and the weakest kind, because it is the one no reader can reproduce.

---

### Use Case 4: The plan author changes a unit that several consumers depend on

**Actor**: The plan author.
**Preconditions**: The plan changes, deletes, or replaces a function, guard, rule, or check that has more than one consumer, and those consumers sit on an ordered path where an earlier branch can decide the outcome before a later one is reached.

**Steps**:

1. The author enumerates every consumer of the unit, deriving the enumeration under Rule 3.
2. For each consumer, the author works out the outcome after the change, including for consumers the plan does not otherwise touch.
3. The author writes every expected-behavior statement against a consumer site from that enumeration, naming the path through the chain that produces the outcome.

**Postconditions**: The plan's expectations describe what the system does, not only what the changed unit returns.

**Information shown**:

- The consumer enumeration with the outcome at each consumer.
- For each expectation, the observation point and the path that reaches it.

**Actions available**:

- Proceed with the change, with expectations anchored at real consumer sites.
- Narrow the change when a consumer outcome turns out to be unacceptable.

**Considerations**:

- The two failures this case prevents are symmetric: a branch removed whose absence lets an earlier consumer answer wrongly, and a branch left in place that quietly absorbs inputs the change was supposed to redirect. Both are invisible from the unit alone.

---

### Use Case 5: The plan author states an obligation that applies only sometimes

**Actor**: The plan author.
**Preconditions**: The plan is about to state a rule of the form "required when X", "checkable once Y", or "must hold after Z" — an obligation whose applicability depends on a condition.

**Steps**:

1. The author writes the condition precisely.
2. The author then names the scope the obligation binds to: which edges, revisions, call sites, or input classes it governs.
3. The author names where the obligation is discharged — the step or site that checks it.
4. The author re-reads the statement for words that stand in for a scope without naming one, and rewrites any it finds.

**Postconditions**: The obligation says not only when it applies, but the scope it governs and where it is discharged.

**Information shown**:

- The condition, the governed scope, and the discharge point, in the statement or in a statement it explicitly references.

**Actions available**:

- State the obligation once its scope is named.
- Split it into several scoped obligations where one scope does not fit.

**Considerations**:

- This defect is the hardest of the set to see, because the sentence reads complete. Nothing in the plan contradicts it, and the surrounding reasoning may be entirely correct. The gap only appears when a reader asks "required where?" and finds the document has no answer.
- The defect is cheap to catch at implementation review, where the escape paths become concrete, and expensive to catch at plan review, where the sentence looks finished. That asymmetry is the reason the obligation sits on the author rather than on the reviewer.

---

### Use Case 6: The plan author corrects a plan across review rounds

**Actor**: The plan author, revising a plan in response to review findings.
**Preconditions**: A plan already exists, a review round has produced findings, and a fact the plan states must change.

**Steps**:

1. The author locates the single place the fact is asserted.
2. The author edits that assertion.
3. The author confirms that no other mention of the fact restates it, and that each other mention names where it is asserted.

**Postconditions**: The corrected fact is asserted once. No second, older statement of it survives elsewhere in the plan.

**Information shown**:

- For each repeated mention, the location of the assertion it refers to.

**Actions available**:

- Edit the assertion.
- Replace a duplicate statement with a reference to the assertion.

**Considerations**:

- The failure this case prevents is a plan that grows through correction rounds until it describes the same design in several places, and then contradicts itself because a round updated one description and not the others.
- Nothing in this case concerns the plan's length. A long plan that asserts each fact once is well-formed; a short plan that asserts a fact twice is not.

---

### Use Case 7: The plan reviewer applies the backstop check

**Actor**: The plan reviewer — the automated or human reviewer at the plan review gate.
**Preconditions**: A plan pull request has reached the plan review gate and carries a per-rule outcome record.

**Steps**:

1. The reviewer reads the recorded outcome for each rule.
2. For each rule the author recorded as firing, the reviewer locates the required evidence and re-runs what can be re-run at the recorded revision.
3. For each rule recorded as not applicable, the reviewer checks the stated rationale against the plan's contents.
4. The reviewer raises a finding for every outcome that does not hold up, naming the rule, the claim, and what was missing, failed to reproduce, or contradicted by the plan's own evidence or outcome record.

**Postconditions**: Each rule has a reviewer-confirmed outcome. Findings that block the plan from becoming human-ready are distinguished from findings that do not.

**Information shown**:

- The per-rule outcome record on the plan pull request.
- The evidence in the plan document, for each firing rule.

**Actions available**:

- Confirm the outcome.
- Raise a finding with the rule name and the action that clears it.

**Considerations**:

- This check is a backstop. A rule that is only ever satisfied because a reviewer demanded it has already cost the rounds the rule exists to save.
- The reviewer checks claims against the repository, not only against the rest of the plan. Internal consistency is what the existing gate already provides, and is exactly what these failures survived.

---

## Business Rules

The rules below are the normative statement of this feature. Every other section refers to them rather than restating them.

### Rule 1 — Sampling an external output distribution

- The rule fires when the plan's design depends on the wording, shape, or presence of free text produced outside this project's control — a third-party service, another team's tool, or a generative model — including any design that matches, parses, classifies, or enumerates that text.
- Before the design is committed to, the plan records a sampling record stating: the producer; the population sampled and the window it covers; how many real occurrences were examined; how many distinct variants those occurrences yielded; and whether further occurrences had stopped yielding new variants by the end of the sample.
- For each occurrence counted in the sample, the record includes a locator sufficient for a reader who was not present when the sample was gathered to find or inspect it independently: a reference to where that occurrence was captured, or the occurrence's own text paired with a named source it was captured from — the specific message, log entry, response payload, request ID, timestamp, or similar. A record that reports only counts, with nothing that lets a reader locate or inspect any underlying occurrence, does not satisfy this rule, and embedded text with no named source has the same defect: a reader can read the string but cannot trace it to a real occurrence.
- The occurrences must be real observed outputs. Text authored to illustrate the format — documentation examples, captures curated for a ticket — is not a sample of the distribution, and a record built only from it does not satisfy this rule.
- A record of two or fewer occurrences never satisfies this rule. The population is small enough to enumerate only when it is finite and closed, and a single recorded command, query, or listing produces its complete membership, in enough detail for a reader to re-run it and reach the same list — the same reproducibility standard Rules 3 and 4 apply to counts and existence claims. Where that holds, the plan enumerates the population that way, instead of sampling it, and records the command or query used. This escape hatch is narrow: a design against a large or open output distribution does not satisfy it by listing a curated subset and calling that subset the whole population.
- The plan may bind its design to a fixed set of literal outputs only when the producer publishes a contract fixing that set and the plan cites the contract. Observation alone never establishes a fixed set, however large the sample.
- Without a cited contract, the design must be tolerant: the plan states which part of the output it relies on as stable, and what the system does when an output outside the observed variants arrives. "That cannot happen" is not an answer this rule accepts.

### Rule 2 — One normative statement per fact

- The rule fires when the plan asserts a fact — any value, count, name, decision, or behavioral statement the plan states as true. A plan with no factual assertion has no substance to review, so the rule fires on every ordinary plan; it is recorded as not applicable only in that limiting, essentially empty case.
- Each fact is asserted in exactly one place in the plan. Every other mention of that fact names where it is asserted instead of restating it.
- Two mentions that assert the same fact are a defect whether or not they agree, but only a disagreeing pair leaves the rule Unsatisfied: it is a contradiction, and the fact has no settled evidence while it stands. An agreeing pair produces a non-blocking finding rather than an Unsatisfied outcome, because the fact's evidence is neither missing nor contradicted — it is a defect in waiting, since the next correction round will update one of them.
- A correction round edits the single assertion. It never adds a second statement of the corrected fact elsewhere.
- This rule imposes no limit on a plan's length in bytes, lines, words, or pages, and no check in this feature may be failed on account of a plan's size. Size is a correlate of duplicated assertions, not the defect.

### Rule 3 — Counts of codebase artifacts

- The rule fires when the plan states a quantity of artifacts that exist in the codebase or test suite.
- Each such quantity is recorded with the exact command or query that produced it, the repository revision it was run at, and the population it counts over.
- A quantity may be obtained by arithmetic on other quantities only when the plan shows that the operand sets are subsets of one homogeneous population, are disjoint, and together exhaust it — a true partition — and that each operand was independently derived by its own recorded command. Otherwise the quantity is derived directly, by its own command.
- Membership in the population is decided by the same property the plan reasons about. A count taken over a wider population, with the surplus treated as if it shared that property, does not satisfy this rule even when the arithmetic is correct.
- A quantity that decides which artifacts an implementation step touches is accompanied by the enumeration its derivation produced. The implementer works from the enumeration; the number summarizes it and never substitutes for it.

### Rule 4 — Independent verification of existence claims

- The rule fires when the plan states that something does or does not exist in the codebase — a test, a helper, a call site, a configuration entry — or that a concern is already covered or already handled.
- Before such a claim enters the plan, it is supported by a direct search recorded in the plan: the search terms or query, the places searched, and the revision it was run at, in enough detail for a reader to re-run it and reach the same result. A claim whose only support is a delegated summary, a prior conversation, or another document does not enter the plan, because none of those give a reader anything to re-run.
- A statement that a whole class of claims was verified is itself a claim of this kind. It is supported by the per-item evidence, never by the assertion of completeness.
- For a claim that something does not exist, the record names the places searched, and those places are where the thing could plausibly live. An absent result from a search that could not have found the thing is not evidence.

### Rule 5 — Expectations at the composed call site

- The rule fires when the plan changes, deletes, or replaces a unit — a function, guard, rule, or check — that has more than one consumer, and those consumers sit on an ordered path where an earlier branch can decide the outcome.
- The plan enumerates every consumer of the unit, derived under Rule 3, and states the outcome at each consumer after the change, including consumers the plan does not otherwise touch.
- Every expected-behavior statement names the consumer site at which the behavior is observed and the path through the chain that produces it. An expectation written against the changed unit alone does not satisfy this rule, because the unit's own answer is not the system's answer.
- Removing or narrowing a branch requires stating which branch then receives the inputs that branch used to absorb, and what it does with them.

### Rule 6 — A conditional obligation names its scope

- For every rule expressed as a conditional obligation ("required when X", "checkable once Y", "must hold after Z"), the plan must name the scope the obligation binds to — which edges, revisions, call sites, or input classes it governs, and where it is discharged. A conditional stated without its scope is under-specified even when the condition itself is precise.
- A word that stands in for a scope without naming one — "then", "there", "at that point" — does not name a scope. Where such a word carries the scope, the statement is rewritten so the scope is named.
- An explanation of why the obligation cannot always be discharged is not a scope. Such an explanation makes the statement read as complete reasoning while leaving unsaid which occurrences the obligation governs.
- This obligation sits on the plan author. The reviewer check for it is a backstop, and no surface may describe plan review as the place this defect is expected to be found: the defect is cheap to catch at implementation review, expensive to catch at plan review, and cheapest of all to avoid at authoring time.

### Rules that apply across all six

- A rule fires only on its own trigger. Where a plan contains no claim of a rule's class, the rule is recorded as not applicable with a one-line rationale naming why the trigger is absent. Silence is not a rationale.
- The evidence a firing rule requires lives in the plan document, not in pull request comments, chat transcripts, or a reviewer's reply. The implementer and every later reader must find it by reading the plan.
- Every evidence record names the repository revision it was gathered at. When a later revision of the plan changes the population a record covers, the record is derived again rather than carried forward.
- Each rule is an obligation of the plan author first and a check of the plan reviewer second. Both roles apply the same rule with the same pass condition, so that an author and a reviewer reading the same plan reach the same outcome.
- No rule requires tooling that does not exist. Each check is performed by a reader holding the plan, the repository at the recorded revision, and a search tool.
- The rules are stated without reference to any language, framework, test runner, or repository-specific path, because every repository that adopts this framework inherits them.
- The rules apply to every implementation plan the workflow produces, including plans for work items that have no spec.
- Rule outcomes describe one plan revision. They are determined again on each review round and never carry forward.
- Exactly one surface carries the canonical statement of the rules. Every other surface that mentions them agrees with it, adds no rule it does not carry, and weakens none of its pass conditions. Which surface is canonical is decided in the implementation plan.

---

## Statuses / Enum Values

Each rule carries one outcome per plan revision.

| Code value       | Display label  | Description                                                                                                                                              |
| ---------------- | -------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `satisfied`      | Satisfied      | The rule fired and the plan carries the evidence it requires, in the form the rule defines. An open non-blocking finding against that evidence — for example, an agreeing duplicate under Rule 2 — does not change this outcome, because a non-blocking finding asks for consolidation rather than for evidence the rule is missing. |
| `not-applicable` | Not applicable | The plan contains no claim of the class this rule governs, and the record states a rationale naming why the trigger is absent.                            |
| `unsatisfied`    | Unsatisfied    | The rule fired and the required evidence is missing, does not reproduce at the recorded revision, or an open blocking finding stands against the claim. Also the outcome for a rule with no record at all, for a not-applicable record with no rationale, and for a record whose value is not one of these three labels. |

**Valid transitions**:

- Unsatisfied → Satisfied when a later plan revision supplies the required evidence for a claim that still fires the rule, and the outcome is determined again.
- Unsatisfied → Not applicable when a later plan revision removes the claim that made the rule fire, and the record states the rationale this outcome requires.
- Not applicable → Satisfied or Unsatisfied when a later plan revision introduces a claim of the rule's class.
- Satisfied → Unsatisfied when a later plan revision changes the population an evidence record covers and the record is not derived again.
- Satisfied → Not applicable when a later plan revision removes the claim that made the rule fire, and the record states the rationale this outcome requires.
- No outcome persists across plan revisions; every transition above is the result of determining the outcome afresh.

---

## Operational Visibility

- **Per-rule outcome record on the plan pull request**: every rule with its display label, and, for each not-applicable rule, the rationale. A reviewer can tell from this record alone which rules the author claims fired, without first reading the plan.
- **Evidence in the plan document**: the sampling records, count derivations, existence searches, consumer enumerations, and scope statements the firing rules require, each naming the revision it was gathered at. This is what survives merge and reaches the implementer.
- **Review findings**: each finding names the rule, the claim it concerns, and what was missing, failed to reproduce, or contradicted by the plan's own evidence or outcome record, so the author knows which statement to fix rather than which section to reread.
- No new notification, report, or dashboard is introduced. The records above sit on surfaces the plan stage already produces.

---

## Decision-Gate Consistency Matrix

The plan review gate is a workflow decision gate, and this feature adds inputs to it and outcomes that can hold a plan back from human review. The matrix below is the canonical statement of that changed behavior.

### Gate inputs

| Input                                                       | Where it comes from                            | Why it matters                                                                          |
| ----------------------------------------------------------- | ---------------------------------------------- | ----------------------------------------------------------------------------------------- |
| Whether the plan contains a claim of each rule's class       | Reading the plan                               | Decides whether a rule fires at all                                                      |
| The evidence a firing rule requires                          | The plan document                              | Decides Satisfied against Unsatisfied for that rule                                       |
| Whether that evidence reproduces at the recorded revision    | Re-running the recorded command or search       | A record that does not reproduce is not evidence                                          |
| The rationale attached to a not-applicable outcome           | The per-rule outcome record                    | Separates a considered non-application from an unexamined one                              |
| The per-rule outcome record itself                           | The plan pull request                          | **Added by this feature.** Its absence is an outcome, not a missing input                 |
| Whether a repeated fact is asserted or referenced            | Reading the plan                               | Decides whether a duplicate is a contradiction or a consolidation finding                  |

Every input is state the gate reads from the plan or the repository. None is inferred from the plan author's identity, the runner in use, or the number of review rounds so far. A plan's length is not an input.

### Triggers

Triggers are events. They decide when the check runs, are never read as inputs, and their absence is not a failure.

| Trigger                                                  | Why it fires                                                            |
| -------------------------------------------------------- | ------------------------------------------------------------------------- |
| A plan pull request reaches the plan review gate          | The check's normal entry point                                           |
| A review round restarts after the author's corrections    | Outcomes are determined afresh, because a revision may change any of them |

### Allowed outcomes and required next actions

| Situation                                                                                       | Outcome                | What the gate does                                            | The author's next action                                    |
| ----------------------------------------------------------------------------------------------- | ---------------------- | ------------------------------------------------------------- | ------------------------------------------------------------ |
| Every firing rule Satisfied; every non-firing rule Not applicable with a rationale               | Check passed           | Proceeds under the gate's existing rules                      | None                                                          |
| A firing rule carries no evidence                                                                | Blocking finding       | Names the rule and the claim; the plan is not human-ready     | Record the evidence, or remove the claim                      |
| A firing rule's evidence record is present but omits one or more of the elements the rule requires (for example a sampling record missing its window, or a count missing its revision) | Blocking finding       | Names the record and the missing element                      | Add the missing element, or derive the record again complete  |
| Evidence is present but does not reproduce at the recorded revision                              | Blocking finding       | Names the record that failed to reproduce                     | Derive the record again at the current revision               |
| A design binds to a fixed set of external literals with no cited producer contract               | Blocking finding       | Names the binding and the missing contract citation           | Cite the contract, or make the design tolerant                |
| A sampling record is built from curated examples, or covers two or fewer occurrences             | Blocking finding       | Names the record and why it is not a sample                   | Sample real occurrences and record the sampling              |
| A quantity is obtained by arithmetic with no shown partition                                     | Blocking finding       | Names the quantity and the operands                           | Derive it directly, or show the partition                     |
| A count's population includes members that do not share the property the plan reasons about, even when the arithmetic over it is correct | Blocking finding       | Names the count and the population defect                     | Derive the count again over only the members that share the property |
| A step's scope is set by a quantity with no enumeration                                          | Blocking finding       | Names the step and the missing enumeration                    | Carry the enumeration into the step                           |
| An existence claim is supported only by a delegated summary or another document                  | Blocking finding       | Names the claim and its inadmissible support                  | Run and record a direct search, or drop the claim             |
| A non-existence claim's recorded search does not cover the places the thing could plausibly live  | Blocking finding       | Names the claim and the missing plausible location            | Search the plausible locations and record the search, or drop the claim |
| An expectation is written against a changed unit that has consumers on an ordered path           | Blocking finding       | Names the expectation and the unenumerated consumers          | Enumerate the consumers and rewrite the expectation at a site |
| A conditional obligation names no scope or no discharge point                                    | Blocking finding       | Quotes the statement and says which of the two is missing     | Name the governed scope and where it is discharged            |
| The same fact is asserted in two places, and the statements disagree                             | Blocking finding       | Names both statements                                         | Resolve the contradiction and leave one assertion             |
| The same fact is asserted in two places, and the statements agree                                | Non-blocking finding   | Names both statements as a consolidation request              | Leave one assertion; make the other a reference               |
| A rule carries no outcome record                                                                 | Blocking finding       | Treats the rule as Unsatisfied, not as Not applicable         | Record the outcome                                            |
| A rule is recorded Not applicable with no rationale                                              | Blocking finding       | Treats the rule as Unsatisfied                                | State why the trigger is absent                               |
| A rule's outcome record carries a value that is not one of the three defined outcome labels      | Blocking finding       | Treats the rule as Unsatisfied                                | Replace the value with one of the three defined labels        |
| A rule is recorded Not applicable with a stated rationale, and the plan does contain a claim of its class that contradicts the rationale | Blocking finding       | Names the claim that contradicts the rationale                | Correct the outcome and supply the evidence                   |
| A rule is recorded Unsatisfied, and the rule's evidence in the plan is complete, reproducible, and satisfies the rule | Blocking finding       | Names the evidence that contradicts the recorded outcome      | Correct the recorded outcome to Satisfied                     |
| A rule has no triggering claim in the plan, and its recorded outcome is Satisfied or Unsatisfied  | Blocking finding       | Names the outcome that contradicts the absence of a firing claim | Change the recorded outcome to Not applicable with its rationale, or show the claim that fires the rule |
| A plan is long                                                                                   | Not an outcome         | Nothing; length is never a finding under these rules          | None                                                          |
| A firing rule's evidence sits in a pull request comment rather than the plan                     | Blocking finding       | Names the evidence that must move into the plan               | Move it into the plan document                                |

A firing rule's Satisfied outcome is compatible with an open non-blocking finding against it, such as the agreeing-duplicates row above: the finding asks for consolidation, not for evidence the rule lacks. A firing rule is never Satisfied while an open blocking finding stands against it. "Every firing rule Satisfied" in the Check passed row above is read with that meaning.

No outcome above changes the plan's contents on the author's behalf, gathers evidence for them, or converts a pull request out of draft.

### Mirror surfaces

Surfaces are named here by the role they play, not by file. Which document carries the canonical statement is an implementation-plan decision; the product requirement is that exactly one does and the rest agree with it.

| Surface                                                            | Relationship                                                      | Consistency requirement                                                                                  |
| ------------------------------------------------------------------ | ----------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| The plan-authoring guidance the plan author follows                 | States the rules as authoring obligations                         | Carries each rule with its trigger, required evidence, and pass condition                                  |
| The plan review checklist the plan reviewer follows                 | States the backstop check                                         | Uses the same rule names, outcome labels, and blocking classifications as the canonical statement          |
| The plan-writer role definitions for each supported runner          | Restate the authoring obligations for their runner                | Add no rule the canonical statement does not carry, and weaken no pass condition                           |
| The implementation plan document's own evidence area                | Holds the records the firing rules require                        | Has a place for every record a firing rule requires, so evidence is never pushed into pull request comments |
| The plan pull request quality gate log                              | Carries the per-rule outcome record                               | Lists every rule with one of the three outcome labels, and a rationale beside each Not applicable          |

### Examples

| Situation                                                                                                               | Outcome              | Reason                                                                                          |
| ----------------------------------------------------------------------------------------------------------------------- | -------------------- | -------------------------------------------------------------------------------------------------- |
| A design matches a vendor's reply against two captured examples; no other occurrences were examined                     | Blocking finding     | Two occurrences are never a sample, and nothing shows the set is fixed                            |
| The same design, with dozens of real occurrences sampled, saturation not reached, and behavior on an unseen reply stated | Check passed         | The set is open and the design says so                                                            |
| The same design, bound to a fixed list, citing the producer's published contract for that list                          | Check passed         | The producer fixed the set, not the sample                                                        |
| A plan states a test count derived by subtracting one measured group from a larger measured total                       | Blocking finding     | The operands were not shown to partition one homogeneous population                               |
| The same count, derived by its own command, with the enumeration carried into the step it scopes                        | Check passed         | Reproducible, and the step names artifacts rather than a number                                    |
| A plan counts every file in a directory to size a step that touches only the files matching a naming pattern           | Blocking finding     | The population counted is wider than the property the step reasons about                          |
| A plan says a named test "already exists", on the strength of a delegated investigation                                 | Blocking finding     | The support is a summary, not a reproducible search recorded in the plan                          |
| A plan asserts that every claim in it was checked against the real files, with no per-item records                      | Blocking finding     | A completeness assertion is the one claim a reader cannot reproduce                                |
| A plan states a helper does not exist, after searching only one of several directories where equivalent helpers are defined | Blocking finding     | The search did not cover the places the helper could plausibly live                                |
| A plan deletes a shared check and states the changed unit's new return value                                            | Blocking finding     | The unit's answer is not the system's answer where consumers sit on an ordered path                |
| The same deletion, with every consumer enumerated and its outcome stated, including untouched ones                       | Check passed         | The expectations are anchored where behavior is observable                                         |
| A plan says a replacement reference "is checkable only once the child carries a new one, and is required then"          | Blocking finding     | The condition is precise; "then" names no scope and no discharge point                            |
| The same rule, saying which edges it governs and which step discharges it                                                | Check passed         | Scope and discharge are both named                                                                |
| A plan states the same decision in three sections, all in agreement                                                      | Non-blocking finding | Agreement today; the next correction round will update one of them                                |
| The same plan after consolidation: one assertion, two references to it                                                   | Check passed         | One place to edit when the decision changes                                                       |
| A plan is long, and asserts every fact exactly once                                                                      | Check passed         | Length is not an input to this gate                                                               |

---

## Acceptance Criteria

### Group A — The rules are stated so both roles can apply them

- [ ] Each rule is stated with a named trigger, the evidence it requires, and the condition that decides pass or fail. A reader can say, for any rule, what makes it fire and what would make it fail.
- [ ] The authoring obligation and the review check for a rule share the same rule name and the same pass condition, so an author and a reviewer applying them to the same plan reach the same outcome.
- [ ] Exactly one surface carries the canonical statement of the rules. A reader comparing the mirror surfaces finds no rule present on one and absent from another, and no rule with two different pass conditions.
- [ ] Every check can be performed with the plan, the repository at the recorded revision, and a search tool. No check names a tool that would have to be built first.
- [ ] No rule text names a language, framework, test runner, or repository-specific path, so a repository adopting this framework can apply each rule unchanged.
- [ ] The rules apply to every implementation plan the workflow produces, including plans for work items that have no spec.

### Group B — Sampling an external output distribution (Rule 1)

- [ ] A plan whose design matches, parses, classifies, or enumerates text produced outside the project fails the check when it carries no sampling record.
- [ ] A sampling record passes only when it states the producer, the population and window sampled, the number of real occurrences examined, the number of distinct variants observed, whether further occurrences had stopped yielding new variants, and, for each occurrence counted, a locator sufficient for a reader to find or inspect it independently. A record missing any one of those fails.
- [ ] A plan that binds to a fixed set of literal outputs passes only when it cites a producer contract fixing that set. The same plan with a large observed sample and no cited contract fails.
- [ ] A plan with no cited contract passes only when it states the part of the output it relies on as stable and what the system does when an output outside the observed variants arrives.
- [ ] A record whose occurrences are curated examples fails, and a record of two or fewer occurrences fails.

### Group C — One normative statement per fact (Rule 2)

- [ ] Take any value, count, name, decision, or behavioral statement that appears more than once in a plan. The author's obligation is to assert it in exactly one occurrence and have every other occurrence name where it is asserted; the next criterion governs whether a plan that instead repeats the assertion leaves the rule Satisfied or Unsatisfied.
- [ ] Two occurrences that both assert the same fact are a defect whether or not they agree, and each produces a finding, but only a disagreeing pair leaves the rule's outcome Unsatisfied. Agreeing duplicates produce a non-blocking consolidation finding and leave the rule Satisfied; disagreeing ones produce a blocking contradiction finding and leave the rule Unsatisfied.
- [ ] No rule, check, outcome, or finding introduced by this feature uses a plan's length in bytes, lines, words, or pages as a pass or fail condition. A plan cannot fail anything in this feature because of its size, and a rule may name these units only to state that they are not a basis for failure.
- [ ] After a correction round, the corrected fact is asserted exactly once. A reader comparing the two revisions finds the assertion edited rather than a second statement added.

### Group D — Counts of codebase artifacts (Rule 3)

- [ ] Every quantity of codebase or test artifacts in a plan carries the command or query that produced it, the revision it was run at, and the population it counts over. A reader re-running it at that revision obtains the same number, or the plan fails.
- [ ] A quantity obtained by arithmetic passes only when the plan shows the operand sets are disjoint subsets that exhaust one homogeneous population and each was derived by its own recorded command. A subtraction of one measured count from another, without that showing, fails.
- [ ] A count whose population includes members that do not share the property the plan reasons about fails, even when the arithmetic over it is correct.
- [ ] A quantity that decides which artifacts an implementation step touches is accompanied by the enumeration its derivation produced. A step that names a number without the enumeration fails.

### Group E — Independent verification of existence claims (Rule 4)

- [ ] Every statement that a named thing does or does not exist in the codebase carries a recorded search and the revision it was run at. A reader re-running it reaches the same yes or no, or the plan fails.
- [ ] A claim whose recorded support is a delegated summary, a prior conversation, or another document, rather than a reproducible search recorded in the plan, fails.
- [ ] A statement that a class of claims was all verified passes only when the per-item evidence is present. The completeness statement alone fails.
- [ ] A non-existence claim passes only when its record names the places searched and those places are where the thing could plausibly live.

### Group F — Expectations at the composed call site (Rule 5)

- [ ] When a plan changes, deletes, or replaces a unit with more than one consumer on an ordered decision path, it carries an enumeration of every consumer with the outcome at each after the change. A consumer missing from the enumeration fails.
- [ ] Consumers the plan does not otherwise modify appear in the enumeration when they sit on the path.
- [ ] Every expected-behavior statement names an observation point that appears in the consumer enumeration, and the path that produces the outcome there. A statement naming only the changed unit fails.
- [ ] A plan that removes or narrows a branch passes only when it states which branch then receives the inputs that branch used to absorb, and what it does with them.

### Group G — A conditional obligation names its scope (Rule 6)

- [ ] A reader searching a plan for conditional obligation phrasing finds, for every occurrence, the governed scope and the discharge point named in the same statement or in a statement it explicitly references. An occurrence missing either one fails.
- [ ] A conditional whose scope is carried only by a word standing in for it fails, even when the condition is precise and the surrounding reasoning is correct.
- [ ] A statement that explains why an obligation cannot always be discharged, without naming which occurrences it governs, fails.
- [ ] The rule is stated as an obligation on the plan author, and the reviewer check is described as a backstop. No surface describes plan review as the place this defect is expected to be found.

### Group H — Outcomes and the plan review gate

- [ ] Each rule carries one of the three outcomes — Satisfied, Not applicable, Unsatisfied — and those display labels are spelled and used identically on every surface that shows an outcome.
- [ ] A rule with no recorded outcome is treated as Unsatisfied, not as Not applicable.
- [ ] A rule recorded Not applicable with no rationale is treated as Unsatisfied, and one whose rationale is contradicted by a claim in the plan produces a blocking finding naming that claim.
- [ ] The reviewer determines each rule's outcome from the plan's evidence, not from the recorded label. A rule recorded Unsatisfied whose evidence in the plan is complete, reproducible, and satisfies the rule produces a blocking finding naming that evidence, and the recorded outcome is corrected to Satisfied.
- [ ] A rule with no triggering claim in the plan, recorded Satisfied or Unsatisfied rather than Not applicable, produces a blocking finding naming the outcome that contradicts the absent trigger.
- [ ] A rule whose outcome record carries a value other than Satisfied, Not applicable, or Unsatisfied is treated as Unsatisfied.
- [ ] The plan pull request quality gate log lists every rule with its outcome, and a rationale beside each Not applicable.
- [ ] Outcomes are determined afresh on every review round. An outcome recorded against an earlier plan revision never satisfies a later one.
- [ ] Every outcome that keeps a plan from becoming human-ready is enumerated together with the action that clears it. A reader can determine, for any outcome, whether it blocks and what to do about it.
- [ ] The evidence a firing rule requires is in the plan document. A plan whose only evidence for a firing rule is in a pull request comment or a chat transcript fails.
- [ ] Every review finding this feature introduces names the rule, the claim, and what was missing, failed to reproduce, or contradicted by the plan's own evidence or outcome record.

---

## Out of Scope (MVP)

- **Automated enforcement.** No script, linter, or bot that detects violations of these rules is built here. The rules must be checkable by a reader without new tooling; automating them is separate work that becomes possible once the rules are stable.
- **Any plan size ceiling.** No limit on a plan's bytes, lines, words, or pages is introduced, now or as a fallback. This is a deliberate rejection rather than a deferral — see the deferral notes below.
- **Retrofitting merged plans.** Plans already merged are not re-audited against these rules. The rules apply to plans authored after adoption.
- **Per-repository opt-out or per-rule configuration.** The rules ship as part of the plan stage, like the plan stage's other guardrails. Whether a downstream repository may disable individual rules is left for a later decision, once there is evidence about their cost in practice.
- **Extension to other artifacts.** Specs, code reviews, retrospectives, and release notes are not brought under these rules, even though some of the same failure modes are plausible there.
- **Automated collection of external output samples.** Rule 1 requires a sample and a record of it; harvesting, storing, or refreshing such samples automatically is not part of this feature.
- **Changing the review gate's existing severity vocabulary.** This feature classifies its own findings using the classifications the gate already has; it does not add new ones or alter the meaning of existing ones.

### Deferral notes

- **A plan size ceiling** — from brief objective 2, "adopt a testable plan-quality rule targeting size/assertion density … rather than leaving size unconstrained". The objective itself is covered by Rule 2, which is the testable rule the brief asked for. The byte ceiling the brief named as the alternative it did not want is deliberately excluded: the observed correlation between plan size and stale-prose findings is explained by duplicated assertions, and a ceiling would penalize well-formed long plans while permitting short self-contradicting ones. No human confirmation is requested; this follows the brief's own stated preference.
- **Per-repository opt-out** — not raised in the brief. Recorded here because this repository ships as a framework template, so every downstream repository inherits these rules whether or not they fit its plans. Human confirmation is requested if downstream friction appears; nothing in this feature forecloses adding configuration later.

---

## Brief Coverage Matrix

Acceptance criteria are referenced by group, because group names are stable across review rounds while criterion numbering is not.

| Objective from issue #1496                                                                                                             | Disposition                                                     |
| ---------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------- |
| Sub-requirement 1 — sample a representative distribution of third-party free-text output before binding to a fixed grammar or template   | Covered. Rule 1; Use Case 1; Groups A and B                       |
| Sub-requirement 2 — adopt a testable plan-quality rule targeting size or assertion density, rather than leaving size unconstrained        | Covered. Rule 2; Use Case 6; Group C. The byte-ceiling alternative the brief declined is recorded in Out of Scope with a deferral note |
| Sub-requirement 3 — every codebase or test-suite count states its exact derivation command, and no count is obtained by subtraction unless both subsets are independently verified as a true partition of a homogeneous set | Covered. Rule 3; Use Case 2; Group D                              |
| Sub-requirement 4 — independently re-verify any delegated claim that something does or does not exist in the codebase, with a direct search, before it enters a plan | Covered. Rule 4; Use Case 3; Group E                              |
| Sub-requirement 5 — when a plan changes a unit with multiple call sites forming a decision chain, write verification expectations against the real call site in the composed chain, not the unit in isolation | Covered. Rule 5; Use Case 4; Group F                              |
| Sub-requirement 6 — every conditional obligation names the scope it binds to and where it is discharged (confirmed decision, contributed by a downstream repository's retrospective) | Covered. Rule 6; Use Case 5; Group G                              |
| The rules are expressed as authoring rules for the plan-writing role, with the review checklist as the place the check is applied        | Covered. The cross-cutting business rules; Use Case 7; Groups A and H |
| The observation that the scope-naming defect is cheap to catch at implementation review and expensive at plan review, which argues for an authoring rule rather than a review rule | Covered. Rule 6's final clause; Group G's last criterion           |
| The underlying diagnosis — the review loop reasons about the diff, not about whether the plan's factual claims are true                  | Covered. Overview; Use Case 7's considerations; the gate inputs, which are read from the repository and not only from the plan |

No objective from the brief is deferred to Out of Scope. The out-of-scope entries are boundaries around covered objectives or decisions the brief did not raise.
