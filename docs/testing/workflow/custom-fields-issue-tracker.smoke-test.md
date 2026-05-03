# Smoke Test Runbook: Custom Fields Support for Issue Tracker Configuration

**Feature**: Custom fields support for issue tracker config (#453)
**Spec**: [`docs/specs/developments/20260430150000_453-custom-fields-issue-tracker/1_453-custom-fields-issue-tracker_specs.md`](../../specs/developments/20260430150000_453-custom-fields-issue-tracker/1_453-custom-fields-issue-tracker_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] You have a shell with Bash available
- [ ] The repository is cloned locally and the working directory is the repo root
- [ ] `workflow-lib.sh` has been updated with the `workflow_issue_tracker_custom_field` function

---

## Test Data

| Item | Value |
|---|---|
| Repo root | `/path/to/repo` |
| Temp config A (no `custom_fields`) | `.tmp/smoke-test-no-cf.yaml` (created in Step 1) |
| Temp config B (with `custom_fields`) | `.tmp/smoke-test-with-cf.yaml` (created in Step 2) |
| Temp config C (key absent) | `.tmp/smoke-test-missing-key.yaml` (created in Step 3) |

---

## Smoke Test Steps

### Step 0: Prepare temporary config files

Create the `.tmp/` directory if it does not exist:

```bash
mkdir -p .tmp
```

**Config A** — `issue_tracker` with no `custom_fields`:

```bash
cat > .tmp/smoke-test-no-cf.yaml <<'EOF'
issue_tracker:
  provider: github_projects
  project_number: 1
EOF
```

**Config B** — `issue_tracker` with `custom_fields.project`:

```bash
cat > .tmp/smoke-test-with-cf.yaml <<'EOF'
issue_tracker:
  provider: github_projects
  project_number: 1
  custom_fields:
    project: my-linear-project-id
EOF
```

**Config C** — `issue_tracker` with `custom_fields` but the queried key absent:

```bash
cat > .tmp/smoke-test-missing-key.yaml <<'EOF'
issue_tracker:
  provider: github_projects
  project_number: 1
  custom_fields:
    cycle: sprint-42
EOF
```

### Step 1: Verify backward compatibility — no `custom_fields` section

**Maps to**: AC-1 (existing scripts unaffected), business rule (omitting `custom_fields` preserves current behaviour)

```bash
source scripts/development-workflow/workflow-lib.sh
result=$(workflow_issue_tracker_custom_field project .tmp/smoke-test-no-cf.yaml)
echo "Result: '${result}'"
```

**Expected result**: Output is `Result: ''` (empty string). Exit code is `0`.

### Step 2: Verify reading a present custom field value

**Maps to**: AC-2 (helper function returns configured value), Use Case 3

```bash
source scripts/development-workflow/workflow-lib.sh
result=$(workflow_issue_tracker_custom_field project .tmp/smoke-test-with-cf.yaml)
echo "Result: '${result}'"
```

**Expected result**: Output is `Result: 'my-linear-project-id'`. Exit code is `0`.

### Step 3: Verify missing key returns empty string

**Maps to**: AC-2 (missing key returns empty string), business rule (missing key → empty string)

```bash
source scripts/development-workflow/workflow-lib.sh
result=$(workflow_issue_tracker_custom_field project .tmp/smoke-test-missing-key.yaml)
echo "Result: '${result}'"
```

**Expected result**: Output is `Result: ''` (empty string). Exit code is `0`.

### Step 4: Verify absent config file returns empty string

**Maps to**: AC-1 (no error when config absent), business rule (backward compatibility)

```bash
source scripts/development-workflow/workflow-lib.sh
result=$(workflow_issue_tracker_custom_field project /nonexistent/path.yaml)
echo "Result: '${result}'"
```

**Expected result**: Output is `Result: ''` (empty string). Exit code is `0`.

### Step 5: Verify `.ai-dev-workflow.yaml` has a commented `custom_fields` block

**Maps to**: AC-6 (inline comments document the section with an example)

```bash
grep -A 6 "custom_fields" .ai-dev-workflow.yaml
```

**Expected result**: Output shows the commented `custom_fields` block with a Linear `project` example. No uncommented `custom_fields:` key should appear in the output (the default must be fully commented).

### Step 6: Verify Linear integration doc documents the `project` custom field

**Maps to**: AC-3 (Linear doc lists `project` as a recognised custom field)

```bash
grep -A 5 "Custom Fields" docs/workflow/development-workflow/integrations/linear.md
```

**Expected result**: Output shows a "Custom Fields" section that names `project` as a recognised key, its expected format (Linear project ID), and the effect when set.

### Step 7: Verify GitHub Projects integration doc states no fields are recognised

**Maps to**: AC-4 (GitHub Projects doc states no custom fields currently recognised)

```bash
grep -A 5 "Custom Fields" docs/workflow/development-workflow/integrations/github-projects.md
```

**Expected result**: Output shows a "Custom Fields" section stating that no `custom_fields` keys are currently recognised by workflow scripts for this provider.

### Last Step: Cleanup and validate

```bash
rm -f .tmp/smoke-test-no-cf.yaml .tmp/smoke-test-with-cf.yaml .tmp/smoke-test-missing-key.yaml
```

---

## Assertions Checklist

- [ ] AC-1: `custom_fields` absent → `workflow_issue_tracker_custom_field` returns empty string, exit 0
- [ ] AC-2: `custom_fields.project: my-linear-project-id` → function returns `my-linear-project-id`
- [ ] AC-2: key absent in `custom_fields` → function returns empty string, exit 0
- [ ] AC-1: config file absent → function returns empty string, exit 0
- [ ] AC-6: `.ai-dev-workflow.yaml` contains a commented `custom_fields` block with a Linear `project` example
- [ ] AC-3: `linear.md` documents `project` as a recognised custom field with format and effect
- [ ] AC-4: `github-projects.md` states no custom fields are currently recognised

---

## Seed Data Reference

None — this feature is configuration-driven and requires no database or seed-data.

| Entity | Scenario | How to load |
|---|---|---|
| N/A | — | — |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Function not found after sourcing | `workflow-lib.sh` not updated yet | Verify the `workflow_issue_tracker_custom_field` function is present in the file |
| Returns value when `custom_fields` is absent | AWK parser exiting too early | Check the `in_custom` flag logic; ensure it only activates after the `custom_fields:` line |
| Returns empty when key is present | Indentation mismatch | Confirm the YAML uses four-space indentation under `custom_fields:`; the AWK parser expects exactly four spaces |
| Reads value from wrong section | Parser not scoped to `issue_tracker` | Verify the `^issue_tracker:` anchor fires before `in_custom` is set |

---

## Known Limitations

- The helper function expects exactly two-space indentation for `custom_fields:` under `issue_tracker:` and four-space indentation for keys under `custom_fields:`. YAML files using tabs or non-standard indentation will not be parsed correctly.
- Nested values under a custom field key (e.g., `project:\n  id: foo`) are out of scope (flat string values only, per spec Out of Scope section).
