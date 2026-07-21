# Smoke Test Runbook: Post-Merge QA (`/post-merge-qa`)

**Feature**: Post-Merge QA (`/post-merge-qa` / `/merged-qa-tester`)
**Spec**: [`docs/specs/developments/20260721204647_1283-post-merge-qa/1_1283-post-merge-qa_specs.md`](../../specs/developments/20260721204647_1283-post-merge-qa/1_1283-post-merge-qa_specs.md)
**Plan**: [`docs/specs/developments/20260721204647_1283-post-merge-qa/2_1283-post-merge-qa_implementation-plan.md`](../../specs/developments/20260721204647_1283-post-merge-qa/2_1283-post-merge-qa_implementation-plan.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

- [ ] On a clean checkout of this repository (template / workflow hub)
- [ ] `gh` authenticated for read-only issue/PR queries used by the scope helper
- [ ] No requirement to run a product app UI for the docs-only path below

---

## Test Data

| Item | Value |
| --- | --- |
| Primary command | `/post-merge-qa` |
| Alias command | `/merged-qa-tester` |
| Protocol | `docs/workflow/development-workflow/protocols/08-post-merge-qa-protocol.md` |
| Scope helper | `scripts/development-workflow/post-merge-qa-scope.sh` |
| Allowed bases | `develop`, `develop-<slug>` |

---

## Smoke Test Steps

### Step 1: Command surfaces exist

**Maps to**: AC — Cursor / Claude / Codex surfaces

1. Confirm Cursor command + agent files for `post-merge-qa` exist
2. Confirm Claude command + agent files exist
3. Confirm Codex/agents skill exists
4. Confirm `merged-qa-tester` alias surfaces exist and point at the same protocol

**Expected result**: All listed surfaces present; alias text states identical behavior.

### Step 2: Disallowed base stops

**Maps to**: AC — refuse disallowed branches

1. From a non-`develop` / non-`develop-<slug>` context (or pass a disallowed `--base`), invoke the scope helper / protocol target resolution
2. Observe stop/ask behavior

**Expected result**: No flow exercise; operator is asked for an allowed target.

### Step 3: Scope proposal requires confirmation

**Maps to**: AC — propose + confirm before flows

1. Run the scope helper against `develop` (or a known integration branch)
2. Verify it prints a proposal without mutating tracker/PRs
3. Confirm protocol/agent instructions require human confirmation before testing
4. Confirm empty confirmed scope stops without preflight/flows/fix PR

**Expected result**: Read-only proposal; confirmation gate documented and enforceable.

### Step 4: Preflight when environment missing

**Maps to**: AC — environment preflight

1. On this template repo, follow the docs-only / no-UI path
2. Verify the protocol asks before inventing a runnable app URL

**Expected result**: Missing product UI does not silently proceed into fake app testing; human can confirm docs-only validation or abort.

### Step 5: Clean docs-only dry run opens no fix PR

**Maps to**: AC — clean pass → no fix PR; no backlog item

1. With human-confirmed docs-only scope that has no actionable defects, complete the protocol walkthrough
2. Verify no `fix/*` PR and no new backlog item were created

**Expected result**: Clean pass report only.

### Step 6: Alias parity

**Maps to**: AC — identical behavior for `/merged-qa-tester`

1. Diff or read alias command/skill bodies vs primary
2. Confirm both load protocol 08

**Expected result**: No behavior fork.

### Step 7 (optional): Design fidelity skip path

**Maps to**: AC — skip assets when none discoverable

1. Run discovery per `design-assets.md` for a scoped item known to lack assets
2. Confirm protocol continues without failing for missing assets

**Expected result**: Assets skipped silently; run continues.

---

## Assertions Checklist

- [ ] Primary and alias surfaces exist on Cursor, Claude, and Codex paths
- [ ] Disallowed base stops without testing
- [ ] Scope helper is read-only and confirmation is required
- [ ] Empty scope stops cleanly
- [ ] Preflight asks when runnable environment is missing
- [ ] Clean docs-only path creates neither fix PR nor backlog item
- [ ] Missing design assets do not fail the run

---

## Seed Data

Not applicable — workflow documentation / helper validation only.
