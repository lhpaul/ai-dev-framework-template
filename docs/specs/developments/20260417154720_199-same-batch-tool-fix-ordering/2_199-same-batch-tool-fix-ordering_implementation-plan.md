# Same-Batch Tool-Fix Ordering Hazard Detection — Implementation Plan

**Spec**: [1_199-same-batch-tool-fix-ordering_specs.md](1_199-same-batch-tool-fix-ordering_specs.md)
**Smoke test runbook**: [docs/testing/workflow/199-same-batch-tool-fix-ordering.smoke-test.md](../../../testing/workflow/199-same-batch-tool-fix-ordering.smoke-test.md)

---

## Summary

**Approach**: Extend `scripts/development-workflow/workflow-batch-plan.sh` to classify each
candidate development folder as a tool-fix item by scanning its spec/plan document for references
to the canonical tool file set, then emit `TOOL_FIX=yes|no|unknown` and (when yes)
`TOOL_FIX_FILES=<comma-separated paths>` per item. Update Protocol 90 Step 3 to define the
same-batch tool-fix ordering hazard, the serialize-first rule, the multiple-tool-fix-item
ordering rule, the human override path, and the tracker-derived conservative override — so the
orchestrator has a documented, machine-readable basis for holding consumer items until every
tool-fix item has been merged.

**Estimated complexity**: S

**Rationale**: The changes are confined to two artifacts — one shell script and one protocol
document. The shell script change is a pattern-matching loop against a fixed file list; no new
external dependencies are introduced. The protocol change is purely additive documentation within
the existing Step 3 structure.

**Dependencies**: None

---

## Layer-by-Layer Changes

### Scripts / Workflow Tooling

- [ ] In `scripts/development-workflow/workflow-batch-plan.sh`, add a helper function
  `classify_tool_fix` that:
  1. Accepts a development folder path.
  2. Locates the spec or plan document inside that folder (any `*.md` file in the folder; if
     none exists, returns `unknown`).
  3. Scans the document for exact occurrences of each path in the canonical tool file list (see
     Business Rules in the spec). **"Exact path match" means the path must be delimited — it
     starts and ends on a token boundary (start-of-line, whitespace, or a punctuation character
     that is not part of the path). A naive `grep -F` (fixed-string) search does substring
     matching and will incorrectly report a hit for a superstring like `pr-review-loop.sh.bak`.**
     Implement with a delimiter-aware matcher, for example:
     - `grep -qE "(^|[^[:alnum:]_./-])${path_regex}([^[:alnum:]_./-]|\$)" "$doc_file"` where
       `path_regex` is the canonical path with regex metacharacters escaped (or use `grep -P`
       with `\Q...\E`), **or**
     - `grep -oF "$path" "$doc_file"` followed by a match-length equality check against the
       canonical path length (rejects superstring hits).

     The chosen strategy must ensure `pr-review-loop.sh` does **not** match
     `pr-review-loop.sh.bak`, and the protocols glob does not match `.md.bak`.
  4. For the glob `docs/workflow/development-workflow/protocols/*.md`, match lines that contain a
     path starting with `docs/workflow/development-workflow/protocols/` and ending with `.md` at a
     path-segment boundary. The regex must anchor on both sides of the matched filename to
     reject superstrings — for example
     `(^|[^[:alnum:]_./-])docs/workflow/development-workflow/protocols/[^/[:space:]]+\.md([^[:alnum:]_./-]|$)`
     — so `foo.md.bak` or a filename embedded in a longer identifier does not incorrectly match.
  5. Collects all matched canonical paths into a comma-separated list.
  6. Emits `TOOL_FIX=yes` and `TOOL_FIX_FILES=<list>` when at least one canonical path is
     matched, `TOOL_FIX=no` when none are matched, or `TOOL_FIX=unknown` when no spec/plan
     document exists.

- [ ] In `workflow-batch-plan.sh`, call `classify_tool_fix` for each development path **before**
  the `workflow-next-action.sh` call (i.e., between the `slug=` computation and the
  `if ! next_action_output=...` guard, currently around lines 75–76). Running it earlier
  ensures `TOOL_FIX` is emitted even for directories without spec/plan files — where
  `workflow-next-action.sh` exits non-zero and the current code `continue`s silently. When
  `workflow-next-action.sh` fails, replace the bare `continue` with an abbreviated output
  block that emits `TARGET`, `DEVELOPMENT_PATH`, `SLUG`, and the TOOL_FIX line(s) before
  continuing to the next path. This keeps spec AC 13 (`TOOL_FIX=unknown` for directories
  without spec/plan documents) satisfiable. Emit rules for the TOOL_FIX lines (applies in
  both the happy path and the next-action-failed path):
  - `print_kv TOOL_FIX "$tool_fix"` always.
  - `print_kv TOOL_FIX_FILES "$tool_fix_files"` only when `TOOL_FIX=yes` (omit the line
    entirely for `no` and `unknown` to keep output compact).

- [ ] The canonical tool file list to match against (exact string for each, checked with
  `grep -qF` individually, plus the glob-equivalent grep for the protocols directory):
  - `scripts/development-workflow/pr-review-loop.sh`
  - `scripts/development-workflow/pr-ci-loop.sh`
  - `scripts/development-workflow/batch-merge.sh`
  - `scripts/development-workflow/post-merge-cleanup.sh`
  - `docs/workflow/development-workflow/protocols/` (prefix match ending with `.md` — covers any
    protocol file in the directory)
  - `.ai-dev-workflow.yaml`

### Protocol Documentation

- [ ] In `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`
  **Step 3**, add a new subsection **"Same-batch tool-fix ordering hazard"** (placed after the
  existing "Do not batch together" list and before the "Codex fallback" paragraph). The
  subsection must cover all of the following, mapping directly to the spec's acceptance criteria:

  1. **Definition**: what a tool-fix item is — references modifications to any file in the
     canonical tool file list (same list as in the spec Business Rules, reproduced verbatim in
     the protocol).

  2. **Detection sources**: `workflow-batch-plan.sh` emits `TOOL_FIX=yes|no|unknown` based on
     spec/plan document evidence. The orchestrator may additionally classify from tracker
     title/description. If tracker-derived classification conflicts with script output (script
     says `no` but tracker title/description references a tool file), the orchestrator takes the
     conservative path and treats the item as a hazard candidate.

  3. **Serialize-first rule**: when a tool-fix item and any non-tool-fix item appear in the
     same candidate batch and the non-tool-fix item is not already `ready-for-human-review`,
     the tool-fix item must be dispatched alone in its own serial sub-batch first. The
     remaining consumer items are held until the tool-fix PR is merged.

  4. **`TOOL_FIX=unknown` handling**: treat `unknown` the same as `yes` — apply the
     serialize-first strategy (conservative default).

  5. **Multiple tool-fix items**: when two or more tool-fix items appear in the same candidate
     batch, each is serialized into its own sub-batch dispatched one at a time. Ordering among
     multiple tool-fix items follows the standard priority order — due date within 2 weeks
     (earliest first), then priority (Urgent → High → Normal → Low), then creation date
     (earliest first).

  6. **Already-waiting tool-fix**: if the tool-fix item is already `ready-for-human-review`,
     `Spec in Review`, or `Plan in Review` (already waiting for merge), the orchestrator
     reports it as a "pending tool-fix" blocker and holds consumer items without redispatching
     the tool-fix.

  7. **Human override**: the orchestrator must never autonomously skip the serialize-first gate.
     Only an explicit human instruction enables parallel dispatch when an ordering hazard has
     been detected. When a human instructs override, the orchestrator logs it and annotates the
     batch summary with a warning.

  8. **Summary annotation**: the batch summary (Step 6) must identify held consumer items and
     their reason ("held — pending tool-fix merge for item #N").

  **Important scope constraints**:
  - Do NOT modify Step 5.1 (Post-Dispatch PR Verification) — that section remains unchanged.
  - Do NOT modify any other step in Protocol 90 or any other protocol file.

---

## Testing Strategy

**Test types**: Manual / Smoke

**Key scenarios to test**:

1. `workflow-batch-plan.sh` against a folder whose spec references `pr-review-loop.sh` →
   `TOOL_FIX=yes`, `TOOL_FIX_FILES` contains exact path (maps to AC 1).
2. `workflow-batch-plan.sh` against a folder whose spec references `pr-ci-loop.sh` →
   `TOOL_FIX=yes`, `TOOL_FIX_FILES` contains exact path (maps to AC 2).
3. `workflow-batch-plan.sh` against a folder whose spec references a protocol `.md` file →
   `TOOL_FIX=yes`, `TOOL_FIX_FILES` contains exact matched protocol path (maps to AC 3).
4. `workflow-batch-plan.sh` against a folder whose spec references `batch-merge.sh` →
   `TOOL_FIX=yes` (maps to AC 4).
5. `workflow-batch-plan.sh` against a folder whose spec references `post-merge-cleanup.sh` →
   `TOOL_FIX=yes` (maps to AC 5).
6. `workflow-batch-plan.sh` against a folder whose spec references `.ai-dev-workflow.yaml` →
   `TOOL_FIX=yes` (maps to AC 6).
7. `workflow-batch-plan.sh` against a folder with no workflow tool references → `TOOL_FIX=no`
   (explicit `no`, not omitted) (maps to AC 7).
8. `workflow-batch-plan.sh` against a folder with no spec/plan document → `TOOL_FIX=unknown`
   (maps to AC 13).
9. Protocol 90 Step 3 contains the "same-batch tool-fix ordering hazard" subsection with all
   required content (maps to ACs 8–12, 14).

**Smoke test runbook**: [`docs/testing/workflow/199-same-batch-tool-fix-ordering.smoke-test.md`](../../../testing/workflow/199-same-batch-tool-fix-ordering.smoke-test.md)

---

## Seed Data

None. All tests use development folder fixtures created during smoke testing.

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` — updated
  as part of this implementation (Step 3 additive subsection). No separate post-implementation
  doc update needed beyond what the plan steps cover.

Other docs in `docs/project/`, `docs/best-practices/`, and `AGENTS.md` are not affected — this
change modifies only tooling internals and the orchestration protocol.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| `grep -F` exact-path matching for the protocols glob produces false negatives for valid protocol paths | Low | Medium | Use a two-part grep: fixed-string prefix `docs/workflow/development-workflow/protocols/` combined with a pattern requiring `.md` suffix; test against known fixtures |
| Protocol 90 Step 3 wording introduces an ambiguity about what "already waiting for merge" means | Low | Low | Use the exact status names from the spec (`ready-for-human-review`, `Spec in Review`, `Plan in Review`) in the protocol text |
| `TOOL_FIX_FILES` line omitted for `no`/`unknown` confuses orchestrator parsers that expect it | Low | Low | Document explicitly in Step 3 that the line is only emitted when `TOOL_FIX=yes`; parsers must treat a missing `TOOL_FIX_FILES` as an empty set |

---

## Code Samples

```bash
# Illustrative — adapt during implementation

CANONICAL_EXACT_PATHS=(
  "scripts/development-workflow/pr-review-loop.sh"
  "scripts/development-workflow/pr-ci-loop.sh"
  "scripts/development-workflow/batch-merge.sh"
  "scripts/development-workflow/post-merge-cleanup.sh"
  ".ai-dev-workflow.yaml"
)
PROTOCOLS_PREFIX="docs/workflow/development-workflow/protocols/"

classify_tool_fix() {
  local dev_path="$1"
  local doc_file matched_paths tool_fix

  # Find ALL spec and plan markdown documents in the folder (spec is 1_*_specs.md, plan is
  # 2_*_implementation-plan.md). Scan every file, not just the first — a tool-fix reference
  # may appear only in the implementation plan, and scanning only the spec would miss it.
  local doc_files=()
  while IFS= read -r f; do
    doc_files+=("$f")
  done < <(find "$dev_path" -maxdepth 1 -name '*.md' | sort)
  if [ "${#doc_files[@]}" -eq 0 ]; then
    printf 'unknown\n'
    return 0
  fi

  matched_paths=()

  # DELIMITER BOUNDARY RATIONALE: `grep -F` does substring matching, so a naive
  # `grep -qF "$path"` would match `scripts/development-workflow/pr-review-loop.sh` against
  # a line containing `pr-review-loop.sh.bak`. We use an extended regex with explicit
  # non-path-character boundaries on both sides to reject superstrings.
  local boundary_lead='(^|[^[:alnum:]_./-])'
  local boundary_trail='([^[:alnum:]_./-]|$)'

  for path in "${CANONICAL_EXACT_PATHS[@]}"; do
    # Escape regex metacharacters in the canonical path (dots, dashes, slashes are already
    # safe; escape any characters that might appear if the canonical list grows).
    local path_regex
    path_regex="$(printf '%s' "$path" | sed 's/[][\\.^$*+?(){}|]/\\&/g')"
    if grep -qE "${boundary_lead}${path_regex}${boundary_trail}" "${doc_files[@]}"; then
      matched_paths+=("$path")
    fi
  done

  # Glob-equivalent: any docs/workflow/development-workflow/protocols/*.md reference, anchored
  # on both sides to reject .md.bak and other superstrings.
  local protocols_regex="${boundary_lead}${PROTOCOLS_PREFIX}[^/[:space:]]+\\.md${boundary_trail}"
  if grep -qE "$protocols_regex" "${doc_files[@]}"; then
    while IFS= read -r match; do
      matched_paths+=("$match")
    done < <(grep -hoE "${PROTOCOLS_PREFIX}[^/[:space:]]+\\.md" "${doc_files[@]}" | sort -u)
  fi

  if [ "${#matched_paths[@]}" -gt 0 ]; then
    tool_fix="yes"
    local IFS=','
    printf '%s\n' "yes" "${matched_paths[*]}"
  else
    printf '%s\n' "no"
  fi
}
```

---

## Implementation Order

1. Read `scripts/development-workflow/workflow-batch-plan.sh` and `workflow-lib.sh` in full.
2. Add `classify_tool_fix` helper function to `workflow-batch-plan.sh` using the canonical
   path list from the spec Business Rules. Place the function after the existing helper
   functions (`batch_hint_for_action`, `parallel_safe_for_action`) and before `cd_workflow_repo_root`.
3. In the main `for development_path` loop, call `classify_tool_fix` and capture its output.
   Emit `TOOL_FIX=<value>` using `print_kv`. When `TOOL_FIX=yes`, also emit
   `TOOL_FIX_FILES=<comma-separated matched paths>` using `print_kv`.
4. Read `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` Step 3
   in full, identify the exact insertion point (after "Do not batch together" list, before
   "Codex fallback" paragraph).
5. Insert the **"Same-batch tool-fix ordering hazard"** subsection at that location, covering
   all seven content requirements listed in the Protocol Documentation layer above.
6. Verify acceptance criteria manually using the smoke test runbook scenarios (lightweight
   fixture-based checks; no running application needed).
7. Update `CHANGELOG.md` under `[Unreleased]` with a concise entry describing the new
   tool-fix hazard detection.
