# Custom Fields Support for Issue Tracker Configuration — Spec

**Issue**: #453

---

## Overview

Different issue trackers support provider-specific fields beyond the basic identifiers currently declared in `.ai-dev-workflow.yaml`. For example, Linear teams can have multiple projects, but the current configuration only supports a team identifier. This feature adds a flexible custom fields map to the issue tracker configuration, with each integration's documentation defining which fields are supported and how they map to the provider's API.

---

## Brief Coverage

| Brief Objective                                                     | Spec Trace                 |
| ------------------------------------------------------------------- | -------------------------- |
| Schema change in `.ai-dev-workflow.yaml` to add `custom_fields` map | AC-1, AC-6, Use Case 1     |
| Update `workflow-lib.sh` to read and expose custom fields           | AC-2, Use Case 3           |
| Update Linear integration docs with supported custom fields         | AC-3                       |
| Update scripts that create issues to use project field when present | AC-5, Use Case 1           |
| Integration docs define which fields are supported per tracker      | AC-3, AC-4, Business Rules |

---

## Use Cases

### Use Case 1: Configure a Linear project for issue creation

**Actor**: Repository maintainer
**Preconditions**: The repository uses Linear as its issue tracker (declared in `.ai-dev-workflow.yaml`)

**Steps**:

1. The maintainer opens `.ai-dev-workflow.yaml`
2. Under `issue_tracker`, the maintainer adds a `custom_fields` map with a `project` key set to the Linear project identifier
3. Workflow scripts that create or query issues use the project field when interacting with the Linear API

**Postconditions**: New issues created by workflow scripts are associated with the specified Linear project

**Considerations**:

- If `custom_fields.project` is omitted, issue creation proceeds without a project association (current behavior preserved)
- The project identifier format depends on the tracker provider (Linear uses a project slug or ID)

---

### Use Case 2: Add a tracker-specific field not yet consumed by scripts

**Actor**: Repository maintainer
**Preconditions**: The repository uses any supported issue tracker

**Steps**:

1. The maintainer adds a new key under `custom_fields` (e.g., `cycle`, `label_prefix`, or a provider-specific concept)
2. The field is stored in the configuration and accessible via the helper function
3. No existing script behavior changes until a script is updated to read the new field

**Postconditions**: The custom field value is available for scripts and agents to query. Unrecognized fields are ignored by scripts that do not consume them.

**Considerations**:

- The configuration is a flat key-value map — nested structures are out of scope for the initial version
- Each integration document defines which keys are recognized and what they do

---

### Use Case 3: Read a custom field from a workflow script

**Actor**: Workflow script or agent
**Preconditions**: A custom field is declared in `.ai-dev-workflow.yaml`

**Steps**:

1. The script calls a helper function (e.g., `workflow_issue_tracker_custom_field <field_name>`) from `workflow-lib.sh`
2. The function reads the value from the YAML configuration
3. The script uses the value in its API call or logic

**Postconditions**: The script has the configured value, or an empty string if the field is not set

**Considerations**:

- The helper function must handle missing `custom_fields` section gracefully (return empty string)
- The helper function must handle missing individual keys gracefully (return empty string)

---

## Business Rules

- Custom fields are optional — omitting the entire `custom_fields` section preserves current behavior for all scripts
- Custom fields are a flat string-to-string map at the YAML level (no nested objects)
- Each tracker integration document is the authoritative source for which custom field keys are recognized and how they are used
- Unrecognized custom field keys are silently ignored by scripts that do not consume them (no warnings, no errors)
- The `custom_fields` section belongs under `issue_tracker` in `.ai-dev-workflow.yaml`, alongside `provider` and `project_number`

---

## Acceptance Criteria

- [ ] A `custom_fields` map can be declared under `issue_tracker` in `.ai-dev-workflow.yaml` without breaking any existing script
- [ ] `workflow-lib.sh` exposes a function to read an individual custom field by name, returning an empty string when the field or section is absent
- [ ] The Linear integration document lists `project` as a recognized custom field with its expected format and effect
- [ ] The GitHub Projects integration document states that no custom fields are currently recognized (for completeness)
- [ ] Scripts that create Linear issues (if any exist) pass the `project` value when configured
- [ ] The `.ai-dev-workflow.yaml` inline comments document the `custom_fields` section with an example

---

## Out of Scope (MVP)

- Nested or structured custom field values (arrays, objects) — flat string values only
- Validation of custom field values against the tracker API at configuration time
- Custom fields for non-tracker integrations (review platforms, VCS, browser automation)
- Automatic migration of existing `project_number` into `custom_fields` — the GitHub Projects `project_number` field remains where it is
