# Protocol: Post-Merge QA

**Agent role**: Post-Merge QA Tester (`post-merge-qa`)
**Commands**: `/post-merge-qa` (primary), `/merged-qa-tester` (compatibility alias — identical behavior)
**Purpose**: Quality-check work already on `develop` or an integration branch
(`develop-<slug>`), then open one fix PR when safely actionable defects exist.

This protocol is the **single source of truth**. Command surfaces and agents load
it; they must not fork behavior.

Related:

- Spec / plan: `docs/specs/developments/20260721204647_1283-post-merge-qa/`
- Design assets (optional consumer): [`../design-assets.md`](../design-assets.md)
- Scope helper: `scripts/development-workflow/post-merge-qa-scope.sh`
- Pre-merge smoke (unchanged): [`04-smoke-test-protocol.md`](04-smoke-test-protocol.md)

---

## Non-goals

- Replacing per-item pre-merge smoke tests (`/smoke-tester` / protocol 04)
- Full visual-regression platforms, pixel diffs, or CI screenshot suites
- Auto-merging the fix PR produced by this command
- Creating a new backlog item for defects found during this run
- QA of arbitrary non-`develop` / non-`develop-<slug>` branches

---

## Step 0: Resolve target branch

Allowed targets only: `develop` or `develop-<slug>`.

1. If the operator supplied an explicit target, use it when it matches an allowed
   form; otherwise stop and ask for an allowed target.
2. Else if the current checkout is `develop` or `develop-<slug>`, use that.
3. Else stop and ask for an explicit allowed target. Do **not** silently QA a
   feature/fix/spec branch.

Record the resolved target as `QA_BASE`.

---

## Step 1: Propose scope (read-only)

Prefer the helper:

<!-- workflow-shell-contract: bash-zsh -->

```bash
./scripts/development-workflow/post-merge-qa-scope.sh \
  --base "$QA_BASE" \
  [--epic <number>] \
  [--issues <csv>] \
  [--tracker-items <csv>] \
  [--recent-merged-prs <n>] \
  --json
```

Default proposal preference (when the operator did not already pin items):

- For `develop`: provider-backed tracker items in the repository's configured
  post-merge state (for example, `Merged`) that have shipped onto `QA_BASE`.
  Resolve the provider from `.ai-dev-workflow.yaml` (`issue_tracker.provider`)
  when configured; do not hardcode one tracker vendor into the protocol.
- For `develop-<slug>`: items and PRs associated with that integration branch
  and already merged into that branch. Do not require final post-merge tracker
  state for integration-branch QA unless the repository's tracker workflow
  explicitly does so.
- If provider-backed tracker discovery is unavailable, unclear, or not
  configured, fall back to recently merged PRs on `QA_BASE` and state that the
  proposal is PR-derived.
- When an epic is indicated: items associated with that epic's integration
  branch, plus any PRs merged into the resolved QA base for those items.

Honor explicit operator inputs (single item, several items, epic, recent merged
PRs) as seeds or filters.

Every proposal must state its scope source (`tracker-post-merge`,
`integration-branch`, `merged-prs`, `explicit`, or `epic`) and whether it is
provider-backed or fallback. The helper emits `scopeSource`, `providerBacked`,
and `fallback` in JSON, and renders the same metadata in text output. Present
the proposal to the human. **Do not exercise flows until the human confirms or
adjusts the scope.**

| Confirmed scope | Action |
| --- | --- |
| Non-empty | Continue to Step 2 |
| Empty | Stop cleanly — no preflight, no flows, no fix PR |

The helper and this step are **read-only**: no tracker updates, branch creation,
or PR opens.

---

## Step 2: Environment preflight

Before exercising flows, resolve a runnable test surface in order:

1. Explicit human-provided URLs / how-to-run notes for this run
2. Project `docs/testing/README.md` and Common Commands in `AGENTS.md`
3. Configured `browser_automation` provider in `.ai-dev-workflow.yaml` (and local
   override when present)

If a required runnable surface is missing or unclear:

1. List what is missing
2. Ask the human how to proceed (provide URLs, start apps, point at docs, narrow
   scope, or confirm a **docs-only** validation path)
3. Do **not** begin flow exercise until the gap is resolved or the human
   explicitly narrows/confirms a testable path

If the human cannot provide a testable surface, stop with a blocked outcome and
do not open a fix PR.

---

## Step 3: Exercise flows and critical UX

On `QA_BASE` for the confirmed scope:

1. Exercise critical user flows for the scoped work
2. Note UX defects (broken flows, missing states, confusing errors, accessibility
   blockers that are obvious in the exercised path)
3. Record pass/fail per scoped item or PR with concrete evidence

For docs-only / template-only confirmed paths, validate the documented command
and documentation surfaces instead of inventing a product UI.

---

## Step 4: Optional design-asset fidelity

For each scoped item, discover design assets per
[`design-assets.md`](../design-assets.md).

| Assets discoverable? | Action |
| --- | --- |
| Yes | Light fidelity comparison (layout, key copy, primary controls) — not pixel-perfect automation |
| No | Skip silently — do **not** fail the run for missing assets |

Do not invent or borrow assets from unrelated sibling items. Relationship to the
design-assets capability is **orthogonal**: use assets only when they already
exist.

---

## Step 5: Findings → clean pass or one fix PR

### Clean pass

If no actionable defects: report a clean result to the human. Do **not** open a
fix PR. Do **not** create a backlog item.

### Safely actionable defects

1. Implement the safe fixes
2. Open **exactly one** fix PR whose **base is `QA_BASE`**
3. Suggested branch form: `fix/post-merge-qa-<short-slug>` (include a dominant
   issue number in the slug when scope is a single item)
4. PR description must include: what was QA’d, what failed, what was fixed, which
   asset checks ran or were skipped, and any deferred product questions
5. Do **not** create a separate backlog item for those fixes
6. Do **not** auto-merge the fix PR

### Product-decision defects

Defects that need a product decision must not be guessed away. Ask the human.
Safely fixable defects may still ship in the same fix PR when deferred findings
are listed explicitly for the human and are not silently dropped. If only
product-decision items remain and nothing is safely fixable, ask and stop —
no ceremony-only PR.

---

## Step 6: Operator-facing report

Always report:

- Resolved `QA_BASE`
- Confirmed scope
- Preflight status (ready / missing with questions / docs-only)
- Findings summary (pass, defects, assets checked or skipped, deferred decisions)
- Fix PR URL when one was opened, or an explicit clean-pass / blocked statement

---

## Acceptance mapping (implementation checklist)

Agents completing a `/post-merge-qa` run should be able to point each of these
at observed evidence:

- Primary and alias commands behave identically
- Disallowed bases stop without testing
- Scope is proposed and confirmed before flows
- Empty confirmed scope stops cleanly
- Preflight asks when the environment is missing
- Missing design assets do not fail the run
- Actionable defects → one fix PR on `QA_BASE`, no new backlog item
- Clean pass → no fix PR
- Product-decision defects are asked, not invented
