# Align Cursor Workflow Surfaces for Client Rollout — Spec

---

## Overview

This framework is tool-agnostic: the canonical workflow lives in `docs/` and each
AI assistant (Claude Code, Cursor, Codex) gets thin wrappers that point at those
protocols. Downstream client teams that adopt the framework Cursor-first must be
able to reach every workflow stage through native Cursor entrypoints (rules,
subagents, slash commands) without being told to use a Claude- or Codex-only
name. Today the Cursor command surface is missing two entrypoints that the
project's own guidance tables advertise, and the framework has never recorded an
explicit decision about whether a Cursor-native skills mirror is needed. This
work closes those parity and guidance gaps so a Cursor user sees a complete,
self-consistent, canonically-anchored workflow surface.

This is a change to an existing capability (the Cursor wrapper surface), not a
new product capability. It depends on no other in-flight work and is the first
substantive child of epic #988 (Cursor Bugbot integration); all changes land on
the `develop-cursor-bugbot-integration` integration branch.

---

## Use Cases

### Use Case 1: Cursor user discovers and invokes a workflow stage

**Actor**: A developer on a downstream team using Cursor as their primary AI
assistant.
**Preconditions**: The project was created from this template; Cursor has loaded
the project's rules, subagents, and commands.

**Steps**:

1. The developer opens the project guidance (the AGENTS-format guidance file and
   the README) to find which workflow stage they need.
2. For each workflow stage the guidance advertises a Cursor entrypoint, the
   developer invokes that entrypoint by its documented name (a slash command or a
   named subagent).
3. The invoked entrypoint runs the corresponding stage by following the canonical
   protocol it references.

**Postconditions**: Every workflow stage the guidance advertises for Cursor is
reachable by its documented name, and the entrypoint runs the canonical protocol
rather than redefining behavior.

**Information shown**:

- A guidance table that lists, per workflow stage, the Cursor entrypoint to use.
- For each Cursor entrypoint, a short description and a pointer to the canonical
  protocol or document it follows.

**Actions available**:

- Invoke any advertised Cursor entrypoint for the stage the developer is working
  on.

**Considerations**:

- If guidance advertises a Cursor entrypoint that does not exist, the developer is
  blocked or forced to fall back to a Claude/Codex-only name. Every advertised
  Cursor entrypoint must therefore resolve to a real Cursor surface.
- If an entrypoint duplicates protocol behavior instead of pointing at it, the
  Cursor surface can drift from the canonical workflow. Wrappers must stay thin.

### Use Case 2: Maintainer confirms Cursor-surface guidance is accurate and current

**Actor**: A framework maintainer (or a downstream lead) verifying the project is
ready for a Cursor-first rollout.
**Preconditions**: The Cursor surfaces, README, and AGENTS-format guidance exist
in the repository.

**Steps**:

1. The maintainer reviews the README and AGENTS-format guidance sections that
   describe Cursor rules, subagents, commands, and skills.
2. The maintainer cross-checks each advertised Cursor entrypoint against the
   actual Cursor surfaces present in the repository.
3. The maintainer confirms the guidance reflects the current Cursor conventions
   for project rules, subagents, commands, and skills.
4. The maintainer reads the recorded decision about whether a Cursor-native
   skills mirror is needed.

**Postconditions**: Advertised Cursor entrypoints and the actual Cursor surfaces
agree; the guidance reflects current Cursor conventions; the skills-mirror
decision is recorded with a rationale.

**Information shown**:

- The list of Cursor rules, subagents, commands, and (if any) skills the project
  ships.
- A recorded decision and rationale on the Cursor skills mirror.

**Actions available**:

- Approve the Cursor surface as rollout-ready, or flag a remaining mismatch.

**Considerations**:

- The decision about a Cursor skills mirror must be explicit and stated in the
  spec and the guidance, not left implicit by the absence of a directory.

---

## Business Rules

- Every workflow stage that the README or the AGENTS-format guidance advertises as
  having a Cursor entrypoint must resolve to a real, invokable Cursor surface
  (a slash command, a named subagent, or a rule) by its advertised name.
- Conversely, every Cursor entrypoint that ships in the repository must be
  represented in the guidance tables, so the guidance and the surfaces stay in
  one-to-one agreement.
- A Cursor user must be able to reach each advertised stage using a Cursor-native
  name; the guidance must not require a Cursor user to invoke a Claude- or
  Codex-only name to complete a stage.
- Every new or changed Cursor surface must reference the canonical protocol or
  document for its stage and must not duplicate or restate the protocol's
  behavior beyond a short orientation summary (the thin-wrapper rule).
- The decision on whether to ship a Cursor-native skills mirror must be recorded
  explicitly with a rationale; the framework's current position is that a Cursor
  skills mirror is intentionally not shipped because Cursor discovers the existing
  agent, command, and shared skill surfaces, and review tooling already treats an
  absent Cursor skills tree as intentional rather than as a missing mirror.
- README and AGENTS-format Cursor guidance for project rules, subagents,
  commands, and skills must match current Cursor conventions and must not
  describe surfaces or invocation styles that Cursor no longer supports.

---

## Acceptance Criteria

- [ ] AC-1: For every workflow stage that the README or the AGENTS-format guidance
  advertises a Cursor entrypoint for, a reviewer can locate a matching Cursor
  surface (command, subagent, or rule) in the repository by the advertised name.
  No advertised Cursor stage entrypoint resolves only to a Claude- or Codex-only
  name.
- [ ] AC-2: A reviewer can confirm that the Cursor command surface advertised by
  the guidance is complete — specifically, the previously documented-but-missing
  Cursor entrypoints (the smoke-test stage entrypoint and the integration-branch
  graduation entrypoint) are either present as real Cursor surfaces or the
  guidance is corrected so it no longer advertises a Cursor entrypoint that does
  not exist. After this change, the guidance tables and the actual Cursor surfaces
  agree in both directions (no advertised-but-missing entrypoint, no shipped-but-
  undocumented entrypoint for the stages in scope).
- [ ] AC-3: Each new or changed Cursor surface references the canonical protocol
  or document for its stage and contains no restated protocol behavior beyond a
  short orientation summary. A reviewer can open each changed Cursor file and
  confirm the referenced canonical path exists in the repository.
- [ ] AC-4: The README and AGENTS-format guidance sections describing Cursor
  rules, subagents, commands, and skills reflect current Cursor conventions, and a
  reviewer can confirm the descriptions match the actual surfaces the project
  ships (including any invocation-name or format details for rules, subagents, and
  commands).
- [ ] AC-5: The spec and the project guidance record an explicit decision on
  whether a Cursor-native skills mirror is shipped, including the rationale. A
  reviewer can find the recorded decision without inferring it from the presence
  or absence of a directory.
- [ ] AC-6: The Project Type for issue #989 is Feature.

---

## Brief Coverage

### Brief Objective List

From the issue body (Scope and Acceptance Criteria bullets):

- B1: Audit `.cursor/agents`, `.cursor/commands`, `.cursor/rules`,
  `.agents/skills`, and related README/AGENTS references.
- B2: Add or update missing Cursor workflow entrypoints where parity gaps exist,
  including graduation/reviewer-loop guidance if needed.
- B3: Decide whether a `.cursor/skills` mirror is necessary now that Cursor
  discovers `.agents/skills` and compatible Codex/Claude skill directories.
- B4: Keep Cursor wrappers thin and pointed at canonical docs/protocols.
- B5: Cursor users can discover and invoke the expected workflow stages without
  relying on Claude/Codex-only names.
- B6: Any new or changed Cursor surface references the canonical protocol instead
  of duplicating behavior.
- B7: README/AGENTS Cursor guidance reflects current Cursor docs for project
  rules, subagents, commands, and skills.
- B8: Project Type is Feature.

### Coverage Matrix

| Brief objective | Covered by |
| --- | --- |
| B1 (Audit current Cursor surfaces) | Out of Scope (MVP) — audit is the discovery activity behind this spec, not a shippable deliverable; its findings are captured in the Audit Findings note below and drive AC-1, AC-2, AC-5. |
| B2 (Add/update missing entrypoints, incl. graduation/reviewer-loop) | AC-1, AC-2 |
| B3 (Decide on `.cursor/skills` mirror) | AC-5 |
| B4 (Keep wrappers thin, pointed at canonical docs) | AC-3 |
| B5 (Cursor users invoke stages without Claude/Codex-only names) | AC-1 |
| B6 (New/changed surfaces reference canonical protocol, no duplication) | AC-3 |
| B7 (README/AGENTS Cursor guidance reflects current Cursor docs) | AC-4 |
| B8 (Project Type is Feature) | AC-6 |

### Deferral Notes

- B1 (Audit) — Deferred to Out of Scope as a shippable deliverable. Rationale:
  the audit is the investigation that produced this spec; it is not a separate
  artifact the feature must produce. Its results are recorded in the Audit
  Findings note below so reviewers and the implementation plan inherit them.
  Human confirmation requested: no (standard discovery-vs-deliverable split).

### Audit Findings (discovery results that inform the ACs)

These findings come from auditing the current repository surfaces and the
guidance tables. They are recorded here so the implementation plan and reviewers
share the same starting picture; the exact files and wording are an
implementation-plan concern.

- The Cursor subagent set is at parity with the Claude agent set (the same named
  workflow agents exist in both surfaces).
- The Cursor command surface advertises a smoke-test entrypoint and a smoke-test
  reference in the testing guidance, but no matching Cursor smoke-test command
  file ships — an advertised-but-missing entrypoint.
- The integration-branch graduation stage has a Claude entrypoint and a shared
  skill, and the guidance marks Cursor as having no entrypoint for it — a parity
  gap relative to the other tool surfaces that this rollout should resolve or
  explicitly justify.
- No Cursor-native skills directory ships today; a prior framework decision
  treats its absence as intentional, and review tooling already treats an absent
  Cursor skills tree as advisory rather than as a missing required mirror.
- Existing Cursor command and rule wrappers are thin and reference canonical
  protocols, which establishes the pattern any new or changed surface must follow.

---

## Out of Scope (MVP)

- Auditing or changing Claude Code or Codex surfaces beyond what is required to
  keep the cross-tool guidance tables internally consistent. The focus of this
  item is the Cursor surface and its guidance.
- Standing up a Cursor-native skills mirror. The decision recorded by this spec is
  not to ship one; building one is explicitly excluded (see AC-5).
- Cursor Bugbot review-tooling integration itself. That is the parent epic (#988)
  and is tracked by other child items; this item only aligns the Cursor workflow
  surfaces and may add reviewer-loop guidance where a parity gap exists, without
  wiring up Bugbot behavior.
- Producing a standalone audit report artifact. The audit findings are captured in
  this spec; no separate deliverable is required (see Deferral Note for B1).
- Changing the underlying canonical protocols themselves. This item aligns Cursor
  wrappers and guidance to the existing protocols; it does not modify protocol
  behavior.
- Changing agent/subagent model assignments or tool restrictions for Cursor
  subagents.
