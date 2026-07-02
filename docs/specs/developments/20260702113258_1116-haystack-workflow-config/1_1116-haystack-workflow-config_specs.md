# Haystack Workflow Configuration - Spec

**Epic**: #1112 External review loop - Haystack advisory hardening
**Depends on**: #1113 Structured Haystack Advisory Findings, #1114 Advisory Disposition Triggers, #1115 Machine-readable False-positive Catalog

---

## Overview

Workflow maintainers need Haystack reviewer behavior to be configured from the
repository workflow configuration instead of only through ad hoc environment
variables. This feature gives repositories an explicit Haystack configuration
surface for severity policy, polling cadence, timeout limits, and stop-rule
behavior while preserving environment-variable overrides for one-off local or
CI adjustments.

The outcome is a review loop whose Haystack behavior is discoverable in the
same configuration family as the rest of the review workflow. Operators can see
the intended defaults, override them intentionally, and validate configuration
mistakes before they affect pull request readiness.

## Brief Objective List

Derived from issue #1116:

1. Add a Haystack review configuration section to the workflow configuration
   schema with settings for major-finding blocking policy, poll interval,
   timeout, maximum triage rounds, and no-progress cycles.
2. Ensure the Haystack reviewer reads repository configuration while preserving
   environment-variable overrides as the higher-priority runtime override.
3. Document the configuration in Haystack triage guidance and in the local
   workflow configuration example.
4. Add validation so invalid Haystack configuration is caught by the existing
   workflow configuration validation path or an equivalent workflow validation
   surface.

## Use Cases

### Use Case 1: Maintainer sets repository Haystack defaults

**Actor**: Workflow maintainer.
**Preconditions**: The repository uses Haystack as an automated PR reviewer and
has a workflow configuration file.

**Steps**:

1. The maintainer opens the repository workflow configuration.
2. The maintainer finds the Haystack review configuration section.
3. The maintainer sets the major-finding policy, polling interval, timeout, and
   stop-rule values that match the repository's review tolerance.
4. The maintainer runs the normal configuration validation path.
5. The maintainer opens or updates a pull request that uses the reviewer loop.

**Postconditions**: Haystack reviewer runs use the repository defaults unless a
runtime override is explicitly supplied.

**Information shown**:

- The available Haystack settings and their expected value types.
- Validation feedback when a setting is missing, misspelled, or invalid.
- Reviewer-loop output that reflects the effective behavior.

**Actions available**:

- Add or edit repository defaults.
- Correct validation failures.
- Keep existing behavior by omitting the optional configuration section.

**Considerations**:

- Existing repositories without the new section must continue using current
  defaults and environment-variable behavior.
- The configuration must be understandable without reading reviewer script
  internals.

### Use Case 2: Operator overrides Haystack behavior for one run

**Actor**: Workflow operator running an automated reviewer loop.
**Preconditions**: The repository has Haystack defaults configured, and the
operator needs a temporary override for a single run or CI job.

**Steps**:

1. The operator sets a supported environment-variable override for the run.
2. The operator starts the reviewer loop.
3. The reviewer loop applies the runtime override ahead of the repository
   default.
4. The reviewer loop finishes using the effective values for that invocation.

**Postconditions**: The one-off override affects only the invocation where it is
set; repository defaults remain unchanged.

**Information shown**:

- The documented override precedence.
- Reviewer-loop behavior consistent with the effective configuration.

**Actions available**:

- Use repository defaults.
- Apply a one-run override.
- Remove the override and return to repository defaults.

**Considerations**:

- Runtime overrides must not silently rewrite repository configuration.
- Operators need deterministic precedence so they can debug review behavior.

### Use Case 3: Invalid Haystack configuration is caught early

**Actor**: Workflow maintainer or CI job validating workflow configuration.
**Preconditions**: A repository configuration includes Haystack settings.

**Steps**:

1. The validator reads the workflow configuration.
2. The validator checks Haystack settings for supported names, value types, and
   valid ranges.
3. The validator reports any invalid setting in a clear failure message.
4. The maintainer corrects the configuration and reruns validation.

**Postconditions**: Invalid Haystack configuration is rejected before it can
change reviewer-loop behavior.

**Information shown**:

- Which setting is invalid.
- Why the setting is invalid.
- The expected type or range.

**Actions available**:

- Fix invalid values.
- Remove optional settings to fall back to defaults.
- Rerun validation.

**Considerations**:

- Validation failures should be specific enough for maintainers to correct the
  configuration without inspecting implementation code.
- Optional omission should not be treated as invalid.

## Business Rules

- The repository workflow configuration may define an optional Haystack review
  configuration section.
- The supported settings are:
  - `major_is_blocking`
  - `poll_interval_sec`
  - `timeout_sec`
  - `stop_rule.max_triage_rounds`
  - `stop_rule.no_progress_cycles`
- Environment-variable overrides remain supported and take precedence over
  repository defaults for the invocation where they are set.
- Repositories that omit the Haystack section keep the existing default behavior.
- Invalid configured values must fail validation rather than being ignored
  silently.
- Poll interval, timeout, maximum triage rounds, and no-progress cycles must be
  positive whole-number settings.
- The major-finding policy must be a binary setting.
- Stop-rule settings must be documented as readiness-control settings, not as a
  substitute for CI, reviewer findings, or human checkpoints.

## Statuses / Enum Values

No workflow item statuses are introduced.

The feature adds these configuration display concepts:

| Concept | Display label | Description |
| ------- | ------------- | ----------- |
| Major-finding policy | Major findings block readiness | Controls whether Haystack major findings are treated as blocking by default. |
| Poll interval | Poll interval seconds | Controls how often the reviewer loop checks for Haystack completion. |
| Timeout | Timeout seconds | Controls how long the reviewer loop waits for Haystack before escalating. |
| Maximum triage rounds | Maximum triage rounds | Controls the maximum number of Haystack triage rounds before the loop stops. |
| No-progress cycles | No-progress cycles | Controls how many unchanged triage cycles are allowed before the loop stops. |

## Operational Visibility

- **Configuration guidance**: Haystack triage documentation explains the
  available settings, defaults, and override precedence.
- **Local example**: The local workflow configuration example shows the
  Haystack section with safe example values.
- **Validation output**: The workflow configuration validator identifies invalid
  Haystack settings by name.
- **Reviewer-loop behavior**: The reviewer loop uses the effective values from
  environment overrides, repository configuration, or built-in defaults in that
  order.

## Acceptance Criteria

- [ ] AC-1: The workflow configuration supports an optional Haystack review
      section with settings for major-finding policy, poll interval, timeout,
      maximum triage rounds, and no-progress cycles.
- [ ] AC-2: When the Haystack section is omitted, existing reviewer-loop
      behavior and defaults continue to apply.
- [ ] AC-3: When valid Haystack settings are present, the reviewer loop uses
      those values for Haystack review behavior.
- [ ] AC-4: Environment-variable overrides take precedence over repository
      Haystack settings for the invocation where they are set.
- [ ] AC-5: Invalid Haystack settings are reported by the workflow configuration
      validation path with setting-specific feedback.
- [ ] AC-6: Haystack triage documentation explains the settings, defaults,
      override precedence, and stop-rule purpose.
- [ ] AC-7: The local workflow configuration example shows the Haystack section
      with representative values.

## Coverage Matrix

| Brief objective | Coverage |
| --------------- | -------- |
| Add a Haystack review configuration section with major policy, poll interval, timeout, max triage rounds, and no-progress cycles. | AC-1, AC-2, AC-3 |
| Preserve environment-variable override precedence while reading repository configuration. | AC-3, AC-4 |
| Document the configuration in Haystack guidance and the local workflow configuration example. | AC-6, AC-7 |
| Validate invalid Haystack configuration through the workflow validation surface. | AC-5 |

## Out of Scope (MVP)

- Adding new external reviewer providers.
- Changing Haystack's upstream review behavior or reviewer API.
- Replacing existing environment-variable overrides.
- Changing delegated merge, CI, or human-checkpoint gate policy.
- Implementing project-specific downstream defaults outside this template.
