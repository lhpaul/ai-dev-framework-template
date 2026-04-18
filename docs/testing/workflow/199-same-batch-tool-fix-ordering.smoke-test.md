# Smoke Test Runbook: Same-Batch Tool-Fix Ordering Hazard Detection

**Feature**: Same-batch tool-fix ordering hazard detection (issue #199)
**Spec**: [docs/specs/developments/20260417154720_199-same-batch-tool-fix-ordering/1_199-same-batch-tool-fix-ordering_specs.md](../../specs/developments/20260417154720_199-same-batch-tool-fix-ordering/1_199-same-batch-tool-fix-ordering_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] Repository is on the `develop` branch (or on the feature branch for this issue)
- [ ] `gh` CLI is authenticated
- [ ] Bash 3.2+ is available
- [ ] `scripts/development-workflow/workflow-batch-plan.sh` has been updated per the
  implementation plan
- [ ] `docs/ai/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` has been
  updated per the implementation plan
- [ ] A temporary fixture directory is available (see Test Data below)

---

## Test Data

All tests use temporary fixture directories created by the smoke tester. No running application,
no database, and no issue tracker queries are required.

| Item | Value |
|---|---|
| Fixture base dir | `.tmp/smoke-199/` (gitignored) |
| Script under test | `scripts/development-workflow/workflow-batch-plan.sh` |
| Protocol under test | `docs/ai/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` |

Create the fixture base directory before running:

```bash
mkdir -p .tmp/smoke-199
```

---

## Smoke Test Steps

### Step 1: AC1 — `pr-review-loop.sh` reference → `TOOL_FIX=yes`

Create a fixture development folder whose spec references `pr-review-loop.sh`:

```bash
mkdir -p .tmp/smoke-199/20200101000001_ac1-pr-review-loop
cat > .tmp/smoke-199/20200101000001_ac1-pr-review-loop/1_ac1_specs.md <<'EOF'
# Test spec referencing scripts/development-workflow/pr-review-loop.sh
EOF
WORKFLOW_SKIP_FETCH=1 ./scripts/development-workflow/workflow-batch-plan.sh \
  .tmp/smoke-199/20200101000001_ac1-pr-review-loop 2>/dev/null || true
```

**Expected result**:
- Output contains `TOOL_FIX=yes`
- Output contains `TOOL_FIX_FILES=` with `scripts/development-workflow/pr-review-loop.sh` in
  the value (exact path, not a superstring)

### Step 2: AC2 — `pr-ci-loop.sh` reference → `TOOL_FIX=yes`

```bash
mkdir -p .tmp/smoke-199/20200101000002_ac2-pr-ci-loop
cat > .tmp/smoke-199/20200101000002_ac2-pr-ci-loop/1_ac2_specs.md <<'EOF'
# Test spec referencing scripts/development-workflow/pr-ci-loop.sh
EOF
WORKFLOW_SKIP_FETCH=1 ./scripts/development-workflow/workflow-batch-plan.sh \
  .tmp/smoke-199/20200101000002_ac2-pr-ci-loop 2>/dev/null || true
```

**Expected result**:
- Output contains `TOOL_FIX=yes`
- `TOOL_FIX_FILES=` contains `scripts/development-workflow/pr-ci-loop.sh`

### Step 3: AC3 — Protocol `.md` reference → `TOOL_FIX=yes`

```bash
mkdir -p .tmp/smoke-199/20200101000003_ac3-protocol-md
cat > .tmp/smoke-199/20200101000003_ac3-protocol-md/1_ac3_specs.md <<'EOF'
# Test spec referencing docs/ai/development-workflow/protocols/90-batch-orchestrate-work-protocol.md
EOF
WORKFLOW_SKIP_FETCH=1 ./scripts/development-workflow/workflow-batch-plan.sh \
  .tmp/smoke-199/20200101000003_ac3-protocol-md 2>/dev/null || true
```

**Expected result**:
- Output contains `TOOL_FIX=yes`
- `TOOL_FIX_FILES=` contains
  `docs/ai/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`

### Step 4: AC4 — `batch-merge.sh` reference → `TOOL_FIX=yes`

```bash
mkdir -p .tmp/smoke-199/20200101000004_ac4-batch-merge
cat > .tmp/smoke-199/20200101000004_ac4-batch-merge/1_ac4_specs.md <<'EOF'
# Test spec referencing scripts/development-workflow/batch-merge.sh
EOF
WORKFLOW_SKIP_FETCH=1 ./scripts/development-workflow/workflow-batch-plan.sh \
  .tmp/smoke-199/20200101000004_ac4-batch-merge 2>/dev/null || true
```

**Expected result**:
- Output contains `TOOL_FIX=yes`
- `TOOL_FIX_FILES=` contains `scripts/development-workflow/batch-merge.sh`

### Step 5: AC5 — `post-merge-cleanup.sh` reference → `TOOL_FIX=yes`

```bash
mkdir -p .tmp/smoke-199/20200101000005_ac5-post-merge
cat > .tmp/smoke-199/20200101000005_ac5-post-merge/1_ac5_specs.md <<'EOF'
# Test spec referencing scripts/development-workflow/post-merge-cleanup.sh
EOF
WORKFLOW_SKIP_FETCH=1 ./scripts/development-workflow/workflow-batch-plan.sh \
  .tmp/smoke-199/20200101000005_ac5-post-merge 2>/dev/null || true
```

**Expected result**:
- Output contains `TOOL_FIX=yes`
- `TOOL_FIX_FILES=` contains `scripts/development-workflow/post-merge-cleanup.sh`

### Step 6: AC6 — `.ai-dev-workflow.yaml` reference → `TOOL_FIX=yes`

```bash
mkdir -p .tmp/smoke-199/20200101000006_ac6-yaml
cat > .tmp/smoke-199/20200101000006_ac6-yaml/1_ac6_specs.md <<'EOF'
# Test spec referencing .ai-dev-workflow.yaml
EOF
WORKFLOW_SKIP_FETCH=1 ./scripts/development-workflow/workflow-batch-plan.sh \
  .tmp/smoke-199/20200101000006_ac6-yaml 2>/dev/null || true
```

**Expected result**:
- Output contains `TOOL_FIX=yes`
- `TOOL_FIX_FILES=` contains `.ai-dev-workflow.yaml`

### Step 7: AC7 — No tool references → `TOOL_FIX=no` (explicit, not omitted)

```bash
mkdir -p .tmp/smoke-199/20200101000007_ac7-no-tools
cat > .tmp/smoke-199/20200101000007_ac7-no-tools/1_ac7_specs.md <<'EOF'
# A spec with no workflow tool references
This spec describes a UI color change with no script dependencies.
EOF
WORKFLOW_SKIP_FETCH=1 ./scripts/development-workflow/workflow-batch-plan.sh \
  .tmp/smoke-199/20200101000007_ac7-no-tools 2>/dev/null || true
```

**Expected result**:
- Output contains `TOOL_FIX=no`
- Output does NOT contain `TOOL_FIX=yes`
- Output does NOT omit the `TOOL_FIX` line entirely

### Step 8: AC13 — No spec/plan document → `TOOL_FIX=unknown`

```bash
mkdir -p .tmp/smoke-199/20200101000008_ac13-no-doc
# Do NOT create any .md file in this folder
WORKFLOW_SKIP_FETCH=1 ./scripts/development-workflow/workflow-batch-plan.sh \
  .tmp/smoke-199/20200101000008_ac13-no-doc 2>/dev/null || true
```

**Expected result**:
- Output contains `TOOL_FIX=unknown`

### Step 9: AC3 — Exact-path matching (no false positives from superstrings)

Verify that a path like `scripts/development-workflow/pr-review-loop.sh.bak` does NOT trigger
`TOOL_FIX=yes`:

```bash
mkdir -p .tmp/smoke-199/20200101000009_ac3-superstring
cat > .tmp/smoke-199/20200101000009_ac3-superstring/1_ac3b_specs.md <<'EOF'
# References pr-review-loop.sh.bak (a superstring, not the canonical path)
EOF
WORKFLOW_SKIP_FETCH=1 ./scripts/development-workflow/workflow-batch-plan.sh \
  .tmp/smoke-199/20200101000009_ac3-superstring 2>/dev/null || true
```

**Expected result**:
- Output contains `TOOL_FIX=no` (superstring must not trigger a match)

### Step 10: Protocol 90 Step 3 content verification (ACs 8–12, 14)

Open `docs/ai/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` and verify
Step 3 contains a "Same-batch tool-fix ordering hazard" subsection with all required content:

- [ ] (AC 8) Orchestrator treats `TOOL_FIX=no` from script but tool-file reference in tracker
  title/description as a hazard candidate (conservative override)
- [ ] (AC 9) Protocol instructs serialize-first when a tool-fix item appears alongside consumer
  items
- [ ] (AC 10) Protocol instructs serializing each tool-fix item one at a time when two or more
  appear in the same batch
- [ ] (AC 11) Standard priority order (due date → priority → creation date) is used for ordering
  multiple tool-fix items
- [ ] (AC 12) Protocol explicitly names the same-batch tool-fix ordering hazard
- [ ] (AC 14) `TOOL_FIX=unknown` is treated the same as `TOOL_FIX=yes` (serialize-first)

Also verify:

- [ ] Step 5.1 remains unchanged (out-of-scope boundary)
- [ ] Human override path is documented and requires explicit human instruction

### Step 11: Cleanup

```bash
rm -rf .tmp/smoke-199/
```

### Last Step: Validate & Shut Down

- Verify all assertions in the checklist below are met
- Remove fixture directories

---

## Assertions Checklist

Each checkbox maps to an acceptance criterion from the spec.

- [ ] AC1: `pr-review-loop.sh` reference → `TOOL_FIX=yes`, exact path in `TOOL_FIX_FILES`
- [ ] AC2: `pr-ci-loop.sh` reference → `TOOL_FIX=yes`, exact path in `TOOL_FIX_FILES`
- [ ] AC3: protocol `.md` reference → `TOOL_FIX=yes`, exact matched path in `TOOL_FIX_FILES`
- [ ] AC4: `batch-merge.sh` reference → `TOOL_FIX=yes`, exact path in `TOOL_FIX_FILES`
- [ ] AC5: `post-merge-cleanup.sh` reference → `TOOL_FIX=yes`, exact path in `TOOL_FIX_FILES`
- [ ] AC6: `.ai-dev-workflow.yaml` reference → `TOOL_FIX=yes`, exact path in `TOOL_FIX_FILES`
- [ ] AC7: no tool references → `TOOL_FIX=no` (explicit line emitted, not omitted)
- [ ] AC8: tracker-derived conservative override described in Protocol 90 Step 3
- [ ] AC9: serialize-first rule described in Protocol 90 Step 3
- [ ] AC10: multiple tool-fix items serialized one at a time, documented in Protocol 90 Step 3
- [ ] AC11: standard priority order for multiple tool-fix items documented
- [ ] AC12: hazard explicitly named in Protocol 90 Step 3
- [ ] AC13: missing spec/plan document → `TOOL_FIX=unknown`
- [ ] AC14: `TOOL_FIX=unknown` treated as `yes` (serialize-first), documented in Protocol 90 Step 3
- [ ] Superstring non-match: `pr-review-loop.sh.bak` does NOT trigger `TOOL_FIX=yes`
- [ ] Step 5.1 in Protocol 90 is unchanged

---

## Seed Data Reference

None required. All test data is created inline via fixture directories.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `workflow-batch-plan.sh` exits non-zero on fixture path | Script calls `workflow-next-action.sh` which needs git context | Ensure you run from repo root; the `WORKFLOW_SKIP_FETCH=1` env var prevents git fetch but `workflow-next-action.sh` still needs git |
| `TOOL_FIX` line absent from output | Script did not reach classify step | Check that the fixture folder has a valid `slug` (timestamp prefix) |
| Superstring test still yields `TOOL_FIX=yes` | `grep -F` matching is too broad | Verify the exact-path match uses word-boundary or line-context anchoring |

---

## Known Limitations

- `workflow-batch-plan.sh` calls `workflow-next-action.sh` internally, which requires a real git
  repository context. Smoke tests must be run from the repository root. The script may print
  warnings or skip output for fixture folders that do not have corresponding git branches; this
  is expected and does not invalidate the `TOOL_FIX` line verification (which is emitted before
  the git-dependent next-action lookup).
- The smoke test validates `TOOL_FIX` line presence by grepping the combined stdout output. If
  the script routes `TOOL_FIX` to stderr, update the test to capture both streams.
