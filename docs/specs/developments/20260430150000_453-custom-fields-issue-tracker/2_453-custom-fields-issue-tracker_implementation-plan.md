# Custom Fields Support for Issue Tracker Configuration — Implementation Plan

**Spec**: [`1_453-custom-fields-issue-tracker_specs.md`](1_453-custom-fields-issue-tracker_specs.md)
**Smoke test runbook**: [`docs/testing/workflow/custom-fields-issue-tracker.smoke-test.md`](../../../testing/workflow/custom-fields-issue-tracker.smoke-test.md)

---

## Summary

**Approach**: Add a `custom_fields` flat map under `issue_tracker` in `.ai-dev-workflow.yaml` (with inline comments and a documented example), then introduce a new `workflow_issue_tracker_custom_field <key>` helper function in `workflow-lib.sh` that reads individual custom field values using a three-level YAML parser (section → subsection → key). Update both the Linear and GitHub Projects integration docs to document which custom field keys each provider recognises. No existing script behaviour changes — all additions are purely opt-in.

**Estimated complexity**: S

**Rationale**: Only three files change (`.ai-dev-workflow.yaml`, `workflow-lib.sh`, two integration docs). The YAML parsing pattern already exists in `workflow_config_field`; the new helper follows the same `awk`-based approach extended by one nesting level. No logic-path changes to existing consumers.

**Dependencies**: None

---

## Verification Log

| Check                                             | Command / query                                                                                        | Result                                                                                                                                                              |
| ------------------------------------------------- | ------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Repo revision                                     | `git rev-parse --short HEAD`                                                                           | `efdc8e6`                                                                                                                                                           |
| Existing issue-tracker helpers in workflow-lib.sh | `grep -n "workflow_issue_tracker\|workflow_config_field" scripts/development-workflow/workflow-lib.sh` | Lines 215–258: `workflow_config_field`, `workflow_issue_tracker_project_number`, `workflow_issue_tracker_provider_raw`, `workflow_normalize_issue_tracker_provider` |
| Scripts importing workflow-lib.sh                 | `grep -rl "workflow-lib.sh" scripts/development-workflow/`                                             | `workflow-batch-plan.sh`, `workflow-lib.sh`, `workflow-next-action.sh`, `add-backlog-item.sh`                                                                       |
| Any existing `custom_fields` references           | `grep -rn "custom_fields" .ai-dev-workflow.yaml scripts/ docs/`                                        | Only in the spec file (no prior implementation)                                                                                                                     |
| Linear issue-creation scripts                     | `grep -rn "linear" scripts/ --include="*.sh"`                                                          | `add-backlog-item.sh` lines 37, 111–113: Linear creation exits non-zero with guidance; no project-field logic present                                               |
| Issue-tracker integration docs                    | `ls docs/workflow/development-workflow/integrations/`                                                  | `github-projects.md`, `linear.md` both confirmed present                                                                                                            |

---

## Layer-by-Layer Changes

### Infrastructure / Configuration

- [ ] `.ai-dev-workflow.yaml` — add a commented `custom_fields` subsection under `issue_tracker` documenting the flat map pattern with a Linear example (`project: <project-id>`). The section must be present but commented out in the template default, preserving current behaviour (AC-1, AC-6).

### Shared Packages / Libraries

- [ ] `scripts/development-workflow/workflow-lib.sh` — add `workflow_issue_tracker_custom_field <key> [config_file]` function that parses `issue_tracker.custom_fields.<key>` from the YAML config using the same `awk`-based approach as `workflow_config_field`, extended one level deeper (AC-2, Use Case 3).

### Documentation

- [ ] `docs/workflow/development-workflow/integrations/linear.md` — add a **Custom Fields** section listing `project` as the supported key, its expected format (Linear project ID string), and its effect on issue creation when set (AC-3).
- [ ] `docs/workflow/development-workflow/integrations/github-projects.md` — add a **Custom Fields** section stating that no custom fields are currently recognised by workflow scripts for this provider (AC-4).

---

## Testing Strategy

**Test types**: Smoke (manual verification against the config file and helper function output)

**Key scenarios to test**:

1. `custom_fields` section absent from `.ai-dev-workflow.yaml` — `workflow_issue_tracker_custom_field project` returns empty string (AC-1, business rule: backward-compat)
2. `custom_fields` present with `project: my-linear-project` — `workflow_issue_tracker_custom_field project` returns `my-linear-project` (AC-2, Use Case 3)
3. `custom_fields` present but queried key absent — `workflow_issue_tracker_custom_field nonexistent-key` returns empty string (AC-2, business rule: missing key → empty string)
4. `.ai-dev-workflow.yaml` absent entirely — function returns empty string without error (AC-1)
5. Unrecognised key in `custom_fields` — existing scripts continue to work unchanged (AC-1, business rule: unrecognised keys silently ignored)

**Smoke test runbook**: `docs/testing/workflow/custom-fields-issue-tracker.smoke-test.md`

**Regression suite**: No automated regression suite exists in this repository; the smoke test runbook covers manual verification.

---

## Seed Data

None — this feature is configuration-driven; no database or seed-data changes.

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/integrations/linear.md` — add **Custom Fields** section (covered in Layer-by-Layer Changes above; listed here per documentation update requirement)
- [ ] `docs/workflow/development-workflow/integrations/github-projects.md` — add **Custom Fields** section (covered in Layer-by-Layer Changes above)

No changes required to `docs/project/`, `docs/best-practices/`, or `AGENTS.md` — this feature adds a config-layer extension with no user-facing workflow behaviour change.

---

## Risks & Mitigations

| Risk                                                                         | Likelihood | Impact | Mitigation                                                                                                                                                                                              |
| ---------------------------------------------------------------------------- | ---------- | ------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| AWK parser misreads indented `custom_fields` key as a subsection exit signal | Low        | Med    | Test parser with config file containing `custom_fields` at two-space indent below `issue_tracker`; validate against the exit condition `^[^[:space:]#].*:[[:space:]]*$` which only fires at zero indent |
| Trailing comment on a `custom_fields` value line stripped incorrectly        | Low        | Low    | Follow same `sub(/[[:space:]]+#.*$/, "", line)` pattern already used in `workflow_config_field`; all four existing callers rely on this and work correctly                                              |
| New helper not sourced by callers that need it                               | Low        | Low    | The helper lives in `workflow-lib.sh`, which is already sourced by every relevant script; no additional sourcing required                                                                               |

---

## Code Samples

> All samples below are **illustrative — adapt during implementation**.

### `workflow_issue_tracker_custom_field` implementation in `workflow-lib.sh`

```bash
# Illustrative — adapt during implementation

# workflow_issue_tracker_custom_field <key> [config_file]
#
# Reads issue_tracker.custom_fields.<key> from .ai-dev-workflow.yaml.
# Prints the value, or empty string when:
#   - The config file is absent
#   - The custom_fields subsection is absent
#   - The key is absent within custom_fields
# Returns 0 in all cases (non-blocking).
workflow_issue_tracker_custom_field() {
  local key="$1"
  local config_file="${2:-$(workflow_config_file)}"

  [ -f "$config_file" ] || return 0

  awk -v key="$key" '
    function trim(value) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      gsub(/^["'"'"']|["'"'"']$/, "", value)
      return value
    }

    /^issue_tracker:[[:space:]]*(#.*)?$/ {
      in_section = 1
      in_custom = 0
      next
    }

    in_section && /^[^[:space:]#]/ {
      in_section = 0
      in_custom = 0
    }

    in_section && /^[[:space:]][[:space:]]custom_fields:[[:space:]]*(#.*)?$/ {
      in_custom = 1
      next
    }

    in_section && in_custom && /^[[:space:]][[:space:]][A-Za-z0-9_-]+:/ {
      # Any two-space-indented non-custom_fields key exits the custom_fields block
      # unless it is a four-space-indented key (those belong to custom_fields)
      if ($0 !~ /^[[:space:]][[:space:]][[:space:]][[:space:]]/) {
        in_custom = 0
      }
    }

    in_section && in_custom && /^[[:space:]][[:space:]][[:space:]][[:space:]]/ {
      pattern = "^[[:space:]][[:space:]][[:space:]][[:space:]]" key ":[[:space:]]*"
      if ($0 ~ pattern) {
        line = $0
        sub(/^[[:space:]]*[^[:space:]]*:[[:space:]]*/, "", line)
        sub(/[[:space:]]+#.*$/, "", line)
        print trim(line)
        exit
      }
    }
  ' "$config_file"
}
```

### `.ai-dev-workflow.yaml` `custom_fields` addition (illustrative placement)

```yaml
# Illustrative — adapt during implementation
issue_tracker:
  provider: github_projects
  project_number: 1
  # custom_fields: flat key-value map of provider-specific fields.
  # Each integration doc defines which keys are recognised and their effect.
  # Unrecognised keys are silently ignored by scripts that do not consume them.
  # Example (Linear):
  #   custom_fields:
  #     project: my-linear-project-id
  # custom_fields:
  #   project: ""
```

---

## Implementation Order

1. **Add `custom_fields` section to `.ai-dev-workflow.yaml`** — Insert the commented `custom_fields` block immediately after `project_number: 1` inside `issue_tracker`. The block must be commented out (no active `custom_fields:` key) so current behaviour is fully preserved. Include inline comments documenting the flat map expectation and a Linear `project` example.

   Verify: open `.ai-dev-workflow.yaml` and confirm the `custom_fields` block is present under `issue_tracker`, fully commented, and that running existing scripts (e.g., `bash scripts/development-workflow/workflow-lib.sh` sourced test) produces no errors.

2. **Add `workflow_issue_tracker_custom_field` to `workflow-lib.sh`** — Insert the new function after the `workflow_issue_tracker_project_number` function (line ~254). Follow the `awk`-based parsing pattern from `workflow_config_field`. The function signature is `workflow_issue_tracker_custom_field <key> [config_file]`.

   Verify: source `workflow-lib.sh` in a shell and run the following checks:
   - Call with no `custom_fields` in config → empty output, exit 0
   - Call with `custom_fields:\n    project: test-id` in a temp config → output `test-id`
   - Call with a missing key → empty output, exit 0

3. **Update `docs/workflow/development-workflow/integrations/linear.md`** — Add a **Custom Fields** section (after the **Branch Naming with Linear** section) documenting:
   - Key: `project`
   - Format: Linear project ID string (obtainable from the Linear project URL or API)
   - Effect: when set and a script creates issues via the Linear API, the `project` value is passed as the project association
   - When absent: issue creation proceeds without a project association (current behaviour preserved)

   Verify: confirm the section is present and the key, format, and effect are clearly documented.

4. **Update `docs/workflow/development-workflow/integrations/github-projects.md`** — Add a **Custom Fields** section (after the **Prerequisites** section) stating:
   - No `custom_fields` keys are currently recognised by workflow scripts for the `github_projects` provider
   - The `project_number` field remains a top-level `issue_tracker` field, not a custom field
   - Future provider-specific fields may be added here as the integration evolves

   Verify: confirm the section is present and accurately states no fields are currently recognised.

5. **Update `CHANGELOG.md`** under `[Unreleased]` — add:

   ```
   - **Add custom_fields support for issue tracker config** (#453): Adds a `custom_fields` flat map under `issue_tracker` in `.ai-dev-workflow.yaml` and a `workflow_issue_tracker_custom_field` helper function in `workflow-lib.sh` to read individual custom field values. Updates Linear and GitHub Projects integration docs to document recognised fields.
   ```

6. **Verify smoke test runbook** — run through `docs/testing/workflow/custom-fields-issue-tracker.smoke-test.md` to confirm all acceptance criteria pass.

7. **Update project docs per Documentation Updates section** — Linear and GitHub Projects integration doc updates are already completed in steps 3–4 above.
