# Post-Merge QA (`/post-merge-qa`) — Spec

---

## Overview

Operators need a shared workflow command to quality-check work that is already on `develop` or an integration branch (`develop-<slug>`), not only the pre-merge smoke path for a single in-flight item. `/post-merge-qa` (with compatibility alias `/merged-qa-tester`) discovers a merged or epic-branch scope, confirms it with the human, verifies that a runnable test environment exists, exercises critical flows and UX, optionally compares against design assets when those assets are already discoverable, and — when actionable defects are found — opens a fix pull request with the corrections. It does not create a separate backlog item for those fixes, and it does not replace per-item pre-merge smoke tests.

**Confirmed product decisions (alignment):**

- Primary command name: `/post-merge-qa`; compatibility alias: `/merged-qa-tester`; slug: `post-merge-qa`.
- Target branch defaults to the current checkout when it is `develop` or `develop-<slug>`; otherwise the human must supply an explicit target.
- Default proposed scope is items already in a merged state for that target, or — when an epic is in scope — all items on the epic’s integration branch; the command confirms the proposed set with the human before testing.
- Before testing begins, the command checks that the necessary runnable environment is available and asks the human when it is not.
- Findings that need code fixes result in a new fix PR; no follow-up backlog item is required for those fixes.
- Relationship to graphical design assets work (#1282) is **orthogonal**: when design assets happen to be discoverable for the scoped items, include light fidelity checks; when none exist, skip silently (do not fail the run for missing assets).
- Does not replace pre-merge smoke tests; does not invent a full visual-regression platform.

---

## Use Cases

### Use Case 1: Operator runs post-merge QA on `develop` or an integration branch

**Actor**: Human operator (or orchestrator agent acting on their behalf) invoking `/post-merge-qa` or `/merged-qa-tester`

**Preconditions**:

- The repository is checked out on `develop` or `develop-<slug>`, **or** the operator supplies an explicit target branch of that form
- There is merged work (or epic-branch work) to inspect on that target

**Steps**:

1. Operator invokes `/post-merge-qa` (or the alias), optionally naming a target branch, an epic, one or more items, or “recent merged PRs”
2. Command resolves the target branch: use current checkout when it is `develop` / `develop-<slug>`; otherwise require an explicit target and stop if missing
3. Command proposes a QA scope: preferably items already in a merged state for that target, or — for an epic — all items on the epic’s integration branch; other explicit inputs the operator named are included
4. Command presents the proposed scope and asks the human to confirm or adjust before testing
5. Command runs a preflight: confirm a runnable app / test surface exists (URLs, local apps, or documented how-to-run). If anything required is missing, ask the human and wait — do not begin exercising flows until the gap is resolved or the human explicitly narrows scope to what can be tested
6. Command exercises critical user flows and UX for the confirmed scope on the target branch
7. When design assets are already discoverable for scoped items, perform light fidelity comparison (expected vs actual). When none are discoverable, skip asset checks without failing the run
8. If actionable defects are found, implement the fixes and open a **fix PR** against the appropriate base (`develop` or the integration branch under test). Summarize findings and fixes in the PR description. Do **not** create a separate backlog item for those fixes
9. If no actionable defects are found, report a clean result to the human and do not open a fix PR

**Postconditions**:

- Human has a clear pass/fail outcome for the confirmed scope
- When fixes were needed, a fix PR exists with the corrections and a findings summary; no new backlog item was created solely to track those fixes
- When nothing needed fixing, no fix PR was opened

**Information shown**:

- Resolved target branch
- Proposed and confirmed item/PR scope
- Preflight environment status (ready / missing with questions)
- Findings summary (pass, defects found, assets checked or skipped)
- Fix PR link when one was opened

**Actions available**:

- Confirm or edit proposed scope
- Supply missing run/test environment details when asked
- Review and merge (or reject) the fix PR when one was opened

**Considerations**:

- Scope confirmation is mandatory even when the default proposal is clear
- “Merged state” means work already integrated onto the target branch (not still-open feature PRs unless the human explicitly adds them)
- Epic path: prefer every item that belongs on that epic’s integration branch, then confirm with the human
- If defects need a product decision before a safe fix exists, stop and ask the human rather than guessing in the fix PR

---

### Use Case 2: Preflight finds the environment is not ready

**Actor**: Human operator invoking `/post-merge-qa`

**Preconditions**:

- Target branch and scope can be resolved (or are mid-confirmation)
- Runnable app / URLs / credentials / how-to-run guidance needed for the scoped work is missing or unclear

**Steps**:

1. Command detects missing prerequisites during preflight
2. Command lists what is missing and asks the human how to proceed (provide URLs, start apps, point at docs, or shrink scope)
3. Command does not exercise flows until the human answers
4. After the human supplies what is needed or narrows scope, continue Use Case 1 from the exercise step; if the human cannot provide a testable surface, stop with a blocked outcome (no fix PR)

**Postconditions**:

- No flows were exercised against an untestable environment
- Either testing resumes with a ready environment / narrowed scope, or the run stops blocked with a clear reason

**Information shown**:

- Explicit list of missing prerequisites
- Questions for the human

**Actions available**:

- Provide missing run details
- Narrow scope to what can be tested
- Abort the run

**Considerations**:

- For docs-only or template-only repositories with no product UI under test, the human may confirm a non-UI validation path (e.g., command/docs surfaces only) or abort

---

### Use Case 3: Design assets are present for some scoped items

**Actor**: Agent running `/post-merge-qa` after scope confirmation and preflight

**Preconditions**:

- Confirmed scope includes one or more items that already have discoverable design assets (tracker attachments and/or development-folder assets per the existing design-assets convention)
- Relationship to the design-assets capability is orthogonal: this command does not require that capability’s delivery; it only uses assets when they already exist

**Steps**:

1. For each scoped item, discover whether design assets are already available
2. When assets exist, compare critical screens/flows against them at a light fidelity level (layout, key copy, primary controls — not pixel-perfect automation)
3. Record asset-related defects alongside other findings
4. Include asset-related fixes in the same fix PR when actionable

**Postconditions**:

- Asset checks ran only where assets were discoverable
- Missing assets did not fail or block the run

**Information shown**:

- Which items had assets checked vs skipped

**Actions available**:

- Same as Use Case 1 for the resulting findings / fix PR

**Considerations**:

- Do not invent or borrow assets from unrelated sibling items
- Light fidelity is intentional; full visual regression is out of scope

---

## Business Rules

- Primary invocation surface is `/post-merge-qa`; `/merged-qa-tester` is a compatibility alias with identical behavior
- Allowed QA target branches are only `develop` and `develop-<slug>`
- If the current checkout is not an allowed target and no explicit allowed target was given, the command must stop and ask for a target — it must not silently QA an arbitrary feature branch
- Default scope proposal prefers: (a) items already merged onto the target, or (b) when an epic is indicated, all items on that epic’s integration branch; the human must confirm before flows are exercised
- Preflight of the runnable test environment is mandatory before exercising flows
- When actionable defects are found, the command opens a fix PR with the fixes; it must not create a separate backlog item solely to track those fixes
- When no actionable defects are found, the command must not open an empty or ceremony-only fix PR
- Product-code changes from this command happen only via that fix PR path (or not at all on a clean run)
- Design-asset fidelity is optional and best-effort: check when assets are discoverable; skip silently when not
- This command does not replace per-item pre-merge smoke tests
- This command does not auto-merge the fix PR; normal human (or delegated) merge policy still applies to that PR
- If a safe fix cannot be determined without a product decision, stop and ask rather than inventing behavior in the fix PR

---

## Operational Visibility

- **Operator-facing output**: target branch, confirmed scope, preflight status, findings summary, fix PR URL or clean-pass statement
- **Fix PR description**: must summarize what was QA’d, what failed, what was fixed, and which asset checks ran or were skipped
- **Tracker**: no new backlog item is required for fixes produced by this command; existing scoped items are not closed solely because post-merge QA ran

---

## Acceptance Criteria

- [ ] An operator can invoke `/post-merge-qa` or `/merged-qa-tester` and get identical behavior from either name
- [ ] When the checkout is `develop` or `develop-<slug>`, the command uses that as the QA target without requiring an extra flag; when it is not, the command asks for an explicit allowed target and refuses to proceed on a disallowed branch
- [ ] The command proposes a scope of merged items (or all items on an epic’s integration branch when an epic is in play), presents that proposal, and only begins exercising flows after human confirmation (or an explicit confirmed adjustment)
- [ ] Before exercising flows, the command verifies a runnable test environment exists and asks the human when prerequisites are missing; it does not start flow exercise while blocked on environment
- [ ] When design assets are discoverable for scoped items, the run includes light fidelity checks; when none are discoverable, the run continues without failing for missing assets
- [ ] When actionable defects are found, the run opens a fix PR containing the fixes and a findings summary, and does **not** create a new backlog item for those fixes
- [ ] When no actionable defects are found, the run reports a clean pass and does not open a fix PR
- [ ] Pre-merge smoke-test commands/protocols remain unchanged and are still the path for single-item pre-merge validation
- [ ] Command surfaces exist for Cursor, Claude Code, and Codex (command / skill / agent entrypoints as appropriate to each tool)

---

## Out of Scope (MVP)

- Replacing or removing per-item pre-merge smoke tests
- Full visual-regression platforms, pixel-diff harnesses, or continuous screenshot baselines
- Auto-merging the fix PR produced by post-merge QA
- Creating follow-up backlog items / tickets as the primary output path for defects (superseded by the fix-PR path per alignment)
- QA of arbitrary non-`develop` / non-`develop-<slug>` branches without an explicit allowed target
- Inventing design assets when none were supplied for the scoped items
- Making this command the only or primary design-reviewer / mockup gate for the whole workflow

---

## Brief Coverage Matrix

| Brief objective | Mapping |
| --- | --- |
| Add `/post-merge-qa` command + protocol/skill across Cursor / Claude / Codex | AC: command surfaces for all three tools; primary name `/post-merge-qa` |
| Optional compatibility alias `/merged-qa-tester` | AC: alias has identical behavior |
| Target branches `develop` or `develop-<slug>` | AC + business rules: allowed targets only; default from checkout when allowed |
| Scope inputs: one item, several items, or an epic / recent merged PRs | Use Case 1 + AC: propose merged / epic-branch scope; confirm with human; honor explicit inputs |
| Discover merged scope, run apps, exercise flows, critical UX | Use Cases 1–2 + ACs: preflight, exercise flows, findings summary |
| Produce fix-ready output without requiring a separate backlog item | **Alignment override**: open a fix PR with fixes when actionable defects exist (brief originally suggested ticket-ready report / no auto fix PR — human confirmed fix-PR path instead) |
| When graphical design assets exist, include fidelity checks | Use Case 3 + AC; Orthogonal to #1282 — best-effort only |
| Do not replace per-item pre-merge smoke tests | Out of scope + AC that smoke remains unchanged |
| Do not invent a full visual-regression platform | Out of scope |
| Auto-merge of resulting fix work | Out of scope (fix PR is opened; merge follows normal policy) |
