# Smoke Test Runbook: Parallel Batch File-Level Conflict Detection

**Feature**: Parallel batch file-level conflict detection (issue #324)
**Spec**: [docs/specs/developments/20260427222126_324-parallel-batch-file-conflict-detection/1_324-parallel-batch-file-conflict-detection_specs.md](../../specs/developments/20260427222126_324-parallel-batch-file-conflict-detection/1_324-parallel-batch-file-conflict-detection_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] Repository is on the `develop` branch (or on the feature branch for this issue)
- [ ] `gh` CLI is authenticated
- [ ] Bash 3.2+ and Python 3 are available
- [ ] `scripts/development-workflow/workflow-batch-plan.sh` has been updated per the
  implementation plan (adds `extract_file_set` and `detect_file_conflicts`)
- [ ] `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` has
  been updated with the new "Same-batch file-level conflict detection" subsection
- [ ] A temporary fixture directory is available (see Test Data below)

---

## Test Data

All tests use temporary fixture directories created by the smoke tester. No running application,
no database, and no issue tracker queries are required.

| Item | Value |
|---|---|
| Fixture base dir | `.tmp/smoke-324/` (gitignored) |
| Script under test | `scripts/development-workflow/workflow-batch-plan.sh` |
| Protocol under test | `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` |

Create the fixture base directory before running:

```bash
mkdir -p .tmp/smoke-324
```

---

## Smoke Test Steps

### Step 1: AC-1 / AC-2 — `extract_file_set` with explicit fenced code block file list

Create a fixture implementation plan with a fenced code block under `### Files to be modified`:

```bash
mkdir -p .tmp/smoke-324/20200101000001_ac1-known-fileset
cat > .tmp/smoke-324/20200101000001_ac1-known-fileset/2_ac1_implementation-plan.md <<'EOF'
# AC1 Plan

### Files to be modified

```
scripts/development-workflow/workflow-batch-plan.sh
docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md
```
EOF
WORKFLOW_SKIP_FETCH=1 ./scripts/development-workflow/workflow-batch-plan.sh \
  .tmp/smoke-324/20200101000001_ac1-known-fileset 2>/dev/null || true
```

**Expected result**:
- Output contains `FILE_SET=` with both paths listed
- Paths are comma-separated and sorted
- No `FILE_SET=unknown` in the output

**Maps to**: AC-1, AC-2 (known file set correctly extracted), BR-2

---

### Step 2: AC-1 — `extract_file_set` with bullet-list format

Create a fixture using bullet-list format:

```bash
mkdir -p .tmp/smoke-324/20200101000002_ac1-bullet-list
cat > .tmp/smoke-324/20200101000002_ac1-bullet-list/2_ac1_implementation-plan.md <<'EOF'
# AC1 Plan

### Files modified

- scripts/development-workflow/pr-review-loop.sh
- docs/project/2-repo-architecture.md
EOF
WORKFLOW_SKIP_FETCH=1 ./scripts/development-workflow/workflow-batch-plan.sh \
  .tmp/smoke-324/20200101000002_ac1-bullet-list 2>/dev/null || true
```

**Expected result**:
- Output contains `FILE_SET=` with both paths
- Paths are extracted correctly without the `- ` prefix

**Maps to**: AC-1 (bullet-list format), BR-2

---

### Step 3: AC-3 — `extract_file_set` with no explicit file list in plan

Create a fixture plan that has no `Files to be modified` heading:

```bash
mkdir -p .tmp/smoke-324/20200101000003_ac3-no-filelist
cat > .tmp/smoke-324/20200101000003_ac3-no-filelist/2_ac3_implementation-plan.md <<'EOF'
# AC3 No File List Plan

## Layer-by-Layer Changes

- [ ] Update some file
- [ ] Update another file
EOF
WORKFLOW_SKIP_FETCH=1 ./scripts/development-workflow/workflow-batch-plan.sh \
  .tmp/smoke-324/20200101000003_ac3-no-filelist 2>/dev/null || true
```

**Expected result**:
- Output contains `FILE_SET=unknown`

**Maps to**: AC-3, BR-3 (no extractable file list → unknown)

---

### Step 4: AC-4 — `extract_file_set` with no plan document

Create a fixture folder with only a spec file (no `2_*_implementation-plan.md`):

```bash
mkdir -p .tmp/smoke-324/20200101000004_ac4-no-plan
cat > .tmp/smoke-324/20200101000004_ac4-no-plan/1_ac4_specs.md <<'EOF'
# AC4 Spec — no plan document
EOF
WORKFLOW_SKIP_FETCH=1 ./scripts/development-workflow/workflow-batch-plan.sh \
  .tmp/smoke-324/20200101000004_ac4-no-plan 2>/dev/null || true
```

**Expected result**:
- Output contains `FILE_SET=unknown`

**Maps to**: AC-4, BR-3 (no plan document → unknown)

---

### Step 5: AC-6 — Spec-stage and plan-stage items do not get FILE_SET

Create a fixture folder for a spec-stage item (no plan document):

```bash
mkdir -p .tmp/smoke-324/20200101000005_ac6-spec-stage
cat > .tmp/smoke-324/20200101000005_ac6-spec-stage/1_ac6_specs.md <<'EOF'
# AC6 Spec-only item
EOF
WORKFLOW_SKIP_FETCH=1 ./scripts/development-workflow/workflow-batch-plan.sh \
  .tmp/smoke-324/20200101000005_ac6-spec-stage 2>/dev/null || true
```

**Expected result**:
- Output does **not** contain `FILE_SET=` for items whose `NEXT_ACTION` is `write-plan` or
  earlier stages (spec/plan items are excluded from conflict detection entirely)

**Maps to**: AC-6, BR-1

---

### Step 6: AC-1 — `detect_file_conflicts` detects overlap and serializes lower-priority item

Invoke `detect_file_conflicts` with two items sharing a file. Simulate two implementation items
in the same candidate batch where item A (higher priority) and item B (lower priority) both
declare `scripts/development-workflow/workflow-batch-plan.sh`:

```bash
# Invoke detect_file_conflicts directly (or via workflow-batch-plan.sh with two paths)
mkdir -p .tmp/smoke-324/20200101000006_item-a
cat > .tmp/smoke-324/20200101000006_item-a/2_item-a_implementation-plan.md <<'EOF'
# Item A Plan

### Files to be modified

```
scripts/development-workflow/workflow-batch-plan.sh
docs/project/1-business-domain.md
```
EOF

mkdir -p .tmp/smoke-324/20200101000007_item-b
cat > .tmp/smoke-324/20200101000007_item-b/2_item-b_implementation-plan.md <<'EOF'
# Item B Plan

### Files to be modified

```
scripts/development-workflow/workflow-batch-plan.sh
docs/project/2-repo-architecture.md
```
EOF

WORKFLOW_SKIP_FETCH=1 ./scripts/development-workflow/workflow-batch-plan.sh \
  .tmp/smoke-324/20200101000006_item-a \
  .tmp/smoke-324/20200101000007_item-b 2>/dev/null || true
```

**Expected result**:
- Output contains `CONFLICT_PAIR=` listing both item IDs
- Output contains `CONFLICT_FILES=scripts/development-workflow/workflow-batch-plan.sh`
- Output contains `SERIALIZE=` identifying the lower-priority item
- The batch summary notes the overlapping file path and the serialization decision

**Maps to**: AC-1, BR-2, BR-4, BR-7

---

### Step 7: AC-2 — No conflict when file sets are disjoint

Create two items with non-overlapping file sets:

```bash
mkdir -p .tmp/smoke-324/20200101000008_item-c
cat > .tmp/smoke-324/20200101000008_item-c/2_item-c_implementation-plan.md <<'EOF'
# Item C Plan

### Files to be modified

```
docs/project/1-business-domain.md
```
EOF

mkdir -p .tmp/smoke-324/20200101000009_item-d
cat > .tmp/smoke-324/20200101000009_item-d/2_item-d_implementation-plan.md <<'EOF'
# Item D Plan

### Files to be modified

```
docs/project/3-software-architecture.md
```
EOF

WORKFLOW_SKIP_FETCH=1 ./scripts/development-workflow/workflow-batch-plan.sh \
  .tmp/smoke-324/20200101000008_item-c \
  .tmp/smoke-324/20200101000009_item-d 2>/dev/null || true
```

**Expected result**:
- Output does **not** contain any `CONFLICT_PAIR=` entry
- Both items appear in the same batch without serialization

**Maps to**: AC-2, BR-2

---

### Step 8: AC-3 — Unknown-set item dispatched with warning, not serialized

Create a batch with one known-set item and one unknown-set item:

```bash
mkdir -p .tmp/smoke-324/20200101000010_item-e
cat > .tmp/smoke-324/20200101000010_item-e/2_item-e_implementation-plan.md <<'EOF'
# Item E Plan

### Files to be modified

```
docs/project/1-business-domain.md
```
EOF

mkdir -p .tmp/smoke-324/20200101000011_item-f
cat > .tmp/smoke-324/20200101000011_item-f/2_item-f_implementation-plan.md <<'EOF'
# Item F Plan — no file list

## Layer-by-Layer Changes

- [ ] Some change
EOF

WORKFLOW_SKIP_FETCH=1 ./scripts/development-workflow/workflow-batch-plan.sh \
  .tmp/smoke-324/20200101000010_item-e \
  .tmp/smoke-324/20200101000011_item-f 2>/dev/null || true
```

**Expected result**:
- Item F output contains `FILE_SET=unknown`
- Output contains `CONFLICT_UNKNOWN=` for item F
- Item F is **not** serialized (appears in same batch)
- Batch summary notes that conflict detection was not possible for item F

**Maps to**: AC-3, BR-3

---

### Step 9: Parser edge cases — leading slash normalization and case-insensitive heading

```bash
mkdir -p .tmp/smoke-324/20200101000012_edge-cases
cat > .tmp/smoke-324/20200101000012_edge-cases/2_edge_implementation-plan.md <<'EOF'
# Edge Cases Plan

### FILES TO BE MODIFIED

```
/docs/project/1-business-domain.md
docs/project/2-repo-architecture.md
docs/project/2-repo-architecture.md
```
EOF
WORKFLOW_SKIP_FETCH=1 ./scripts/development-workflow/workflow-batch-plan.sh \
  .tmp/smoke-324/20200101000012_edge-cases 2>/dev/null || true
```

**Expected result**:
- Leading `/` is stripped: `docs/project/1-business-domain.md` (not `/docs/...`)
- Duplicate path `docs/project/2-repo-architecture.md` appears only once
- Heading `FILES TO BE MODIFIED` (all caps) is matched correctly

**Maps to**: BR-2 (normalized paths), parser edge cases

---

### Step 10: AC-7 / BR-8 — Tool-fix-serialized items excluded from conflict detection

Confirm that items already serialized by the tool-fix check are not evaluated by
`detect_file_conflicts`. In a batch containing a tool-fix item and an implementation item:

```bash
# The tool-fix item (references a canonical workflow tool) should be serialized by
# the tool-fix check BEFORE conflict detection runs. Confirm the output shows:
# 1. TOOL_FIX=yes for the tool-fix item
# 2. The tool-fix item is moved to its own serial sub-batch
# 3. detect_file_conflicts is NOT invoked for the tool-fix item
# (This is verified by confirming that even if the tool-fix item's plan declares
# a file also declared by another item, no CONFLICT_PAIR is emitted for that pairing.)

mkdir -p .tmp/smoke-324/20200101000013_toolfix-item
cat > .tmp/smoke-324/20200101000013_toolfix-item/2_toolfix_implementation-plan.md <<'EOF'
# Tool-Fix Item Plan

### Files to be modified

```
scripts/development-workflow/pr-review-loop.sh
docs/project/1-business-domain.md
```
EOF

mkdir -p .tmp/smoke-324/20200101000014_consumer-item
cat > .tmp/smoke-324/20200101000014_consumer-item/2_consumer_implementation-plan.md <<'EOF'
# Consumer Item Plan

### Files to be modified

```
docs/project/1-business-domain.md
```
EOF

WORKFLOW_SKIP_FETCH=1 ./scripts/development-workflow/workflow-batch-plan.sh \
  .tmp/smoke-324/20200101000013_toolfix-item \
  .tmp/smoke-324/20200101000014_consumer-item 2>/dev/null || true
```

**Expected result**:
- Tool-fix item has `TOOL_FIX=yes`
- Tool-fix item is serialized to its own sub-batch (tool-fix rule takes precedence)
- No `CONFLICT_PAIR=` involving the tool-fix item (BR-8: tool-fix-serialized items excluded)
- Consumer item remains in the current batch (or is held pending tool-fix merge, per
  protocol 90 Step 3 tool-fix rule)

**Maps to**: AC-7, BR-8

---

### Step 11: Protocol 90 — New subsection present with required content

Verify that Protocol 90 Step 3 contains the new "Same-batch file-level conflict detection"
subsection:

```bash
grep -n "Same-batch file-level conflict detection" \
  docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md
```

**Expected result**:
- Command returns at least one matching line
- The subsection heading appears after `Same-batch tool-fix ordering hazard`
- The subsection heading appears before `Codex fallback`

Confirm the subsection covers all required content by reading it:

```bash
# Read Step 3 between the two anchor points to visually confirm content
grep -n "Same-batch\|Codex fallback\|FILE_SET\|conflict detection\|BR-1\|BR-2\|BR-3\|BR-4\|BR-5\|BR-6\|BR-7\|BR-8" \
  docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md | head -40
```

**Expected result**:
- Scope rule (BR-1), conflict definition (BR-2), serialization rule (BR-4/BR-5),
  unknown-set handling (BR-3), human override (BR-6), ordering relative to tool-fix (BR-8),
  and batch summary annotation (BR-7) are all present in the subsection

**Maps to**: AC-1 through AC-8 (protocol-level), BR-1 through BR-8

---

### Last Step: Clean up fixtures and validate

```bash
rm -rf .tmp/smoke-324
```

Verify all assertions in the checklist below are met before considering the feature complete.

---

## Assertions Checklist

Each checkbox maps to an acceptance criterion from the spec.

- [ ] AC-1: Two implementation items declaring the same file → only higher-priority item in
  current batch; other serialized; batch summary lists overlapping path and decision
- [ ] AC-2: Two implementation items with disjoint file sets → both dispatched together;
  no conflict warning in batch summary
- [ ] AC-3: Implementation item whose plan has no explicit file list → dispatched normally;
  batch summary notes unknown file set
- [ ] AC-4: Implementation-branch item with no plan document → treated as unknown file set;
  dispatched; batch summary includes warning
- [ ] AC-5: Human override of serialization decision → previously-serialized item dispatched
  in parallel; batch summary records the override with warning
- [ ] AC-6: Spec-stage and plan-stage items are not subject to file-level conflict checks
- [ ] AC-7: Conflict detection runs after the tool-fix check; tool-fix-serialized items
  excluded from conflict-detection input
- [ ] AC-8: File path comparison is case-sensitive and uses normalized repo-root-relative
  paths (forward slashes, no leading slash)

---

## Seed Data Reference

No seed data required — all tests use temporary fixture directories.

| Entity | Scenario | How to load |
|---|---|---|
| Fixture directories | Created inline per step | `mkdir -p .tmp/smoke-324/<fixture-name>` |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `FILE_SET` not emitted for implementation item | `extract_file_set` not called for `implement` action | Confirm `NEXT_ACTION=implement` is emitted and that `extract_file_set` is invoked for that action |
| `FILE_SET=unknown` when plan has a file list | Heading regex does not match the variant used | Check the heading text against the supported variants; add the variant to the regex |
| `CONFLICT_PAIR` not emitted for overlapping items | `detect_file_conflicts` not receiving both items' file sets | Confirm both items are passed as input; confirm `FILE_SET` values are non-`unknown` |
| Leading slash not stripped from path | Normalization step missing | Confirm `lstrip('/')` or equivalent is applied to all extracted paths |
| Duplicate paths in `FILE_SET` | Deduplication step missing | Confirm `sort -u` or equivalent is applied |

---

## Known Limitations

- AC-5 (human override of serialization) cannot be verified end-to-end in a pure fixture-based
  test; manual orchestrator run with a real parallel batch is required to fully exercise that
  path.
- The smoke test does not verify the priority tiebreaker (BR-5) for items with the same priority
  and creation date; that case requires constructing two fixtures with matching timestamps and
  different branch names, which may need a manual test.
