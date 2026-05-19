# Scope Drift Detection (Brief ↔ Spec, Spec ↔ Repo at Plan Time) — Spec

**Depends on**: none

---

## Overview

Workflow authors sometimes **silently narrow** what the tracker issue brief asks for when generating a feature spec, or **treat a stale enumeration** in an approved spec as the authoritative set when the repository has changed by plan-write time. Both patterns waste human review cycles, can ship incomplete work, and incorrectly rely on external PR reviewers to catch what internal gates should surface earlier.

This feature defines **mandatory coverage and verification behaviors** for the spec-writer stage (`01-generate-spec-protocol.md` and the `product-manager` / spec-writer agent guidance) and the plan-writer stage (`02-generate-implementation-plan-protocol.md` and the `tech-lead` / plan-writer agent guidance), plus optional reinforcement in internal review protocols, so drift is **detected, documented, and visible to humans before a draft PR is treated as ready**.

---

## Brief Coverage (issue #186)

| Brief objective (from tracker)                                                                                                             | Spec trace               |
| ------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------ |
| Spec-writer: extract discrete objectives / acceptance-style items from the issue brief                                                     | UC1, BR-1–BR-3, AC1, AC3 |
| Match each brief item to an AC or explicit Out of Scope entry                                                                              | UC1, BR-1, AC1           |
| If in Out of Scope, surface deferral during alignment **or** in PR description with rationale                                              | UC2, BR-3, AC2           |
| Internal spec-reviewer runs the same coverage verification                                                                                 | UC3, BR-6, AC6           |
| Plan-writer: do not treat stale spec enumerations as authoritative when intent is pattern/repo-current; run live search at plan-write time | UC4, BR-4–BR-5, AC4–AC5  |
| Internal plan reviewer checks enumeration vs verification log                                                                              | UC5, BR-6, AC7           |
| MVP excludes automated NLP extraction, retroactive rewrites, CI merge-blocking bots, full parity for non-GitHub trackers                   | Out of Scope (MVP)       |

---

## Use Cases

### Use Case 1: Spec Writer — Brief Objective Coverage Matrix Before Draft PR

**Actor**: Product Manager agent (spec writer) orchestrated by the Work Item Runner  
**Preconditions**: A GitHub-tracked feature issue exists with a body that lists multiple discrete objectives, acceptance-style bullets, or explicitly numbered requirements.

**Steps**:

1. The spec writer reads the full issue brief (title, body, and recent comments material to scope).
2. The spec writer extracts a **Brief Objective List** — each discrete item the brief treats as in-scope work (bullets, numbered lists, checklist items that are requirements rather than background narrative).
3. While drafting the spec, the writer maintains a **Coverage Matrix** mapping each brief objective to exactly one of:
   - One or more **Acceptance Criteria** in the spec that clearly satisfy that objective; or
   - An explicit **`## Out of Scope (MVP)`** entry that names the objective and states why it is deferred.
4. Before opening the draft spec PR, the writer validates that **every** brief objective has a mapping; none may be omitted or “absorbed” without a row in the matrix.
5. The draft PR body (or a dedicated section the human will read first) includes the **Coverage Matrix summary**: brief objective → AC id(s) or Out-of-Scope row reference.

**Postconditions**:

- A human reviewer can verify in under five minutes that nothing from the brief disappeared without an explicit AC or Out-of-Scope rationale.
- Silent deferral (“moved to out of scope without calling it out”) is structurally prevented by the required summary artifact.

**Information shown**:

- PR description: Coverage Matrix summary (or link to a section inside the spec that contains the full matrix).

**Actions available**:

- Human can reject a deferral before merge because the rationale is visible up front.
- Human can request scope expansion without rediscovering missing objectives via external review.

**Considerations**:

- Narrative prose in the brief that does not state a requirement is not forced into the matrix; the writer uses judgment but must not use that ambiguity to hide dropped requirements.

---

### Use Case 2: Spec Writer — Out-of-Scope Deferral Requires Human-Visible Rationale

**Actor**: Product Manager agent (spec writer)  
**Preconditions**: At least one brief objective is placed under **`## Out of Scope (MVP)`** rather than covered by an AC.

**Steps**:

1. For each such objective, the writer records a **Deferral Note** containing: the brief wording (or stable paraphrase), the rationale for deferral, and whether the human should confirm the deferral as acceptable.
2. The Deferral Note appears in **both** the spec’s Out-of-Scope section **and** the draft PR description (or a clearly labeled subsection), not only in hidden agent reasoning.
3. During the alignment conversation (per `01-generate-spec-protocol.md`), if the run is orchestrated with a pasted brief and no live human, the writer **surfaces deferrals explicitly in the PR description** as the human-facing stand-in for synchronous alignment.

**Postconditions**:

- No brief objective lands in Out of Scope without a human-visible Deferral Note tied to that objective.

**Information shown**:

- PR description lists each deferred brief objective with rationale.

**Actions available**:

- Human requests scope expansion before merge without relying on CodeRabbit or other external tools to notice the contradiction first.

**Considerations**:

- Rationales must be product- or risk-framed (“requires human judgment on NLP boundary”) rather than vague (“too hard”).

---

### Use Case 3: Internal Spec Reviewer — Verify Brief Coverage

**Actor**: Spec reviewer (internal Step 7a) or human following `01-review-spec-protocol.md`  
**Preconditions**: Draft spec PR exists for a tracked issue with a non-trivial brief.

**Steps**:

1. The reviewer reconstructs or imports the **Brief Objective List** from the linked issue.
2. The reviewer confirms the Coverage Matrix in the PR description (or spec) accounts for **every** objective.
3. If any objective is missing, the reviewer returns **NEEDS REVISION** with the specific gap.

**Postconditions**:

- Internal gate can catch the same drift pattern that previously relied on external Major findings.

**Information shown**:

- Review comment references missing objective IDs or brief bullet text.

**Actions available**:

- Work Item Runner re-runs spec fixes and Step 7a until clean.

**Considerations**:

- Reviewer does not renegotiate product scope; they enforce traceability between brief and spec.

---

### Use Case 4: Plan Writer — Live Repo Verification vs Stale Enumerations

**Actor**: Tech Lead agent (plan writer) orchestrated by the Work Item Runner  
**Preconditions**: The approved spec describes a set of files, modules, or artifacts using an **enumerated list** that may become stale (e.g., “these four spec files contain section X”), or uses language equivalent to “all files matching pattern Y.”

**Steps**:

1. When the spec’s intent is **pattern- or query-based coverage** (e.g., “every file under `docs/specs/` containing `Guiding principle`”), the plan writer runs a **live repository search** at plan-write time (e.g., `grep` / `rg` / documented equivalent) and treats that result as authoritative for the plan’s file list and counts.
2. When the spec provides a **fixed enumeration** for a reason other than pattern coverage (e.g., explicitly named integration partners), the plan documents that the list is **spec-frozen** and not re-derived — but if the brief or spec language implies completeness via a pattern, the writer must not copy the enumeration without verification.
3. The implementation plan’s **Summary** and **Documentation Updates** sections reflect the **verified** counts and paths, not the stale numbers from an older spec revision.

**Postconditions**:

- Plans do not ship with “4 files” when seven match the pattern at plan-write time unless the human explicitly chose a subset in an updated spec.

**Information shown**:

- Plan includes a short **Verification Log**: command or search used, timestamp or commit SHA of repo state checked, and resulting count/list.

**Actions available**:

- Human sees why the plan’s scope matches current repo reality.

**Considerations**:

- Verification must be reproducible by a human following the plan (exact command recorded).

---

### Use Case 5: Internal Plan Reviewer — Enumeration Consistency Check

**Actor**: Implementation plan reviewer (internal Step 7a for plans)  
**Preconditions**: Plan PR references spec ACs that imply pattern-based completeness.

**Steps**:

1. The reviewer repeats or spot-checks the Verification Log commands from the plan.
2. If counts or paths disagree with the plan body, the reviewer returns **NEEDS REVISION**.

**Postconditions**:

- Stale counts cannot pass the internal plan gate when they contradict a live search.

**Information shown**:

- Review comment cites mismatch between plan text and verification output.

**Actions available**:

- Same fix loop as other internal review failures.

**Considerations**:

- Spot-check strategy may be defined in the implementation plan stage protocol to balance thoroughness and time.

---

## Business Rules

- **BR-1 (No silent drops)**: A brief objective must never disappear between issue brief and draft spec without either (a) mapped AC(s) or (b) a named **`## Out of Scope (MVP)`** entry plus Deferral Note visible in the PR description.
- **BR-2 (Matrix before PR)**: The Coverage Matrix summary must exist **before** the draft spec PR is opened for human review automation (`ready-for-human-review` path).
- **BR-3 (Deferral visibility)**: Deferral Notes for brief objectives must not live only in agent chain-of-thought; they must appear in committed markdown (spec and/or PR body as required above).
- **BR-4 (Pattern vs freeze)**: If the spec language implies completeness via a pattern or global search, the plan writer **must** re-run the matching search at plan-write time and align Summary / Documentation Updates / smoke-test expectations to verified results.
- **BR-5 (Explicit freeze allowed)**: If the spec explicitly limits work to a named subset for a documented reason, copying that subset without search is allowed — but the plan must quote the spec section that authorizes the freeze so reviewers can see intent.
- **BR-6 (Internal review reinforcement)**: Spec and plan internal reviewers treat BR-1–BR-5 as **blocking** findings when violated, same severity class as contradictory acceptance criteria today.

---

## Acceptance Criteria

- [ ] **AC1**: For a synthetic issue brief with three numbered required objectives, a spec generated under the updated protocol includes a Coverage Matrix showing each objective mapped to an AC reference or an Out-of-Scope row before the draft PR is opened.
- [ ] **AC2**: If one objective is placed under `## Out of Scope (MVP)`, the draft PR description contains a Deferral Note for that objective with rationale in language a non-engineering stakeholder can understand.
- [ ] **AC3**: The `01-generate-spec-protocol.md` update documents the Brief Objective List, Coverage Matrix, and PR-description requirement such that a new agent session can follow it without reading this spec’s narrative.
- [ ] **AC4**: The `02-generate-implementation-plan-protocol.md` (and/or tech-lead agent guidance) documents when live repo search is mandatory vs when spec-frozen enumerations are allowed, including the Verification Log requirement.
- [ ] **AC5**: For a fixture spec that claims “all files matching pattern P” while an outdated enumeration lists fewer files, an implementation plan produced under the updated plan-writer rules uses the live search result count in the Summary and Documentation Updates sections.
- [ ] **AC6**: The internal spec review checklist in `REVIEW.md` (or companion review protocol) includes at least one explicit bullet instructing reviewers to verify brief-to-spec coverage when a tracker issue is linked.
- [ ] **AC7**: The internal plan review checklist includes at least one explicit bullet instructing reviewers to verify enumerated counts against the plan’s Verification Log when pattern-based completeness applies.

---

## Out of Scope (MVP)

- **Automated NLP extraction** from arbitrary free-text issues beyond deterministic list parsing heuristics documented in the implementation plan (agents may still use judgment; the MVP is behavioral/protocol, not a new ML service).
- **Retroactive rewriting** of historical merged specs or plans; this applies to new work and protocol updates going forward.
- **Blocking merges of downstream PRs** via CI robots that parse issue bodies — optional follow-up if a later item wants hard CI enforcement.
- **Non-GitHub trackers** beyond documenting equivalent fields in tracker-agnostic guidance (implementation may scope to GitHub Projects first).
