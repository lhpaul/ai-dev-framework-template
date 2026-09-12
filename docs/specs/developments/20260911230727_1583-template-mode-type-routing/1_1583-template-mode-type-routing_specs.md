# Framework-Mode Work-Item Classification — Spec

---

## Overview

The work-item classification field on the project board carries two unrelated
meanings at the same time. Three of its values — Feature, Bug, and Refactor —
say which pipeline an item takes. The fourth, Workflow, says nothing about the
pipeline; it says the item is AI-development-framework, process, or tooling work
rather than product work. In a repository that builds a product, those two
meanings coexist quietly because framework work is rare. In this repository
every item is framework work, so the second meaning wins on every item and the
routing meaning disappears.

That is not agent drift. The workflow's own guidance tells agents to classify
framework, process, and tooling work as Workflow, and every item here qualifies,
so agents follow the documented rule correctly and produce a board that cannot
be routed. Measured on 2026-08-23, 57 of 63 open Backlog items were classified
Workflow — and Workflow is the one class for which the routing rules give no
deterministic next action, only "infer the path, or stop and ask a human".

This feature makes the classification field mean one thing in a repository that
declares itself the framework template. In that repository — **framework mode** —
Workflow is not a valid class, and every item is a Feature, a Bug, or a Refactor
*of the framework itself*. The declaration that turns this on already exists and
already means "this repository is the framework"; no new switch is introduced.
Repositories that do not make that declaration are **consumer repositories**, and
nothing about them changes: they keep all four classes, keep using Workflow for
framework work, and observe no difference in any command, message, or routing
decision.

---

## Use Cases

### Use Case 1: An agent files a backlog item in framework mode

**Actor**: A backlog agent — the agent or operator creating a work item through
the workflow's backlog-creation command.
**Preconditions**: The repository is in framework mode. The agent has decided the
item is framework, process, or tooling work and is about to classify it Workflow.

**Steps**:

1. The agent runs the backlog-creation command and asks for the Workflow class.
2. The command recognizes that this repository is in framework mode.
3. The command refuses the request and explains why.

**Postconditions**: No work item exists. Nothing was created on the tracker,
nothing was added to the board, and no field was set. The agent can immediately
re-run the same request with a valid class.

**Information shown**:

- That Workflow is not a valid class in a framework-mode repository.
- The classes that are valid here — Feature, Bug, and Refactor.
- That in this repository those words describe the framework itself, so the item
  should be classified by the pipeline it needs rather than by the fact that it
  is framework work.

**Actions available**:

- Re-run the request with Feature, Bug, or Refactor.
- Nothing else is required. There is no confirmation prompt, no override flag,
  and no way to force the rejected class through this path.

**Considerations**:

- The refusal happens before the item is created, not after. A half-created item
  that the agent then has to clean up would be worse than the problem being
  fixed.
- The refusal is not advice the agent can read and ignore; the command does not
  proceed.
- An item filed without any class is out of this feature's scope to reject — the
  absence of a class is a pre-existing gap, not something this rule introduces.

---

### Use Case 2: An agent files a backlog item in a consumer repository

**Actor**: A backlog agent working in a repository that consumes this framework
rather than being it.
**Preconditions**: The repository does not declare itself the framework template
— the declaration is absent, or present and false. The agent is filing framework,
process, or tooling work and classifies it Workflow.

**Steps**:

1. The agent runs the backlog-creation command and asks for the Workflow class.
2. The command finds no framework-mode declaration.
3. The command creates the item and classifies it Workflow, exactly as it does
   today.

**Postconditions**: The item exists with the Workflow class. The consumer
repository's board, routing, release checks, and retrospectives behave exactly as
they did before this feature.

**Information shown**:

- The same output the command produces today. No new warning, note, or nudge
  about framework mode appears.

**Considerations**:

- This is the default. A repository that says nothing about being a template is a
  consumer repository.
- A declaration whose value is not recognizable as an affirmative is also a
  consumer repository. Ambiguity resolves toward the behavior that changes
  nothing.
- The reserved meaning of Workflow for consumer repositories is unchanged and
  still recommended there: product work is Feature or Bug, framework work is
  Workflow.

---

### Use Case 3: The Work Item Runner meets a misclassified Backlog item

**Actor**: The Work Item Runner, and the operator who reads the run's report.
**Preconditions**: The repository is in framework mode. A Backlog item carries the
Workflow class — typically one filed before this rule existed. The runner has been
asked to advance it.

**Steps**:

1. The runner reads the item's class to decide which pipeline it takes.
2. It finds the Workflow class, which framework mode does not accept.
3. It treats the item as misclassified and stops, rather than inferring a path
   from the brief.

**Postconditions**: The item is untouched — its class, its board status, and its
branches and pull requests are exactly as they were. No pipeline was started.

**Information shown**:

- The item, named.
- That its class is not valid in a framework-mode repository, and that this is a
  classification problem rather than a problem with the brief.
- The valid classes, and that re-classifying the item is what unblocks it.

**Actions available**:

- Re-classify the item on the board as Feature, Bug, or Refactor, then re-run it.

**Considerations**:

- Stopping is the point. Before this feature the runner was allowed to guess the
  path from the brief and only stop when the brief was unclear; a guess that
  lands on the wrong pipeline is more expensive to undo than a stop.
- Until the pre-existing items are re-classified, this stop is expected to fire
  on most of the open Backlog. That is a visible, per-item, immediately
  actionable cost, and it is the trade this feature accepts in exchange for
  restoring the routing meaning. The bulk re-classification is separate work.
- Items already past Backlog are unaffected. Their pipeline was chosen when they
  started, and re-deciding it mid-flight would be a regression, so the
  misclassification stop applies only where classification is the routing input.

---

### Use Case 4: A release or retrospective run looks for open framework items

**Actor**: The agent running the release-preparation flow, and the agent running
the retrospective flow.
**Preconditions**: The repository is in framework mode. Both flows include a step
that asks the tracker for the open framework-tooling items, so that known script
bugs can be reviewed before a release and so that retrospective findings can be
matched against work that is already filed.

**Steps**:

1. The flow asks for the open framework items.
2. Because the repository is in framework mode — where every item is framework
   work — the answer is every open item on the board.
3. The flow reviews that list as it does today.

**Postconditions**: The release check and the retrospective de-duplication both
see a complete list. Neither reports "no open framework items" merely because the
repository stopped using the Workflow class.

**Information shown**:

- The open items, in the same shape and detail as today.

**Considerations**:

- This is the part of the change that must not be skipped. If the repository stops
  using Workflow and this lookup keeps filtering on it, both flows quietly return
  nothing — a release stops catching known open script bugs, and every
  retrospective finding looks new. A visible problem would be traded for a silent
  one.
- In a consumer repository the lookup keeps its current meaning and still filters
  to the Workflow class, because there the distinction between framework work and
  product work is real.
- Returning nothing remains a legitimate answer when the board genuinely has no
  open items. The requirement is that emptiness reflects the board, not the
  classification rule.

---

### Use Case 5: An agent consults the classification guidance

**Actor**: Any workflow agent deciding how to classify an item, reading the
workflow's guidance before acting.
**Preconditions**: The agent is working in a framework-mode repository and is
about to choose a class.

**Steps**:

1. The agent reads the classification guidance on whichever surface it reached
   first — the backlog-creation protocol, the repository's agent guidance file,
   the tracker integration guide, or the routing protocol.
2. Every one of those surfaces states the framework-mode rule.
3. The agent chooses Feature, Bug, or Refactor.

**Postconditions**: The agent's choice matches what the creation command accepts.
The agent was never instructed toward a class the same repository refuses.

**Information shown**:

- The framework-mode rule: in a repository that declares itself the framework
  template, Workflow is not a valid class and every item is a Feature, Bug, or
  Refactor of the framework.
- The consumer-repository rule, unchanged and still stated, so a reader of the
  shared guidance is not left thinking the framework-mode rule applies to them.

**Considerations**:

- The original problem was created by correct agents following correct-looking
  guidance. Leaving any surface stating the old rule reproduces it.
- Guidance that is mirrored across runner-specific copies has to agree with the
  canonical copy, or the rule an agent sees depends on which runner it is.
- Surfaces that instruct an agent to *set* the Workflow class on an item it just
  created count as guidance for this purpose, not just surfaces that describe the
  field.

---

## Business Rules

- A repository is in **framework mode** when it declares in its workflow
  configuration that it is the framework template. This is the same existing
  declaration that already gates the template-fit check and the template-specific
  setup step; no new configuration is introduced.
- A repository is a **consumer repository** when that declaration is absent,
  false, or not recognizable as an affirmative. Consumer behavior is the default
  and is unchanged by this feature in every respect.
- In framework mode the valid classes are Feature, Bug, and Refactor, and they
  describe the framework itself: a defect in the framework is a Bug, a new
  framework capability is a Feature, and restructuring the framework without
  changing its behavior is a Refactor.
- In framework mode the Workflow class is not valid. It carries no routing
  meaning there, because the distinction it draws — framework work versus product
  work — is true of every item.
- The Workflow option is not removed from the board's class field. It stays, so
  historical items keep a readable classification and consumer boards that share
  the field definition are untouched. The rule is enforced when a class is
  written, not by deleting the option.
- Rejection is complete: when the creation command refuses a class, no item is
  created, no board entry is added, and no field is set.
- A rejection message names the invalid class, names the valid classes, and is
  enough on its own for the agent to retry correctly. It is never a bare failure.
- In framework mode a Backlog item carrying the Workflow class is misclassified.
  Routing stops and asks for re-classification instead of inferring a pipeline
  from the brief.
- The routing stop applies to items whose pipeline has not yet been chosen. An
  item already past Backlog keeps the pipeline it started on.
- The lookup for open framework items means every open board item in framework
  mode, and keeps its class-filtered meaning in a consumer repository. It must
  never report an empty result as a consequence of the classification rule
  itself.
- Every workflow surface that *explains* how to classify an item states the
  framework-mode rule and the consumer rule consistently, so a reader in either
  mode is not misled by the rule for the other.
- Every workflow surface that *instructs* an agent to set a class on an item it
  just created must never direct a framework-mode repository toward a class that
  same repository refuses. Such a surface is not required to restate both rules;
  it is required not to produce the refused class.
- This feature changes no routing behavior for Feature, Bug, or Refactor items,
  in either mode.

---

## Statuses / Enum Values

Work-item classification values, and what each means in each mode:

| Code value | Display label | Meaning in a consumer repository | Meaning in framework mode |
| ---------- | ------------- | -------------------------------- | ------------------------- |
| `Feature`  | Feature       | Product capability; full pipeline — spec, plan, implementation | Framework capability; same full pipeline |
| `Bug`      | Bug           | Product defect; fast-track fix path when the scope check allows | Framework defect; same fast-track path |
| `Refactor` | Refactor      | Restructuring without behavior change; plan-only path | Framework restructuring; same plan-only path |
| `Workflow` | Workflow      | AI-development-framework, process, or tooling work; pipeline inferred from the brief | Not valid — refused on creation, and treated as misclassified when routing an item still awaiting a pipeline |

**Valid transitions**:

- Any class → any other class, by an operator editing the board. This feature adds
  no transition restrictions; it constrains only which values may be written
  through the workflow's creation command and which values route.
- Workflow → Feature, Bug, or Refactor is the re-classification an operator
  performs to unblock a misclassified framework-mode item.

---

## Operational Visibility

- **Creation refusals**: reported directly to whoever ran the creation command, at
  the moment of the attempt, naming the invalid class and the valid ones. No item
  is created, so nothing is left on the tracker to explain later.
- **Routing stops**: reported in the run's own report, naming the item, the reason
  (classification not valid in framework mode), and the re-classification that
  unblocks it.
- **No new audit trail**: this feature records no events, writes no logs, and
  posts no tracker comments beyond the two reports above. It has no background or
  scheduled behavior.
- **No misclassification scan**: nothing in this feature sweeps the board looking
  for misclassified items; a problem surfaces only when an item is created or
  routed. The framework-item lookup does read the open items on the board, but
  that is an existing read serving the release and retrospective flows, not a new
  scan for misclassification.

---

## Decision-Gate Consistency Matrix

This feature modifies a workflow decision gate — the rule that turns a Backlog
item's class into a pipeline — so the gate is enumerated here.

### Gate inputs

| Input | Values | Source |
| ----- | ------ | ------ |
| Repository mode | Framework mode / consumer repository | The repository's own workflow configuration declaration that it is the framework template |
| Item classification | Feature / Bug / Refactor / Workflow / unset | The project board's classification field for the item |
| Item stage | Still awaiting a pipeline (Backlog) / already on a pipeline | The item's board status, reconciled against work already completed for it, exactly as routing reconciles a stale status today |

### Triggers

| Trigger | Gate evaluated |
| ------- | -------------- |
| An agent asks the creation command to file an item with a class | Creation-time class validity |
| A runner is asked to advance an item, or a portfolio scan proposes a Backlog item to start | Routing classification |
| A release or retrospective flow asks for open framework items | Framework-item lookup meaning |

### Allowed outcomes and required next actions

Routing outcomes. Every row except the last describes an item still awaiting a
pipeline; an item already on a pipeline is not re-evaluated by this gate in
either mode.

| Mode | Classification | Outcome | Required next action |
| ---- | -------------- | ------- | -------------------- |
| Framework | Feature | Route: full pipeline | Unchanged — start the spec stage |
| Framework | Bug | Route: fast track, subject to the existing scope check | Unchanged — run the existing gate |
| Framework | Refactor | Route: plan-only | Unchanged — start the plan stage |
| Framework | Workflow | Misclassified | Stop; report the item and ask for re-classification. Do not infer a pipeline |
| Framework | Unset | Unchanged from today | Unchanged — this feature does not add behavior for an absent class |
| Consumer | Feature / Bug / Refactor | Route as today | Unchanged |
| Consumer | Workflow | Route as today — infer the path from the brief, stop if unclear | Unchanged |
| Consumer | Unset | Unchanged from today | Unchanged |
| Either | Any class, item already on a pipeline | Not re-evaluated | Unchanged — the item continues on the pipeline it started; re-deciding it mid-flight is out of scope |

Creation-time outcomes:

| Mode | Requested class | Outcome | Required next action |
| ---- | --------------- | ------- | -------------------- |
| Framework | Workflow | Refused before creation, with the valid classes named | Re-run the request with Feature, Bug, or Refactor |
| Framework | Feature / Bug / Refactor | Created as today | Unchanged |
| Framework | Unset — no class requested | Created as today | Unchanged — this feature does not add behavior for an absent class |
| Consumer | Any class, or none | Created as today | Unchanged |

Framework-item lookup outcomes:

| Mode | Board contents | Outcome | Required next action |
| ---- | -------------- | ------- | -------------------- |
| Framework | At least one open item | Every open board item, whatever its class | Unchanged — the flow reviews the list as today |
| Framework | No open items | Empty, and empty only because the board is empty | Unchanged — an empty board is a legitimate answer |
| Consumer | Any | Only items classified Workflow, as today | Unchanged |

### Mirror surfaces

| Surface | Required alignment |
| ------- | ------------------ |
| Backlog-creation protocol (classification step and its inference table) | States the framework-mode rule; its worked examples do not show a class that framework mode refuses |
| Repository agent-guidance file, and its per-runner mirrors | States the framework-mode rule in the same words as the canonical copy |
| Tracker integration guide (classification field table and the Workflow entry) | States that the Workflow option remains on the board but is not valid in framework mode |
| Every Backlog routing table that turns a class into a pipeline — the single-item routing table and the portfolio batch-proposal table alike | The framework-mode Workflow row reads as misclassified-and-stop, not infer-the-path, in each of them |
| Retrospective flows that create an item and set its class | Do not direct a framework-mode repository to set a class it refuses |
| Release and retrospective framework-item lookups | Describe the lookup's framework-mode meaning as every open board item |

### Examples

- A framework-mode repository files "reviewer loop times out on large diffs" and
  asks for Workflow. The command refuses and names Feature, Bug, and Refactor.
  The agent re-files it as a Bug, and it routes exactly as any Bug does today —
  to the fast-track path when the existing scope check allows it.
- A framework-mode repository is asked to advance an existing Backlog item that
  was filed months ago as Workflow. The runner stops, names the item, and asks for
  re-classification. Nothing about the item changes until an operator acts.
- A consumer repository files "the retrospective script drops the last finding"
  and asks for Workflow. The item is created as Workflow, and routing infers its
  path from the brief exactly as it does today.
- A framework-mode release run asks for open framework items and receives every
  open board item, so a known open script bug affecting the release is still
  caught.
- A framework-mode item classified Workflow is already past Backlog — its spec is
  merged and implementation is under way. The runner continues that pipeline. The
  misclassification stop does not fire, because the pipeline was already chosen.

---

## Issue-objective Traceability

Every discrete requirement in the brief maps to an acceptance-criteria group
(named in italics) or to an explicit out-of-scope entry. Nothing in the brief is
silently dropped.

| Brief objective | Where it comes from in the brief | Disposition |
| --------------- | -------------------------------- | ----------- |
| Creation command refuses the Workflow class in framework mode, with a clear actionable message, and creates no item | Acceptance criterion 1; enforcement point 1 | *Creating an item in framework mode* |
| The same invocation still succeeds when the repository is not the framework template | Acceptance criterion 2 | *Consumer repositories are unchanged* |
| Framework-item lookup means all open board items in framework mode, and keeps its filtered behavior otherwise | Acceptance criterion 3; required companion change | *Open framework items stay discoverable* |
| Backlog-creation protocol, routing protocol, agent-guidance file, and tracker integration guide state the rule consistently | Acceptance criterion 4; enforcement point 2 | *Guidance surfaces agree* |
| Routing no longer infers a path for a framework-mode Workflow item | Acceptance criterion 5; enforcement point 3 | *Routing stops instead of guessing* |
| Reuse the existing framework-template declaration as the gate rather than adding a switch | Proposed approach | *Consumer repositories are unchanged*; Business Rules |
| Keep the Workflow option on the board's class field | Out of scope, first bullet | Out of Scope, item 1; Business Rules |
| No board-scanning CI check | Out of scope, second bullet | Out of Scope, item 2 |
| Do not backfill the existing misclassified items | Out of scope, third bullet | Out of Scope, item 3 |
| Splitting the two meanings into a separate area field or label | Alternative considered and rejected | Out of Scope, item 4 — recorded as rejected, not revived |

---

## Relationship to Other Work Items

- The bulk re-classification of the already-filed misclassified items (#1584)
  depends on this landing first, so that re-typed items are not pulled back
  toward the old class by guidance that still recommends it. This spec does not
  perform that re-classification.
- The items sharing this batch (#1462, #1496, #1515, #1529, #1561) were assessed
  as orthogonal to this one. Nothing here orders against them.

---

## Acceptance Criteria

### Creating an item in framework mode

- [ ] In a repository that declares itself the framework template, asking the
      backlog-creation command to file an item with the Workflow class fails, and
      no item is created on the tracker or added to the board.
- [ ] The failure message names Workflow as invalid here and names Feature, Bug,
      and Refactor as the valid classes, so the agent can retry without consulting
      another document.
- [ ] Re-running the same request with Feature, Bug, or Refactor succeeds and
      produces an item classified as asked.
- [ ] There is no flag, environment variable, or confirmation prompt through which
      the creation command will accept the Workflow class in framework mode.

### Consumer repositories are unchanged

- [ ] In a repository whose framework-template declaration is absent, the same
      request with the Workflow class succeeds and the item is classified
      Workflow.
- [ ] The same holds when the declaration is present and false, and when its value
      is not recognizable as an affirmative.
- [ ] A consumer repository's creation output for every class is identical to its
      output before this feature — no added warning or note about framework mode.
- [ ] A consumer repository's Backlog routing for every class, including Workflow,
      is identical to its behavior before this feature.

### Open framework items stay discoverable

- [ ] In framework mode, the lookup used by the release flow and the retrospective
      flow returns every open board item.
- [ ] In a consumer repository, the same lookup returns only items classified
      Workflow, as it does today.
- [ ] With at least one open item on the board, the framework-mode lookup never
      returns an empty result on the grounds that no item carries the Workflow
      class.

### Routing stops instead of guessing

- [ ] In framework mode, asking a runner to advance a Backlog item classified
      Workflow stops the run and reports the item as misclassified.
- [ ] The stop names the item, states that its class is not valid in a
      framework-mode repository, and names the re-classification that unblocks it.
- [ ] The run starts no pipeline for that item and changes neither its class nor
      its board status.
- [ ] Re-classifying the item as Feature, Bug, or Refactor and re-running it
      routes the item exactly as that class routes today, with no additional
      step introduced by this feature — a re-classified Bug still passes
      through the existing scope check before it reaches the fast-track path.
- [ ] In framework mode, an item classified Workflow whose pipeline has already
      started continues on that pipeline — the misclassification stop does not
      fire, and the run proceeds exactly as it did before this feature.

### Guidance surfaces agree

- [ ] The backlog-creation protocol's classification step and its class-inference
      table state the framework-mode rule, and no worked example in that protocol
      shows a class framework mode refuses.
- [ ] The repository's agent-guidance file states the framework-mode rule, and
      every per-runner mirror of that text says the same thing.
- [ ] The tracker integration guide states that the Workflow option remains on the
      board but is not valid in framework mode.
- [ ] Every Backlog routing table that turns a class into a pipeline — the
      single-item routing table and the portfolio batch-proposal table alike —
      describes a framework-mode Workflow item as misclassified rather than as
      an item whose path is inferred.
- [ ] The release-preparation flow and the retrospective flow each describe the
      open-framework-item lookup's framework-mode meaning as every open board
      item, so a reader of either flow is not left expecting a class-filtered
      result there.
- [ ] No workflow surface directs an agent in a framework-mode repository to set
      the Workflow class on an item, including the retrospective flows that create
      an item and classify it.
- [ ] Reading any one of these surfaces alone is enough to classify an item in a
      way the creation command accepts.

---

## Out of Scope (MVP)

1. **Removing the Workflow option from the board's classification field.** It
   stays. Removing it would orphan the classification of historical items, and
   consumer boards that share the field definition may legitimately still want
   it. The rule is enforced when a class is written instead.
2. **A scheduled or per-pull-request check that scans the board for misclassified
   items.** This repository has repeatedly hit tracker API rate limits during
   batch runs, and a repeated scan of a several-hundred-item board is a flaky
   guard for a low-frequency problem. Refusing the class at creation time and
   stopping at routing time is sufficient.
3. **Re-classifying the items already filed with the Workflow class.** Tracked
   separately as #1584, which depends on this landing first so re-typed items are
   not pulled back by guidance that still recommends the old class.
   **Accepted consequence**: until #1584 lands, the routing stop described above
   is expected to fire on most of the open Backlog — on the order of the 57
   Workflow-classed items measured on 2026-08-23. The cost is visible, per item,
   and cleared by re-classifying that item on the board before re-running it; no
   item is lost or altered. This spec accepts that cost in exchange for restoring
   the routing meaning, and it applies only to items still in Backlog.
4. **Splitting the two meanings into separate fields.** Keeping the class field
   routing-only and moving the framework-versus-product distinction to its own
   field or label is the more principled model, and it was considered and
   rejected in the brief: it is a breaking board change for every consumer that
   already has the Workflow option, and it needs a migration and a
   template-sync story to solve a problem the existing framework-template
   declaration solves cheaply.
5. **Changing how consumer repositories classify framework work.** They keep all
   four classes and keep using Workflow for framework, process, and tooling work.
6. **Changing the pipelines themselves.** Feature, Bug, and Refactor route exactly
   as they do today, in both modes.
7. **Rejecting or defaulting an item filed with no class at all.** The absent-class
   case is a pre-existing gap that this feature neither worsens nor fixes.
