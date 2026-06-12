# Protocol: Resolve Epic Execution Scope

**Agent role**: Epic Scope Resolver (`run-epic`)
**Purpose**: Convert a native GitHub epic or explicit item list into a read-only execution set before delegated orchestration begins

This is a **resolver protocol**, not an implementation protocol. It exists to
make scoped multi-item work explicit before an agent starts specs, plans,
branches, PRs, tracker updates, reviewer loops, merges, or cleanup.

---

## Overview

Use this protocol when a human invokes `/run-epic`, `$run-epic`, or asks to run
an epic / bounded item list as a delegated workflow batch.

The resolver supports exactly one scope source:

```bash
./scripts/development-workflow/run-epic-scope-resolver.sh --epic <issue-number>
./scripts/development-workflow/run-epic-scope-resolver.sh --items <issue-number>[,<issue-number>...]
```

Optional flags:

- `--base <branch>`: override base-branch inference.
- `--json`: emit machine-readable output for an orchestrator handoff.

The resolver is read-only. It must not update tracker status, create branches,
open or edit PRs, merge PRs, close issues, or delete branches.

---

## Step 1: Validate Scope Input

Require exactly one of:

- `--epic <issue-number>`
- `--items <issue-number>[,<issue-number>...]`

Issue numbers must be positive integers. Reject empty values, zero, non-numeric
tokens, and mixed `--epic` plus `--items` invocations before any repository or
tracker lookup.

Explicit item lists are exact. Do not expand siblings, parent epics, labels, or
linked issues from an explicit list. Duplicate item numbers may be collapsed.

---

## Step 2: Resolve Epic Children

For `--epic`, read native GitHub sub-issues using GraphQL pagination.

Required behavior:

- Read all pages of `subIssues`.
- Verify the child-side parent relationship when GitHub exposes it.
- If the epic has no native sub-issues, report an empty scope clearly.
- Do not fall back to integration branch labels as an epic membership source.
  Labels remain routing metadata, not membership metadata.

---

## Step 3: Enrich Each Item

For each in-scope item, collect best-effort read-only metadata:

- Issue number, title, and open / closed state.
- Labels, including any `integration-branch:<slug>` label.
- Project Status, Type, and Priority when available.
- Dependency signal from issue body references such as `Depends on #123`.
- Linked open or merged PRs whose branch names match the item number.

If a metadata read fails for one item, keep the item in the result as
`ambiguous` with a short reason instead of silently dropping it.

---

## Step 4: Infer Base Branch

Use this precedence:

1. Supplied `--base <branch>`.
2. One shared `integration-branch:<slug>` label across in-scope items, resolved
   as `develop-<slug>`.
3. No integration label, resolved as `develop`.
4. Conflicting integration labels, resolved as ambiguous unless `--base` is
   supplied.

When conflicting integration labels are ambiguous, every item in the result is
ambiguous. A later mutating workflow must stop until a human supplies `--base`
or narrows the scope.

---

## Step 5: Group Items

Assign each item to one group:

- `eligible`: no known blocker, no ready/open review PR, and not already merged.
- `blocked`: dependency signal points to an open dependency.
- `already_merged`: tracker status, issue state, or merged PR indicates the work
  is already complete.
- `in_review`: tracker status or open PR indicates the item is waiting for review
  or merge.
- `ambiguous`: missing / conflicting data prevents a deterministic next action.
- `out_of_scope`: reserved for consumers that compare resolver output against a
  later bounded handoff.

Do not mutate anything based on these groups. The resolver only describes the
execution set.

---

## Step 6: Handoff

Print:

- Scope source and item count.
- Base branch and inference reason.
- Read-only guarantee.
- Grouped item list with issue number, title, status, type, and issue state.

When `--json` is supplied, emit valid JSON containing the same fields plus the
full item metadata. Downstream orchestrators must treat this JSON as the bounded
scope contract and must not opportunistically mutate items outside it.
