# Async/Concurrency Safety Checklist — Implementation Plan

**Spec**: [1_348-async-concurrency-safety-checklist_specs.md](./1_348-async-concurrency-safety-checklist_specs.md)
**Smoke test runbook**: N/A — out of scope per spec (workflow documentation only, no application behavior)

---

## Summary

**Approach**: Add a new conditional async/concurrency safety checklist block to two workflow documents. In `02-generate-implementation-plan-protocol.md`, the block is appended to Step 3 as a peer of the existing "Parser-risk plans" section, following the same conditional-guidance pattern. In `REVIEW.md`, the block is added to the Code Review Checklist as a new "Additional checks" paragraph, parallel to the existing "Additional checks for shell scripts" and "Additional checks for database migrations" entries.

**Estimated complexity**: S

**Rationale**: Both changes are purely additive documentation edits to two existing markdown files. No code changes, no database, no UI, no infrastructure. The structure and wording patterns are already established in both files — this is a documentation-only expansion.

**Dependencies**: None

---

## Verification Log

| Check | Command / query | Result |
|---|---|---|
| Repo revision | `git rev-parse --short HEAD` | `0039ddb` |
| Files to change | `ls docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md REVIEW.md` | Both files present |
| Parser-risk section line in plan protocol | `grep -n "Parser-risk plans" docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md` | Line 109 — existing conditional block to mirror |
| Additional checks in REVIEW.md | `grep -n "Additional checks for" REVIEW.md` | Lines 137 (shell scripts) and 143 (database migrations) — new block appended after line 144 |

---

## Layer-by-Layer Changes

### Workflow Documentation

- [ ] `docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md` — add a new conditional "Concurrent-event-source plans" block to Step 3, immediately after the "Parser-risk plans" block (after line 138, before "### Examples"). The block follows the same structural pattern as the parser-risk block: a classification trigger, a "skip if not applicable" escape, and mandatory checklist items.

- [ ] `REVIEW.md` — add a new "Additional checks for **features with concurrent event sources**" paragraph to the Code Review Checklist section, immediately after the "Additional checks for database migrations" block (after line 144, before "Typical `blocking` issues"). The block follows the same structural pattern as the existing additional-checks paragraphs.

---

## Testing Strategy

**Test types**: Manual review (documentation-only change; no automated tests apply)

**Key scenarios to test**:
1. A tech lead writing a plan for a feature with concurrent event sources reads the protocol and finds the new checklist — maps to AC-1, AC-3, AC-4, AC-6
2. A code reviewer reviewing a PR with shared mutable state reads `REVIEW.md` and applies the new conditional checklist — maps to AC-2, AC-3, AC-4, AC-5
3. Both documents use the same terminology for each checklist item — maps to AC-7

**Smoke test runbook**: not applicable — this feature is explicitly out of scope for smoke test runbook updates (see spec Out of Scope section)

---

## Seed Data

None — documentation-only change; no seed data required.

---

## Documentation Updates

None — the files being changed (`02-generate-implementation-plan-protocol.md` and `REVIEW.md`) are the target workflow documentation for this feature. No further documentation updates are needed after implementation.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| New checklist block breaks relative-link or trailing-whitespace lint | Low | Low | Run `markdownlint-cli2` on both files before committing |
| Wording divergence between the two documents causes confusion (violates AC-7) | Low | Medium | Cross-read both checklists before committing; use the same term list from the spec (BR-5 and AC-3) |
| Block placement disrupts existing structure | Low | Low | Insert after last existing "Additional checks" paragraph; use a blank line before and after per file convention |

---

## Implementation Order

1. **Add the async/concurrency safety block to `02-generate-implementation-plan-protocol.md`**

   In Step 3, after the closing line of the "Parser-risk plans" block (the reference to the 201 spec), insert the following new section before `### Examples`:

   ```markdown
   ### Concurrent-event-source plans: async and concurrency safety

   Treat this block as conditional guidance. Apply it only when the plan introduces or modifies code with two or more concurrent event sources (e.g., real-time data listeners, network socket callbacks, timers or scheduled callbacks) that share mutable state.

   **Classification (concurrent-event-source):** classify a plan as concurrent-event-source when the Layer-by-Layer changes involve any of the following:

   - Two or more event listeners, socket callbacks, timers, or async queues that can execute concurrently
   - Shared mutable state (variables, collections, counters, caches) that multiple execution contexts can read or write
   - Initialization or teardown sequences that race with incoming events

   If none of these signals apply, skip this entire block.

   **Mandatory when concurrent-event-source — Checklist:** include a dedicated concurrency safety section in the plan. For each item below, document the design decision when the item applies, or note "not applicable" with a brief rationale:

   - **Shared mutable state guards**: how is shared state protected from concurrent reads/writes? (e.g., access serialized through a single async queue, ownership transferred on each event, copy-on-update)
   - **Re-entrancy / in-flight tracking**: can a second event arrive before the handler for the first event finishes? If yes, how is in-flight state tracked and new arrivals handled?
   - **Event deduplication**: can the same logical event fire more than once (e.g., reconnect triggers, duplicate callbacks)? If yes, how is deduplication handled?
   - **Listener and resource cleanup**: how are all registered listeners, timers, and handles removed when the feature is torn down or the component unmounts? What happens to in-flight operations at teardown?
   - **Race conditions at initialization**: can events arrive before initialization completes? If yes, what happens to those events?
   - **Race conditions at teardown**: can events arrive after teardown begins? If yes, how are they discarded or drained safely?
   - **Error propagation across async boundaries**: how are errors from async callbacks surfaced? Are unhandled rejections or uncaught exceptions in callbacks visible to the caller or swallowed silently?

   **Conditional — new concurrent patterns:** if the feature introduces concurrent event handling patterns not previously used in this codebase, note this explicitly and identify any architectural decisions that differ from existing patterns.
   ```

   Verify: open the file and confirm the new block appears between the parser-risk reference line and `### Examples`, with blank lines above and below.

2. **Add the async/concurrency safety block to `REVIEW.md`**

   In the Code Review Checklist section, after the "Additional checks for database migrations" block (after the trigger/backfill parity bullet), insert the following before "Typical `blocking` issues":

   ```markdown
   Additional checks for **features with concurrent event sources** (when the PR introduces or modifies code where multiple execution contexts — listeners, timers, callbacks, async queues — can access shared mutable state):
   - **Shared mutable state guards**: shared state is protected from concurrent reads/writes by a consistent access pattern (e.g., serialized queue, ownership transfer, copy-on-update)
   - **Re-entrancy / in-flight tracking**: the handler correctly tracks or rejects concurrent in-flight operations when a second event can arrive before the first completes
   - **Event deduplication**: duplicate logical events (e.g., reconnect triggers, repeated callbacks) are deduplicated or idempotent
   - **Listener and resource cleanup**: all registered listeners, timers, and handles are removed at teardown; in-flight operations are drained or discarded safely
   - **Race conditions at initialization**: events that arrive before initialization completes are handled correctly (queued, dropped, or deferred with correct sequencing)
   - **Race conditions at teardown**: events that arrive after teardown begins are discarded or drained without causing errors or accessing freed state
   - **Error propagation across async boundaries**: errors from async callbacks are surfaced to the caller; unhandled rejections or uncaught exceptions in callbacks do not silently swallow failures
   ```

   Verify: open the file and confirm the new block appears between the database migrations block and "Typical `blocking` issues", with blank lines above and below, and that the seven checklist items use the same terms as in the plan protocol.

3. **Cross-read both documents for terminology consistency (AC-7)**

   Open both files side by side and verify:
   - Each of the seven checklist items appears in both documents under the same name
   - The trigger condition wording is consistent ("two or more concurrent event sources", "shared mutable state", "concurrent event sources")
   - No term defined in one document is missing or renamed in the other

4. **Run `markdownlint-cli2` on both modified files**

   ```bash
   REPO_ROOT=$(git rev-parse --git-common-dir)/..
   "$REPO_ROOT/node_modules/.bin/markdownlint-cli2" \
     "docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md" \
     "REVIEW.md"
   ```

   Fix any reported violations (trailing spaces, broken relative links, missing trailing newline) before committing.

5. **Update `CHANGELOG.md` under `[Unreleased]`**

   ```markdown
   - **Add async/concurrency safety checklist to plan protocol and review contract** (#348): adds a conditional async/concurrency safety checklist to `02-generate-implementation-plan-protocol.md` (triggered when a plan has concurrent event sources) and a matching conditional additional-checks block to `REVIEW.md` (triggered when a PR introduces or modifies concurrent event source code). Covers shared mutable state guards, re-entrancy / in-flight tracking, event deduplication, listener cleanup, initialization/teardown race conditions, and error propagation across async boundaries.
   ```

6. **Commit all changes**

   Stage and commit `02-generate-implementation-plan-protocol.md`, `REVIEW.md`, and `CHANGELOG.md` together:

   ```bash
   git add docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md REVIEW.md CHANGELOG.md
   git commit -m "docs: add async/concurrency safety checklist to plan protocol and REVIEW.md (#348)"
   ```
