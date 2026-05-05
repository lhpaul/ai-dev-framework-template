# Attempt Tracking for Reviewer Loop Prompts — Implementation Plan

**Spec**: [`1_448-attempt-tracking-reviewer-loop_specs.md`](./1_448-attempt-tracking-reviewer-loop_specs.md)
**Smoke test runbook**: [`../../testing/workflow/448-attempt-tracking-reviewer-loop.smoke-test.md`](../../../testing/workflow/448-attempt-tracking-reviewer-loop.smoke-test.md)

---

## Summary

**Approach**: Add an attempt-context injection rule to the fixer agent dispatch section of Protocol 91 (Step 7) and Protocol 93. On the first fixer dispatch (cycle = 1) the prompt is unchanged. On each retry (cycle ≥ 2) the orchestrator prepends a structured header — "Attempt N/M:" followed by one-to-two-sentence summaries of what prior attempts addressed and what findings remain open — before the standard blocking-findings list. The attempt summaries are derived from the orchestrator's existing PR feedback ledger and fixer response, live in in-session state only, and are discarded when the orchestration session ends.

**Estimated complexity**: S

**Rationale**: The change is documentation-only — two markdown protocol files. No scripts, no code, no database changes. The fixer dispatch section in both Protocol 91 Step 7 and Protocol 93 needs a new subsection describing the injection rule and the required prompt format. The existing cycle counter and PR feedback ledger (already tracked in the protocol) are the only data sources required; no new state structures are needed.

**Dependencies**: None

---

## Verification Log

| Check | Command / query | Result |
|---|---|---|
| Repo revision | `git rev-parse --short HEAD` | `1ab1488` |
| Files that define fixer dispatch in Protocol 91 | `grep -n "Fixer agent batching rule\|dispatch.*fixer\|needs_fixes.*cycle" docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` | Lines 766, 895, 933–944 (fixer batching rule block, `needs_fixes` dispatch table, loop parameters) |
| Files that define fixer dispatch in Protocol 93 | `grep -n "Fixer agent batching rule\|dispatch.*fixer" docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md` | Lines 117–129 (fixer batching rule block) |
| Protocol 91 line count | `wc -l docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` | 1385 |
| Protocol 93 line count | `wc -l docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md` | 286 |
| Other agents/skills referencing these protocols | `grep -rl "91-orchestrate-work-protocol\|93-automated-reviewer-loop" .claude/agents/ .cursor/agents/ .codex/skills/ 2>/dev/null` | Results include `.claude/agents/automated-reviewer-loop.md`, `.cursor/agents/automated-reviewer-loop.md`, `.claude/agents/item-orchestrator.md`, `.cursor/agents/item-orchestrator.md` — these reference the protocols by pointer only; the injection rule lives in the protocols themselves, so the agent files do not need updating |

---

## Layer-by-Layer Changes

### Protocol / Documentation Layer

- [ ] **`docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` — Step 7 fixer dispatch**: Add a new subsection `### Attempt-context injection rule (Step 7 fixer dispatch)` immediately after the existing `### Fixer agent batching rule (mandatory)` block. The subsection must document:
  - When to inject (cycle ≥ 2 only; cycle = 1 is unchanged)
  - How to derive per-attempt summaries from the PR feedback ledger and fixer response
  - The required prompt format for cycle ≥ 2
  - The fallback format when no prior-attempt summary is available
  - How to accumulate summaries across multiple retries
  - The rule that the attempt-context prefix is prepended and does not replace the standard blocking-findings list
- [ ] **`docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md` — fixer dispatch section**: Add the same `### Attempt-context injection rule` subsection in the matching location (after `### Fixer agent batching rule (mandatory)`) with identical content, so the standalone reviewer loop path is covered (AC-8, AC-9 both require documentation in both protocols)

---

## Testing Strategy

**Test types**: Manual / smoke (protocol review is the verification mechanism — no automated test for documentation changes)

**Key scenarios to test**:

1. First dispatch (cycle = 1) — prompt has no attempt-context prefix (maps to AC-1)
2. First retry (cycle = 2) — prompt begins with "Attempt 2/M:" plus prior-attempt summary and remaining findings (maps to AC-2, AC-3, AC-4, AC-5)
3. Multi-retry (cycle ≥ 3) — prompt accumulates all prior-attempt summaries, not only the most recent (maps to Use Case 3, AC-5)
4. Fallback path — when no prior-attempt summary is available, minimal "Attempt N/M: prior attempt did not fully resolve all findings" message is used (maps to Use Case 1 Considerations, AC-5)
5. Reappearance — when a finding reappeared after a prior fix, the summary notes the reappearance explicitly (maps to AC-6)
6. Prefix additive — the attempt-context prefix is in addition to, not a replacement of, the blocking-findings list (maps to AC-7)

**Smoke test runbook**: `docs/testing/workflow/448-attempt-tracking-reviewer-loop.smoke-test.md`

---

## Seed Data

None — this is a documentation-only change with no application data requirements.

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` — Updated as the primary implementation file (see Layer-by-Layer Changes)
- [ ] `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md` — Updated as a secondary implementation file (see Layer-by-Layer Changes)

No other project docs in `docs/project/`, `docs/best-practices/`, or `AGENTS.md` are affected. The change is scoped to the reviewer loop protocols.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Attempt-context prompt grows too long for large max_cycles values | Low | Med | Spec mandates one-to-two sentences per attempt summary; plan enforces this in the documented format |
| Fixer agent ignores the attempt-context prefix | Low | Med | The prefix is informational context only; the standard blocking-findings list is unchanged and the agent still has all findings to work from |
| Protocol 93 diverges from Protocol 91 over time | Low | Med | Both are updated in the same PR so they are in sync at merge; future editors are advised by the subsection header that this rule mirrors Protocol 91 Step 7 |

---

## Code Samples

> All samples below are illustrative — adapt during implementation.

### Attempt-context injection rule (illustrative format for the protocol text)

The following shows the content to add to the `### Attempt-context injection rule` subsection in both Protocol 91 and Protocol 93. It is marked illustrative; the developer must adapt prose, headings, and formatting to match the surrounding document style.

```markdown
<!-- Illustrative — adapt during implementation -->
### Attempt-context injection rule (Step 7 fixer dispatch)

This rule governs what the orchestrator prepends to the fixer agent's prompt on each
dispatch. It applies to fixer agents dispatched from this step only (Step 7 external
automated reviewers); Step 7a (internal review gate) fixer cycles are unaffected.

**First dispatch (cycle = 1)**

No attempt-context prefix is added. The fixer receives only the standard
blocking-findings list and the batching rule above.

**Retry dispatches (cycle ≥ 2)**

Before dispatching the fixer, the orchestrator prepends an attempt-context header
to the fixer's prompt using the following format:

> Attempt N/M: prior attempt(s) tried [per-attempt summaries]. The following findings
> remain open: [standard blocking-findings list]. Try a different approach for each
> remaining finding.

Where:
- `N` = the current `cycle` value (matches the loop's `cycle` counter exactly)
- `M` = `max_cycles` (the loop escalation limit — default: 10)
- `[per-attempt summaries]` = one entry per prior dispatch, each one-to-two plain-language
  sentences describing what that attempt changed and which findings it addressed or left
  open. Derive each entry from the PR feedback ledger and the fixer's commit message /
  response for that cycle.
- `[standard blocking-findings list]` = the same findings list passed in any dispatch —
  the attempt-context prefix does not replace it

**Accumulating summaries across retries**

For cycle N, include summaries for all N-1 prior attempts, not only the most recent.
Each entry should be keyed to its cycle number for clarity:

> Attempt 1: rewrote the `foo()` function signature in `bar.sh`; MD009 trailing-space
> finding on line 42 remained open.
> Attempt 2: removed trailing space on line 42; `relative-links` finding on `baz.md`
> remained open.

**Fallback when no prior-attempt summary is available**

If no summary was recorded for a prior attempt (e.g., the fixer did not respond or
the attempt had no ledger entries), use the minimal fallback:

> Attempt N/M: prior attempt did not fully resolve all findings. Try a different approach.

**Reappearance notation**

When a finding that was marked `resolved` in a prior cycle reappears in the current
ledger (same `(platform, path, body_snippet)` key, status reverted to `open`), the
per-attempt summary for the cycle in which it was "resolved" must note the reappearance:

> Attempt 2: removed trailing space on line 42 (fix did not hold — finding reappeared
> in cycle 3).

**In-session state only**

Attempt summaries live in the orchestrator's in-session state for the duration of the
PR's review loop. They are not persisted to disk or to any external tracker. They are
discarded when the orchestration session ends.
```

---

## Implementation Order

1. **Read both target files** — read the complete text of `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` and `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md` before making any edits. Confirm the exact line after the `### Fixer agent batching rule (mandatory)` block in each file where the new subsection will be inserted.

2. **Add `### Attempt-context injection rule` subsection to Protocol 91** — insert the new subsection immediately after the closing lines of the `### Fixer agent batching rule (mandatory)` block (i.e., after the closing `>` blockquote and before `### Loop parameters`). The subsection must cover all items listed in the Layer-by-Layer Changes section and must match the illustrative format in the Code Samples section. Verify after editing that the section appears between the fixer batching rule and the loop parameters table.

3. **Add `### Attempt-context injection rule` subsection to Protocol 93** — insert the identical subsection in the matching location in Protocol 93: immediately after the closing lines of the `### Fixer agent batching rule (mandatory)` block. The subsection header should note that this rule mirrors Protocol 91 Step 7 to aid future maintenance. Verify after editing that the section appears in the correct position.

4. **Cross-section consistency self-check** — confirm that:
   - The cycle counter variable name (`cycle`) is consistent across both files and matches the existing usage in the loop parameters sections
   - The `max_cycles` constant name is consistent with existing usage
   - The prompt format uses the same `N/M` notation in both files
   - The fallback phrase is identical in both files

5. **Pre-commit markdown lint** — run `markdownlint-cli2` on both modified files:

   ```bash
   REPO_ROOT=$(git rev-parse --git-common-dir)/..
   "$REPO_ROOT/node_modules/.bin/markdownlint-cli2" \
     "docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md" \
     "docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md"
   ```

   Fix any reported violations (trailing spaces, missing trailing newline, broken relative links) before committing.

6. **Pre-commit smoke test runbook lint** — run `markdownlint-cli2` on the smoke test runbook:

   ```bash
   REPO_ROOT=$(git rev-parse --git-common-dir)/..
   "$REPO_ROOT/node_modules/.bin/markdownlint-cli2" \
     "docs/testing/workflow/448-attempt-tracking-reviewer-loop.smoke-test.md"
   ```

7. **Commit** — `docs: add attempt-context injection rule to reviewer loop fixer dispatch (#448)`

8. **Verify smoke test runbook scenarios** — confirm each scenario in the runbook can be traced to a specific acceptance criterion in the spec and a specific line in the updated protocol text.

9. **Update `CHANGELOG.md`** under `[Unreleased]` — add:

   ```
   - **Add attempt tracking to reviewer loop prompts** (#448): Fixer agents dispatched on retry (cycle ≥ 2) now receive an attempt-context prefix in their prompt summarising what prior attempts addressed and what findings remain open, enabling them to avoid repeating failing approaches and converge faster.
   ```
