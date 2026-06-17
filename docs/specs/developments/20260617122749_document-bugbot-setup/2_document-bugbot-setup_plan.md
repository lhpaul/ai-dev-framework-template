# Document Bugbot Setup and Framework Rollout Guidance — Implementation Plan

**Spec**: [`1_document-bugbot-setup_specs.md`](1_document-bugbot-setup_specs.md)
**Smoke test runbook**: [`../../../testing/workflow/991-document-bugbot-setup.smoke-test.md`](../../../testing/workflow/991-document-bugbot-setup.smoke-test.md)

---

## Summary

**Approach**: Add a new documentation-only integration guide,
`docs/workflow/development-workflow/integrations/bugbot.md`, that documents how
framework adopters enable Cursor Bugbot, how it reports on pull requests, and how
it fits into the staged AI development workflow as post-push validation. Include a
minimal, copy-ready `.cursor/BUGBOT.md` template inside the guide (as a fenced
code block, not a live root file) plus guidance on nested Bugbot rule files and
aligning Bugbot rules with `REVIEW.md` by reference. Add discoverability
cross-references from the two authoritative integration listings (the generic
platform guide and the dev-workflow README Integration Guides index).

**Estimated complexity**: S

<!-- S: < 1 day | M: 1-3 days | L: 3+ days -->

**Rationale**: This is a documentation-only feature. No scripts, schemas, or code
change. The work is confined to authoring one new Markdown guide and adding two
cross-reference list entries. There is no parser, API surface, or concurrency
behavior involved. The only nuance is correctly describing existing tooling
contracts (the planned-but-unsupported / skipped semantics already defined in
`pr-review-platform.md`) without overstating tooling behavior.

**Dependencies**: None. The spec was merged via PR #996 to the integration branch
`develop-cursor-bugbot-integration`, which is the base for this work. The plan does
not depend on the separate Bugbot reviewer-loop adapter item (explicitly out of
scope per the spec) — this guide documents Bugbot as planned-but-unsupported by
the loop.

---

## Template-Fit Check (Step 0 result)

This repository sets `template.is_template: true` in `.ai-dev-workflow.yaml`, so
the Step 0 Template-Fit Check is mandatory. **Result: passes (generic enough).**
Cursor Bugbot is a workflow PR-review tooling integration — the same class of
artifact as the existing `coderabbit.md`, `pr-agent.md`, `greptile.md`,
`devin.md`, `haystack.md`, `copilot.md`, and `claude-code-action.md` guides. It
improves the workflow documentation the template itself ships and benefits every
downstream project that uses Cursor as its agent surface, regardless of their
application tech stack. It does not reference a downstream application framework
(React/Rails/Django/etc.). No human confirmation is required.

**Template-ownership notes for the developer:**

- `docs/workflow/development-workflow/integrations/bugbot.md` is a
  **template-owned** file (framework-shipped documentation). Downstream teams
  consume it as-is via sync-template. Do not add wrapping `<!-- TEMPLATE-OWNED -->`
  markers unless an adjacent integration guide already uses them (the sibling
  guides do not).
- The `.cursor/BUGBOT.md` content embedded in the guide is a **customizable
  scaffold** that downstream teams copy into their own repository and edit. It is
  delivered as a fenced code block inside the guide, not as a live root-level
  `.cursor/BUGBOT.md` file in this template (the template does not enable Bugbot
  for itself — out of scope per the spec).

---

## Verification Log

> Record reproducible plan-time verification commands that influenced scope, counts, or file lists. Include repo revision and concrete results.

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `9a7de1e` (tip of `implementation-plan/991-document-bugbot-setup`, branched from `origin/develop-cursor-bugbot-integration`) |
| Existing integration guides | `ls docs/workflow/development-workflow/integrations/` | 17 guides present; no `bugbot.md` exists yet |
| Existing Bugbot references | `grep -rli "bugbot" --include="*.md" --include="*.yaml" --include="*.sh" .` (excluding this spec dir) | Only sibling epic specs `20260617122727_bugbot-reviewer-platform` and `20260617122852_align-cursor-workflow-surfaces`; no docs/scripts reference Bugbot yet |
| Authoritative review-tool integration listings | `grep -rln "integrations/coderabbit.md\|integrations/pr-agent.md\|integrations/greptile.md" --include="*.md" .` (excluding `/specs/`) | Index-style listings: `pr-review-platform.md` ("See:" block) and `docs/workflow/development-workflow/README.md` ("Integration Guides"). Illustrative-only mentions (not exhaustive indexes): `REVIEW.md`, root `README.md`, `docs/workflow/setup/protocol.md`, plus `CHANGELOG.md` and a smoke-test file |
| Generic platform "See:" block contents | `grep -n "\.md" docs/workflow/development-workflow/integrations/pr-review-platform.md` (lines 7-11) | Lists claude-code-action, coderabbit, greptile, devin, haystack-triage — bugbot must be added |
| Planned-but-unsupported / skipped contract | Read `pr-review-platform.md` "What a Platform Must Provide" + "Aggregation Rules" | Confirms: unsupported platforms documented as "planned but unsupported" and reported `skipped` (reason `unsupported-platform`) by `pr-review-loop.sh` |
| `.cursor/` root files | `ls .cursor/*.md` | No root-level `.cursor/*.md` files exist (only `agents/`, `commands/`, `rules/`) — confirms the template does not ship a live `.cursor/BUGBOT.md` |

**Scope determination (pattern-completeness):** The spec phrases AC-10 as "any
relevant README/agent-guidance references that list review-tool integrations." This
is pattern-based, so the live `grep` above was used rather than a frozen list. The
result shows exactly two **authoritative index-style** listings that enumerate the
review-tool integration guides as a set: the generic `pr-review-platform.md` "See:"
block and the dev-workflow `README.md` "Integration Guides" section. The other hits
(`REVIEW.md`, root `README.md`, `docs/workflow/setup/protocol.md`) cite specific
tools as illustrative examples ("e.g., CodeRabbit"), not exhaustive enumerations,
and the dev-workflow README index is itself already non-exhaustive (it omits
`copilot.md`, `pr-agent.md`, `claude-code-action.md`). Updating the two index-style
listings satisfies discoverability (AC-1, AC-10) without forcing inconsistent edits
to illustrative prose. The developer should not add bugbot mentions to the
illustrative-only files.

---

## Layer-by-Layer Changes

> Documentation-only feature. Database, Backend/API, Shared Packages, and Frontend/UI layers do not apply.

### Database / Data Layer

- Not applicable — no schema, migration, or seed data.

### Backend / API

- Not applicable — no code change. In particular, this plan does **not** add a
  `bugbot` platform to `scripts/development-workflow/pr-review-loop.sh` (the
  reviewer-loop adapter is explicitly out of scope per the spec).

### Shared Packages / Libraries

- Not applicable.

### Frontend / UI

- Not applicable.

### Infrastructure / Configuration

- [ ] **New file** `docs/workflow/development-workflow/integrations/bugbot.md` —
      the Bugbot integration guide. Required sections (each maps to ACs below):
  - **Intro / what Bugbot adds** — one-paragraph summary plus a link out to
    Cursor's product docs; states Bugbot is optional and the workflow functions
    without it; links to `pr-review-platform.md` for the multi-platform loop and
    aggregation rules. (AC-1)
  - **Review model / where Bugbot fits** — explicitly states Bugbot is post-push
    validation and does **not** replace the pre-PR review gate defined in
    `REVIEW.md`. (AC-4)
  - **Prerequisites & setup** — GitHub/Cursor connection steps and the required
    repository access (GitHub App installation / repo permissions Bugbot needs to
    read PRs and post checks). (AC-2)
  - **Configuration in `.ai-dev-workflow.yaml`** — explains where Bugbot is
    declared in the workflow integration manifest so a downstream team knows where
    to configure it, consistent with how other platforms appear under
    `review.on_draft.github` / `review.on_ready.github`. (AC-3)
  - **PR behavior** — the Bugbot check name(s), the possible check conclusions
    (including the known **neutral** conclusion), how to trigger a manual review,
    automatic review settings, and draft-PR behavior. (AC-2, AC-5)
  - **Branch protection implications** — describes the known neutral-check
    behavior and its implications for making (or not making) Bugbot a required
    status check. (AC-5)
  - **Autofix considerations** — what to weigh before enabling Bugbot Autofix.
    (AC-2)
  - **Reviewer-loop status** — states Bugbot is currently planned-but-unsupported
    by `scripts/development-workflow/pr-review-loop.sh` and is reported as
    `skipped` by that loop until an adapter exists, consistent with the generic
    platform contract in `pr-review-platform.md`. (AC-9)
  - **Bugbot rules** — explains the repository-level `.cursor/BUGBOT.md` rules
    file and nested per-directory Bugbot rule files; includes a minimal,
    copy-ready `.cursor/BUGBOT.md` template (fenced code block); and explains how
    to keep Bugbot rules aligned with `REVIEW.md` by **referencing** it rather
    than duplicating the full review contract. (AC-6, AC-7)
  - **Rollout guidance for Cursor-primary teams** — a dedicated section for client
    teams that use Cursor as their primary agent surface, reinforcing that Bugbot
    is complementary post-push validation, not a substitute for the pre-PR review
    gate, and giving an adoption path that accounts for neutral-check behavior in
    branch-protection decisions. (AC-8)
  - **Known limitations** — concise list (e.g., neutral checks, no review-loop
    adapter yet, links out for vendor-maintained product detail). (AC-9)
- [ ] **Edit** `docs/workflow/development-workflow/integrations/pr-review-platform.md`
      — add `bugbot.md` to the "See:" list of platform-specific integration docs
      (lines 7-11), keeping alphabetical/grouped style with siblings. (AC-10)
- [ ] **Edit** `docs/workflow/development-workflow/README.md` — add
      `docs/workflow/development-workflow/integrations/bugbot.md` to the
      "Integration Guides" list (around lines 605-615) so the new guide is
      reachable from the index/README listing. (AC-1, AC-10)

---

## Testing Strategy

**Test types**: Manual / documentation review (this is a documentation-only
feature; no unit, integration, or automated regression tests apply).

**Key scenarios to test** (validated via the smoke test runbook and review gates):

1. The new guide exists in the integrations area and is reachable from the
   dev-workflow README Integration Guides index and the `pr-review-platform.md`
   "See:" list — maps to AC-1, AC-10.
2. The guide documents GitHub/Cursor setup, required repository access, check
   name(s), check conclusions, manual trigger, automatic review settings, draft-PR
   behavior, and Autofix considerations — maps to AC-2.
3. The guide explains where Bugbot is declared in `.ai-dev-workflow.yaml` — maps
   to AC-3.
4. The guide explicitly states Bugbot is post-push validation and does not replace
   the pre-PR review gate — maps to AC-4.
5. The guide describes neutral-check behavior and branch-protection implications —
   maps to AC-5.
6. The guide includes a minimal, copy-ready `.cursor/BUGBOT.md` template and
   explains nested Bugbot rule files — maps to AC-6.
7. The guide explains aligning Bugbot rules with `REVIEW.md` by reference, not
   duplication — maps to AC-7.
8. The guide includes rollout guidance for Cursor-primary teams — maps to AC-8.
9. The guide states Bugbot is planned-but-unsupported by `pr-review-loop.sh` and
   reported as `skipped` — maps to AC-9.

**Lint validation**: `markdownlint-cli2` and the heuristic lint/duplicate-header
checks must pass on the new guide (relative links resolve, no trailing whitespace,
trailing newline present). All internal links (to `REVIEW.md`,
`pr-review-platform.md`, Cursor product docs) must resolve.

**Smoke test runbook**: `docs/testing/workflow/991-document-bugbot-setup.smoke-test.md`

**Regression suite**: Omitted — this repository has no automated application
regression suite for documentation; doc lint + review gates are the verification
mechanism.

<!-- Parser-risk addendum: not applicable. No parser, regex engine, scanner, lint module, or structured-text scanning is introduced or modified. The change is prose documentation plus an embedded copy-ready template. -->

<!-- Concurrent-event-source addendum: not applicable. No event listeners, sockets, timers, async queues, shared mutable state, or init/teardown sequences are introduced. -->

<!-- Cross-cutting checklist: not applicable. This plan does not add or modify a safety/quality/compliance checklist category in REVIEW.md, the planning protocol, or the implementation protocol; it adds one optional integration guide. No agent/skill/protocol guidance files require updates. -->

---

## Seed Data

> Not applicable — documentation-only feature, no runtime data.

| Entity | Values / Scenario | File |
| --- | --- | --- |
| None | No seed data required | N/A |

---

## Documentation Updates

> The deliverable of this feature *is* documentation. The files below are the in-scope doc artifacts; they are created/edited during implementation (not deferred), because the documentation is the feature itself.

- [ ] `docs/workflow/development-workflow/integrations/bugbot.md` — **new** Bugbot
      integration guide (the primary deliverable).
- [ ] `docs/workflow/development-workflow/integrations/pr-review-platform.md` —
      add `bugbot.md` to the "See:" platform list.
- [ ] `docs/workflow/development-workflow/README.md` — add `bugbot.md` to the
      "Integration Guides" index list.
- [ ] `AGENTS.md` / `CLAUDE.md` — **None.** `AGENTS.md` lists only `haystack.md`
      in its Key Documentation table as an illustrative integration reference, not
      an exhaustive review-tool index, so it does not need a Bugbot entry. (No
      change; recorded here for completeness.)
- [ ] `REVIEW.md`, root `README.md`, `docs/workflow/setup/protocol.md` — **None.**
      These cite specific tools as illustrative examples, not exhaustive
      integration indexes (see Verification Log scope determination). No edits.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Guide overstates tooling behavior (implies the reviewer loop already runs Bugbot) | Med | Med | Reuse the exact "planned but unsupported" / `skipped` (`unsupported-platform`) language from `pr-review-platform.md`; the AC-9 section must say the loop reports `skipped` until an adapter exists |
| Embedded `.cursor/BUGBOT.md` template duplicates the full review contract | Low | Med | Template must be minimal and copy-ready and must **reference** `REVIEW.md` rather than restate it (AC-6, AC-7); reviewer checks template length/content |
| Vendor-specific details (exact check name, Autofix UI) drift as Cursor changes Bugbot | Med | Low | Link out to Cursor's product docs for vendor-maintained detail; keep the guide focused on workflow integration (per spec Out of Scope) |
| Broken relative links / lint failures cause a fix cycle | Med | Low | Run `markdownlint-cli2` + heuristic lint locally before commit (Step 8 of git execution); count `../` depth carefully for links to `REVIEW.md` and sibling guides |
| Cross-reference omitted, guide not discoverable | Low | Med | Plan enumerates both index listings explicitly (pr-review-platform "See:" + README Integration Guides); smoke test verifies reachability |

---

## Code Samples

> No production code in this feature. The only "sample" is the minimal
> `.cursor/BUGBOT.md` template embedded in the guide. The developer should mark it
> clearly as a copy-ready scaffold (e.g., a heading like "Minimal `.cursor/BUGBOT.md`
> template" above a fenced code block) and ensure it references `REVIEW.md` rather
> than duplicating the review contract. Illustrative skeleton (adapt during
> implementation):
>
> ```markdown
> # Bugbot Review Rules
>
> Apply the review standards in our review contract: see `REVIEW.md`.
> Do not duplicate the full contract here — reference it.
>
> Focus areas for this repository:
> - <project-specific concern 1>
> - <project-specific concern 2>
> ```

---

## Implementation Order

> Ordered steps. Later steps may depend on earlier ones.

1. From `implementation-plan/991-document-bugbot-setup` (already branched from
   `origin/develop-cursor-bugbot-integration`), create the feature branch for
   implementation off `origin/develop-cursor-bugbot-integration`:
   `feature/991-document-bugbot-setup`. (The implementation PR targets
   `develop-cursor-bugbot-integration`, NOT `develop`.)
2. Create `docs/workflow/development-workflow/integrations/bugbot.md` with all
   required sections listed under Infrastructure / Configuration above, mapping
   each section to its acceptance criterion. Model structure/tone on
   `integrations/copilot.md` and `integrations/coderabbit.md`, but ensure the
   reviewer-loop status reflects planned-but-unsupported / `skipped` (Bugbot is
   NOT a runnable loop platform yet).
3. Embed the minimal copy-ready `.cursor/BUGBOT.md` template (fenced code block)
   and the nested-rule-file + REVIEW.md-by-reference guidance in the guide.
4. Edit `docs/workflow/development-workflow/integrations/pr-review-platform.md`:
   add `- [`integrations/bugbot.md`](bugbot.md)` to the "See:" list (lines 7-11).
5. Edit `docs/workflow/development-workflow/README.md`: add
   `- `docs/workflow/development-workflow/integrations/bugbot.md`` to the
   "Integration Guides" list (around lines 605-615).
6. Verify all internal relative links resolve (to `REVIEW.md`,
   `pr-review-platform.md`, sibling guides) and confirm no illustrative-only files
   were edited (REVIEW.md, root README.md, setup/protocol.md unchanged).
7. Update/verify the smoke test runbook
   `docs/testing/workflow/991-document-bugbot-setup.smoke-test.md` covers every AC.
8. Update project docs per the **Documentation Updates** section above — the new
   guide plus the two index edits are the doc updates; no further `docs/project/`
   or `AGENTS.md` edits are required.
9. Update `CHANGELOG.md` under `[Unreleased]` using the project's
   `**Bold Title** (#N):` format. Literal entry to copy (place under `### Added`):

   ```markdown
   - **Document Bugbot setup and framework rollout guidance** (#991): add a Cursor Bugbot integration guide under `docs/workflow/development-workflow/integrations/bugbot.md` covering GitHub/Cursor setup, check behavior, neutral-check and branch-protection implications, a minimal `.cursor/BUGBOT.md` template, and rollout guidance for Cursor-primary teams; cross-reference it from the generic PR review platform guide and the integration guides index.
   ```

10. Run `markdownlint-cli2` plus the heuristic lint and duplicate-header checks on
    the new/edited Markdown and the smoke test runbook; fix any violations before
    committing.
