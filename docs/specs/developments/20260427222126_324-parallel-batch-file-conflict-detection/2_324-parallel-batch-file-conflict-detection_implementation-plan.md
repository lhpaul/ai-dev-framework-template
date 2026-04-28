# Parallel Batch File-Level Conflict Detection — Implementation Plan

**Spec**: [1_324-parallel-batch-file-conflict-detection_specs.md](1_324-parallel-batch-file-conflict-detection_specs.md)
**Smoke test runbook**: [docs/testing/workflow/324-parallel-batch-file-conflict-detection.smoke-test.md](../../../testing/workflow/324-parallel-batch-file-conflict-detection.smoke-test.md)

---

## Summary

**Approach**: Extend `scripts/development-workflow/workflow-batch-plan.sh` to extract the
declared file set from each implementation item's plan document and emit it as
`FILE_SET=<comma-separated paths>` (or `FILE_SET=unknown` when extraction fails). Add a
`detect_file_conflicts` helper function to the same script that the Portfolio Orchestrator invokes
after the tool-fix check: it cross-checks file sets between all pairs of implementation items in
a candidate batch, marks conflicting pairs per the priority rules in the spec, and emits a
`CONFLICT_PAIRS` block. Update Protocol 90 Step 3 to insert a new subsection **"Same-batch
file-level conflict detection"** (placed after the "Same-batch tool-fix ordering hazard"
subsection) that codifies the detection algorithm, serialization rule, unknown-set handling, human
override path, and ordering rules.

**Estimated complexity**: M

**Rationale**: The work spans two files (one shell script, one protocol document) and follows the
same structural pattern as the tool-fix ordering feature (#199). The complexity is Medium rather
than Small because the file-set extraction step must parse structured markdown reliably, the
priority-based conflict resolution logic (BR-4 / BR-5) has multiple tiebreaker cases, and the
integration with the existing tool-fix check (BR-8) requires ordering discipline within the script.

**Dependencies**: None

---

## Verification Log

| Check | Command / query | Result |
|---|---|---|
| Repo revision | `git rev-parse --short HEAD` | `0039ddb` |
| Implementation plan template | `ls docs/workflow/development-workflow/templates/implementation-plan-template.md` | present |
| Batch-plan script location | `ls scripts/development-workflow/workflow-batch-plan.sh` | present |
| Protocol 90 location | `ls docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` | present |
| Protocol 90 tool-fix subsection anchor | `grep -n "Same-batch tool-fix ordering hazard" docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` | line 235 |
| "Codex fallback" paragraph anchor (insertion point for new subsection) | `grep -n "Codex fallback" docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` | line 290 |
| Existing smoke test runbooks pattern | `ls docs/testing/workflow/199-same-batch-tool-fix-ordering.smoke-test.md` | present |
| `print_kv` helper in workflow-lib.sh | `grep -n "print_kv" scripts/development-workflow/workflow-lib.sh` | function present |
| `parallel_safe_for_action` emits `conditional` for `implement` | `grep -A5 "parallel_safe_for_action" scripts/development-workflow/workflow-batch-plan.sh` | `implement` → `conditional` |

---

## Layer-by-Layer Changes

### Scripts / Workflow Tooling

- [ ] Add an `extract_file_set` helper function to
  `scripts/development-workflow/workflow-batch-plan.sh` that:
  1. Accepts a development folder path.
  2. Locates the implementation plan document (`2_*_implementation-plan.md`) inside the
     folder using `find "$dev_path" -maxdepth 1 -name '2_*_implementation-plan.md'`.
  3. If no plan document exists, emits `unknown` and returns.
  4. Searches the plan document for lines inside an explicit "Files to be modified" list.
     The canonical format is a fenced code block or a bullet list under a heading whose
     normalized text matches `files to (be )?modified` or `files modified`
     (case-insensitive). The function must handle at least these two formats:
     - **Fenced code block format**: a block delimited by triple backticks under the
       matching heading; each non-blank, non-backtick line is treated as a file path.
     - **Bullet list format**: lines beginning with `- ` or `* ` directly under the
       matching heading, where the bullet content is a repo-root-relative path (no
       leading slash, forward slashes).
  5. Normalizes each extracted path: trim leading/trailing whitespace, convert backslashes
     to forward slashes, strip a leading `/` if present.
  6. If after normalization the extracted set is empty, emits `unknown`.
  7. Otherwise emits `<comma-separated normalized paths>` (sorted, deduplicated).

  > **Parser-risk note**: this function is the core parser for the file-set extraction.
  > See the Parser-risk addendum in the Testing Strategy section for edge-case coverage.

- [ ] In `workflow-batch-plan.sh`, call `extract_file_set` for each development path that
  has `NEXT_ACTION=implement` or `NEXT_ACTION=resolve-development-pr` (i.e.,
  implementation-stage items only, matching BR-1). Emit:
  - `print_kv FILE_SET "$file_set"` always (even `unknown`).

- [ ] Add a `detect_file_conflicts` function to `workflow-batch-plan.sh` (or to a new
  helper script `scripts/development-workflow/workflow-conflict-detect.sh` invoked from
  `workflow-batch-plan.sh`). This function:
  1. Accepts an associative-array-style input of `<item-id>=><comma-separated file set>` pairs
     for all implementation items in the proposed batch. Items whose `FILE_SET=unknown` are
     excluded from conflict analysis but included in the summary warning list.
  2. For each pair `(A, B)` where both have known file sets, computes the intersection of
     their file sets.
  3. If the intersection is non-empty, records the pair as conflicting with the overlapping
     file paths.
  4. Applies the priority-based serialization rule (BR-4 / BR-5): compare item priorities;
     the lower-priority item is serialized. Tiebreaker: later creation date is serialized.
     Second tiebreaker: lexicographically later branch name is serialized.
  5. Emits for each conflicting pair:
     - `CONFLICT_PAIR=<item-A-id>,<item-B-id>` — the conflicting pair (higher-priority item
       first)
     - `CONFLICT_FILES=<comma-separated overlapping paths>` — the overlapping paths
     - `SERIALIZE=<item-id>` — the item to move to the next sub-batch
  6. Emits `CONFLICT_UNKNOWN=<item-id>` for each item whose file set is unknown.

  > **Integration with tool-fix check (BR-8)**: `detect_file_conflicts` must receive only
  > the items that **remain in the current batch after the tool-fix check**. Items already
  > serialized by the tool-fix rule must be excluded from the conflict-detection input set.
  > The orchestrator (or the calling code in `workflow-batch-plan.sh`) is responsible for
  > excluding tool-fix-serialized items before passing the input to `detect_file_conflicts`.

- [ ] The `parallel_safe_for_action` function already returns `conditional` for `implement`
  and `resolve-development-pr`. No change is needed to that function — conflict detection
  is an additional filter applied by the orchestrator after `workflow-batch-plan.sh` emits
  the per-item `FILE_SET` values.

### Protocol Documentation

- [ ] In `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`
  **Step 3**, add a new subsection **"Same-batch file-level conflict detection"** immediately
  after the existing "Same-batch tool-fix ordering hazard" subsection and before the "Codex
  fallback" paragraph. The new subsection must cover:

  1. **Scope** (BR-1): conflict detection applies only to implementation items (branches with
     prefix `feature/`, `fix/`, `refactor/`, `hotfix/`). Spec and plan items are never
     subject to file-level conflict serialization.

  2. **Detection source**: `workflow-batch-plan.sh` emits `FILE_SET=<comma-separated paths>`
     or `FILE_SET=unknown` per implementation item. The `FILE_SET` value is derived from the
     explicit file list in the item's implementation plan document. Items without a plan
     document, or whose plan contains no extractable file list, receive `FILE_SET=unknown`.

  3. **Conflict definition** (BR-2): a conflict exists between two items when their declared
     file sets share at least one common path. Paths are compared as normalized,
     repo-root-relative strings (forward slashes, no leading slash).

  4. **Serialization rule** (BR-4 / BR-5): when a conflict is detected, the lower-priority
     item is moved to the next serial sub-batch. Priority is determined by: (a) item priority
     level (Urgent > High > Normal > Low); (b) creation date (older stays); (c) branch name
     lexicographic order (earlier stays). The batch summary must list the conflicting pair,
     the overlapping file paths, and the resulting batch assignment for each item (BR-7).

  5. **Unknown-set handling** (BR-3): items with `FILE_SET=unknown` are not automatically
     serialized but are flagged in the batch summary with a warning noting that file-level
     conflict detection was not possible.

  6. **Human override** (BR-6): the orchestrator must **never** autonomously dispatch an
     override. Only an explicit human instruction enables parallel dispatch when a conflict
     has been detected. When a human instructs override, the orchestrator logs the override
     and annotates the batch summary with a warning.

  7. **Ordering relative to tool-fix check** (BR-8): conflict detection runs **after** the
     tool-fix ordering check. Items already serialized by the tool-fix rule are excluded from
     the conflict-detection input set for the current batch.

  **Important scope constraints**:
  - Do NOT modify Steps 3.3, 3.5, 3.6, 3.7, or any other step in Protocol 90 or any other
    protocol file.

---

## Testing Strategy

**Test types**: Manual / Smoke

**Key scenarios to test**:

1. `workflow-batch-plan.sh` against an implementation item whose plan has an explicit file
   list → `FILE_SET` contains the listed paths (maps to AC-1, AC-2, BR-2).
2. `workflow-batch-plan.sh` against an implementation item whose plan has no explicit file
   list → `FILE_SET=unknown` (maps to AC-3, BR-3).
3. `workflow-batch-plan.sh` against an implementation item with no plan document →
   `FILE_SET=unknown` (maps to AC-4, BR-3).
4. `detect_file_conflicts` with two items sharing a file → emits `CONFLICT_PAIR`,
   `CONFLICT_FILES`, `SERIALIZE` for the lower-priority item (maps to AC-1, BR-4).
5. `detect_file_conflicts` with two items whose file sets have no overlap → no
   `CONFLICT_PAIR` emitted (maps to AC-2).
6. `detect_file_conflicts` with one item having `FILE_SET=unknown` → emits
   `CONFLICT_UNKNOWN` for that item; no auto-serialization (maps to AC-3, BR-3).
7. Equal-priority tiebreaker by creation date: the item with the later creation date is
   serialized (maps to BR-5).
8. Equal-priority, equal-date tiebreaker by branch name: lexicographically later branch is
   serialized (maps to BR-5).
9. Tool-fix-serialized item excluded from conflict-detection input → not evaluated for file
   overlap (maps to AC-7, BR-8).
10. Spec-stage and plan-stage items excluded from conflict detection → `FILE_SET` not emitted
    for those items (maps to AC-6, BR-1).
11. Protocol 90 Step 3 contains the new subsection with all required content (maps to
    AC-1 through AC-8 protocol-level verification).

**Smoke test runbook**: [`docs/testing/workflow/324-parallel-batch-file-conflict-detection.smoke-test.md`](../../../testing/workflow/324-parallel-batch-file-conflict-detection.smoke-test.md)

### Parser-risk addendum

This plan is parser-risk because `extract_file_set` is a structured-text scanner that parses
markdown plan documents to extract file paths.

**Edge-case enumeration**:

| Case | Input | Expected behaviour |
|---|---|---|
| Fenced code block: paths with no leading slash | `` `\ndocs/foo/bar.sh\n` `` under matching heading | extracted as `docs/foo/bar.sh` |
| Fenced code block: path with leading slash | `` `\n/docs/foo/bar.sh\n` `` | normalized to `docs/foo/bar.sh` (strip leading `/`) |
| Bullet list: `- ` prefix | `- docs/foo/bar.sh` under matching heading | extracted as `docs/foo/bar.sh` |
| Bullet list: `* ` prefix | `* docs/foo/bar.sh` | extracted as `docs/foo/bar.sh` |
| Heading variant: `Files to be modified` | `### Files to be modified` | matched |
| Heading variant: `Files modified` | `### Files modified` | matched |
| Heading variant: mixed case | `### FILES TO BE MODIFIED` | matched (case-insensitive) |
| Empty fenced block | `` `\n` `` under heading | yields no paths → `unknown` |
| Blank lines between heading and content | heading followed by one or more blank lines then fenced block or bullet list | blank lines skipped; content extracted normally |
| Blank lines inside fenced block | paths interspersed with blank lines | blank lines skipped; paths extracted |
| Duplicate paths in list | same path listed twice | deduplicated in output |
| Path with backslashes | `docs\foo\bar.sh` | normalized to `docs/foo/bar.sh` |
| Heading that almost matches | `### Files that will be modified later` | must **not** match (only `files to be modified`, `files to modified`, `files modified` match) |
| No matching heading in document | plan document with no `Files` heading | yields `unknown` |
| Multiple matching headings | two `Files to be modified` sections | paths from both sections extracted and merged |

**Unit test mapping**:

Name the unit test file `scripts/lint/test-extract-file-set.sh` (or inline within the smoke test
runbook). Each row in the edge-case table above maps to at least one `assert_file_set` invocation
in the smoke test runbook Step 1 through Step N.

---

## Seed Data

None. All tests use temporary fixture directories created by the smoke tester. No running
application, no database, and no issue tracker queries are required.

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` —
  updated as part of this implementation (new Step 3 subsection). No separate post-implementation
  doc update needed beyond what the plan steps cover.

Other docs in `docs/project/`, `docs/best-practices/`, and `AGENTS.md` are not affected — this
change modifies only workflow tooling internals and the orchestration protocol.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Markdown heading normalization misses a valid heading variant used in real plan documents | Medium | Medium | Pre-scan existing plan documents in `docs/specs/developments/` during implementation and confirm all `Files` headings are covered by the regex |
| `extract_file_set` silently returns `unknown` for a plan that does have a file list but uses an unrecognized format | Medium | Low | Implement format detection strictly per the two canonical formats; add a warning comment in the script when `unknown` is returned for a non-empty document |
| Priority tiebreaker (creation date from branch name slug) is unreliable when branch names do not encode a timestamp | Low | Low | The tiebreaker falls through to lexicographic branch name order, which is deterministic even without a timestamp |
| BR-8 ordering violated if script caller passes tool-fix-serialized items to `detect_file_conflicts` | Low | Medium | Document the pre-filtering requirement in the function's docstring and in Protocol 90; add a defensive guard that ignores items already flagged as `SERIALIZE` by the tool-fix step |
| Conflict detection for items with overlapping `FILE_SET=unknown` produces no warning | Low | Low | `CONFLICT_UNKNOWN` is emitted for every unknown-set item; the orchestrator summarizes this to the human |

---

## Code Samples

```bash
# Illustrative — adapt during implementation

# extract_file_set <development-folder-path>
#
# Extracts the declared file set from a development folder's implementation plan.
# Looks for a heading matching /files\s+(to\s+(be\s+)?)?modified/i and extracts paths from
# the subsequent fenced code block or bullet list.
#
# Emits:
#   unknown                         — no plan found, or no extractable file list
#   <comma-separated sorted paths>  — normalized repo-root-relative paths
extract_file_set() {
  local dev_path="$1"
  local plan_file
  plan_file="$(find "$dev_path" -maxdepth 1 -name '2_*_implementation-plan.md' | head -1)"
  if [ -z "$plan_file" ]; then
    printf 'unknown\n'
    return 0
  fi

  # Python one-liner for robust multi-line section extraction (illustrative)
  local paths
  paths="$(python3 - "$plan_file" <<'PYEOF'
import sys, re
text = open(sys.argv[1]).read()
# Find heading matching "files (to (be )?)?modified" (case-insensitive)
heading_re = re.compile(r'#+\s+files\s+(to\s+(be\s+)?)?modified', re.IGNORECASE)
paths = []
lines = text.splitlines()
i = 0
while i < len(lines):
    if heading_re.search(lines[i]):
        i += 1
        # Skip blank lines between heading and content block
        while i < len(lines) and not lines[i].strip():
            i += 1
        # Try fenced code block
        if i < len(lines) and lines[i].startswith('```'):
            i += 1
            while i < len(lines) and not lines[i].startswith('```'):
                p = lines[i].strip()
                if p:
                    paths.append(p.lstrip('/').replace('\\', '/'))
                i += 1
        else:
            # Bullet list
            while i < len(lines) and (lines[i].startswith('- ') or lines[i].startswith('* ')):
                p = lines[i][2:].strip()
                if p:
                    paths.append(p.lstrip('/').replace('\\', '/'))
                i += 1
    else:
        i += 1
seen = set()
deduped = [p for p in paths if not (p in seen or seen.add(p))]
print(','.join(sorted(deduped)) if deduped else 'unknown')
PYEOF
  )"
  printf '%s\n' "$paths"
}
```

---

## Implementation Order

1. Read `scripts/development-workflow/workflow-batch-plan.sh` and
   `scripts/development-workflow/workflow-lib.sh` in full to understand existing helpers
   (`print_kv`, `batch_hint_for_action`, `parallel_safe_for_action`, `classify_tool_fix`,
   `extract_github_issue_number`, `cd_workflow_repo_root`).

2. Add `extract_file_set` helper function to `workflow-batch-plan.sh`. Place it after
   `classify_tool_fix` and before `cd_workflow_repo_root`. Implement format detection for:
   - Fenced code block under a heading matching `/files\s+(to\s+(be\s+)?)?modified/i`
   - Bullet list under the same heading
   Use the Python one-liner approach from the Code Samples section (or an equivalent pure
   Bash/awk implementation if Python is unavailable). All edge cases in the parser-risk
   addendum must be covered.

3. In the main `for development_path` loop, after the `classify_tool_fix` call, call
   `extract_file_set` for items where `next_action` is `implement` or
   `resolve-development-pr`. Emit `print_kv FILE_SET "$file_set"`. For all other
   `next_action` values, do not emit `FILE_SET`.

4. Add `detect_file_conflicts` function to `workflow-batch-plan.sh` (below `extract_file_set`).
   Implement the pairwise overlap detection, priority-based serialization tiebreakers (BR-4 /
   BR-5), and output protocol described in the Layer-by-Layer Changes section.

5. Read
   `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` Step 3
   in full. Identify the insertion point: after the "Same-batch tool-fix ordering hazard"
   subsection's **Human override** paragraph and before the **Codex fallback** paragraph
   (currently around line 290).

6. Insert the **"Same-batch file-level conflict detection"** subsection at that location,
   covering all seven content requirements listed in the Protocol Documentation layer above.
   Confirm:
   - The subsection appears after "Same-batch tool-fix ordering hazard"
   - The subsection appears before "Codex fallback"
   - No other existing content is modified

7. Run the smoke test runbook scenarios manually using fixture directories to verify all
   acceptance criteria. Pay particular attention to the parser edge cases in the parser-risk
   addendum.

8. Update `CHANGELOG.md` under `[Unreleased]` with:

   ```
   - **Parallel batch file-level conflict detection** (#324): the batch orchestrator now extracts declared file sets from implementation plan documents and automatically serializes items with overlapping file sets before dispatch; items without an explicit file list are flagged as unknown-set in the batch summary.
   ```
