# Haystack Workflow Configuration - Implementation Plan

**Spec**: [Haystack Workflow Configuration - Spec](1_1116-haystack-workflow-config_specs.md)
**Smoke test runbook**: [1116 Haystack workflow configuration smoke test](../../../testing/workflow/1116-haystack-workflow-config.smoke-test.md)

---

## Summary

**Approach**: Extend the existing standard-library workflow config resolver with
validated `review.haystack` settings and a shell-safe command that prints the
effective Haystack defaults. Update `haystack-reviewer.sh` to read those
defaults before applying existing environment-variable and CLI overrides, then
document the configuration surface and add focused shell tests.

**Estimated complexity**: M

**Rationale**: The change spans the YAML subset parser, validation behavior, a
stateful polling shell script, docs, examples, and regression tests. No external
API or database change is required, but the stop-rule behavior needs careful
bounded-loop semantics.

**Dependencies**: #1113, #1114, and #1115 must be merged first because this work
builds on the structured advisory output, disposition handling, and
false-positive catalog behavior those items introduced.

---

## Verification Log

| Check | Command / query | Result |
| ----- | --------------- | ------ |
| Repo revision | `git rev-parse --short HEAD` | `07dcc73` |
| Current Haystack runtime controls | `rg -n "HAYSTACK_REVIEWER_TIMEOUT\|HAYSTACK_POLL_INTERVAL\|HAYSTACK_MAJOR_IS_BLOCKING\|HAYSTACK_PR_STATUS_CHECK\|HAYSTACK_FALSE_POSITIVES_FILE" scripts/development-workflow/haystack-reviewer.sh docs/workflow/development-workflow/integrations/haystack-triage.md scripts/development-workflow/tests/test-haystack-reviewer.sh` | Existing runtime settings are script/env-driven in `haystack-reviewer.sh`; docs mention timeout, poll interval, major policy, and false-positive catalog overrides. |
| Workflow config resolver surface | `rg -n "workflow-config-resolver\|validate\|review:" scripts/development-workflow/workflow-config-resolver.py scripts/development-workflow/validate-workflow-config.sh scripts/development-workflow/tests/test-workflow-config-resolver.sh .ai-dev-workflow.yaml .ai-dev-workflow.local.example.yaml` | `validate` currently routes through resolver context loading; review local override support exists, but no Haystack-specific schema exists. |
| Reviewer-loop Haystack dispatch | `rg -n "run_haystack_review\|haystack-reviewer.sh" scripts/development-workflow/pr-review-loop.sh scripts/development-workflow/tests/test-pr-review-loop.sh` | `pr-review-loop.sh` delegates Haystack behavior to `haystack-reviewer.sh` and passes only `--timeout` from reviewer-loop max wait. |

---

## Layer-by-Layer Changes

### Database / Data Layer

- [ ] No database or seed-data changes are required.

### Backend / API

- [ ] No service endpoint or external API changes are required.

### Shared Packages / Libraries

- [ ] `scripts/development-workflow/workflow-config-resolver.py`:
  - Add validation helpers for optional `review.haystack` settings in shared
    and local workflow configs.
  - Support only these keys: `major_is_blocking`, `poll_interval_sec`,
    `timeout_sec`, and `stop_rule` with `max_triage_rounds` and
    `no_progress_cycles`.
  - Require `major_is_blocking` to be a boolean.
  - Require all numeric settings to be positive integers.
  - Reject unknown Haystack keys with setting-specific error messages.
  - Preserve omission semantics: no section, missing nested `stop_rule`, or
    omitted optional keys stays valid and falls back to defaults.
  - Add a `review-haystack` command that prints shell-safe values such as
    `HAYSTACK_CONFIG_TIMEOUT_SEC`, `HAYSTACK_CONFIG_POLL_INTERVAL_SEC`,
    `HAYSTACK_CONFIG_MAJOR_IS_BLOCKING`, `HAYSTACK_CONFIG_MAX_TRIAGE_ROUNDS`,
    and `HAYSTACK_CONFIG_NO_PROGRESS_CYCLES`.
- [ ] `scripts/development-workflow/validate-workflow-config.sh`: keep the
  wrapper contract intact while ensuring the resolver's validation path checks
  the new Haystack schema.

### Frontend / UI

- [ ] No frontend or UI changes are required.

### Infrastructure / Configuration

- [ ] `.ai-dev-workflow.yaml`: add a commented or inactive example for
  `review.haystack` near the existing review configuration so template
  consumers can discover supported shared defaults.
- [ ] `.ai-dev-workflow.local.example.yaml`: add a local override example for
  `review.haystack` with representative safe values.
- [ ] `scripts/development-workflow/haystack-reviewer.sh`:
  - Resolve the repository root with `git rev-parse --show-toplevel`, falling
    back to the current directory only when Git metadata is unavailable.
  - Invoke `workflow-config-resolver.py review-haystack --repo-root <root>` and
    fail closed with exit code `3` when config parsing or validation fails.
  - Apply precedence in this order:
    - `--timeout` CLI flag for timeout only.
    - Existing environment variables:
      `HAYSTACK_REVIEWER_TIMEOUT`, `HAYSTACK_POLL_INTERVAL`,
      `HAYSTACK_MAJOR_IS_BLOCKING`.
    - Repository config from `review.haystack`.
    - Current built-in defaults: timeout `120`, poll interval `15`, major
      findings advisory by default.
  - Keep `HAYSTACK_PR_STATUS_CHECK` and `HAYSTACK_FALSE_POSITIVES_FILE` as
    environment-only controls because they are outside the #1116 config scope.
  - Implement stop-rule settings inside the existing triage poll loop:
    - `max_triage_rounds` caps the number of `haystack triage --no-wait` calls
      and exits `RESULT=skipped`, `REASON=max_triage_rounds` when exhausted
      before a completed result appears.
    - `no_progress_cycles` compares a stable transient-progress signature
      derived from status value plus finding/category counts available in the
      transient payload and exits `RESULT=skipped`, `REASON=no_progress_cycles`
      when the same signature repeats for the configured number of cycles.
    - A completed Haystack payload still exits the loop before stop rules can
      turn a completed result into a skipped result.
- [ ] `scripts/development-workflow/pr-review-loop.sh`: update only comments or
  field forwarding if `haystack-reviewer.sh` adds new `REASON` values; keep the
  existing companion-script call contract unless tests show the wrapper needs
  explicit pass-through.

---

## Testing Strategy

**Test types**: Unit, integration-style shell tests, smoke, and documentation lint.

**Key scenarios to test**:

1. Missing `review.haystack` preserves current defaults and behavior (AC-2).
2. Valid shared config values are emitted by the resolver and used by
   `haystack-reviewer.sh` (AC-1, AC-3).
3. Local config can override shared Haystack defaults through the same local
   config family as existing review overrides (AC-3).
4. Environment variables override repository config for timeout, poll interval,
   and major policy (AC-4).
5. `--timeout` overrides both env and config for timeout when
   `pr-review-loop.sh` supplies a max-wait budget (AC-4).
6. Invalid booleans, numeric values, unknown keys, and malformed YAML fail
   validation with setting-specific feedback (AC-5).
7. Stop-rule thresholds terminate only transient polling and never suppress a
   completed Haystack result (AC-1, AC-3).
8. Documentation and examples describe settings, defaults, and precedence
   consistently (AC-6, AC-7).

**Smoke test runbook**:
`docs/testing/workflow/1116-haystack-workflow-config.smoke-test.md`

**Regression suite**: Extend the shell regression tests that already cover the
resolver and Haystack reviewer. No browser or product-app regression suite
applies to this workflow-script feature.

### Parser-risk addendum

This plan is parser-risk because it changes structured YAML parsing and
validation behavior in `workflow-config-resolver.py`.

**Edge-case enumeration**:

- Missing `review.haystack` section in a valid config.
- Empty `review.haystack: {}` equivalent represented by an empty mapping.
- Boolean values `true` and `false` for `major_is_blocking`.
- Negative boolean lookalikes such as `"true"`, `yes`, `1`, and `blocking`.
- Positive integer values for `poll_interval_sec`, `timeout_sec`,
  `stop_rule.max_triage_rounds`, and `stop_rule.no_progress_cycles`.
- Negative numeric lookalikes: `0`, `-1`, `1.5`, `"15"`, and `fifteen`.
- Unknown top-level Haystack key under `review.haystack`.
- Unknown nested key under `review.haystack.stop_rule`.
- `stop_rule` present as a scalar or list instead of a mapping.
- Shared config plus local config where local Haystack values intentionally
  override shared values.
- Malformed YAML indentation under `review.haystack`.
- Environment values overriding parsed repository values without rewriting
  config files.
- CLI `--timeout` overriding env and repository timeout values.
- Transient Haystack status repeating the same progress signature until
  `no_progress_cycles` is exhausted.
- Transient Haystack polling reaching `max_triage_rounds` before completion.
- Haystack completion arriving before either stop-rule threshold is reached.

**Unit test mapping**:

- `scripts/development-workflow/tests/test-workflow-config-resolver.sh`:
  missing section, empty mapping, valid booleans, invalid boolean lookalikes,
  valid positive integers, invalid numeric lookalikes, unknown keys, malformed
  YAML, `stop_rule` type validation, nested stop-rule key validation, and
  shared-plus-local override precedence.
- `scripts/development-workflow/tests/test-haystack-reviewer.sh`: config-derived
  timeout, poll interval, major policy, env override precedence, CLI timeout
  precedence, `max_triage_rounds`, `no_progress_cycles`, and completion before
  stop-rule exhaustion.
- `scripts/development-workflow/tests/test-pr-review-loop.sh`: only update if
  new `REASON` fields or wrapper comments need assertion coverage.

**Suppression semantics**: Not applicable. This feature does not add inline
suppression directives or rule-specific suppression parsing.

---

## Seed Data

No persistent seed data is required.

| Entity | Values / Scenario | File |
| ------ | ----------------- | ---- |
| Temporary workflow config fixture | Shared and local `review.haystack` variants created by shell tests | `scripts/development-workflow/tests/test-workflow-config-resolver.sh` |
| Mock Haystack responses | Pending, repeated-progress, and completed JSON payloads | `scripts/development-workflow/tests/test-haystack-reviewer.sh` |

---

## Documentation Updates

- [ ] `.ai-dev-workflow.yaml` - show the optional shared `review.haystack`
  configuration surface.
- [ ] `.ai-dev-workflow.local.example.yaml` - show local override examples for
  Haystack reviewer behavior.
- [ ] `docs/workflow/development-workflow/integrations/haystack-triage.md` -
  document settings, defaults, precedence, validation, and stop-rule purpose.
- [ ] `docs/project/2-repo-architecture.md` - no update; placeholder project
  architecture is not changed by workflow script configuration.
- [ ] `docs/project/3-software-architecture.md` - no update; the tech stack and
  architecture patterns do not change.
- [ ] `docs/project/4-database-model.md` - no update; no data model change.
- [ ] `AGENTS.md` - no update; command workflow and agent guidance are unchanged.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| ---- | ---------- | ------ | ---------- |
| Config validation rejects existing repositories unexpectedly | Low | Medium | Keep the whole section optional and validate only present `review.haystack` keys. |
| Env/config precedence becomes ambiguous | Medium | Medium | Implement a single resolver load step, then explicit assignment order in `haystack-reviewer.sh`, with tests for config, env, and CLI precedence. |
| Stop-rule thresholds skip a completed analysis | Low | High | Check for completed payload before applying stop-rule exits and add tests where completion arrives before thresholds. |
| Shell config loading introduces quoting issues | Medium | Medium | Use resolver shell-safe output with `shlex.quote`; avoid hand-parsing YAML in shell. |
| Local config accidentally becomes shared policy | Low | Medium | Keep local overrides in `.ai-dev-workflow.local.example.yaml` and do not commit `.ai-dev-workflow.local.yaml`. |

---

## Implementation Order

1. Extend `workflow-config-resolver.py` with Haystack config normalization and
   validation helpers for shared and local configs.
2. Add the `review-haystack` resolver command and shell-safe output fields.
3. Add resolver tests for valid configs, invalid configs, unknown keys, malformed
   YAML, and local-overrides-shared precedence.
4. Update `haystack-reviewer.sh` to load config defaults, preserve env/CLI
   precedence, validate effective values, and emit clear errors on invalid
   config.
5. Implement `max_triage_rounds` and `no_progress_cycles` in the existing
   transient-status poll loop.
6. Extend `test-haystack-reviewer.sh` for config-derived defaults, env override
   precedence, CLI timeout precedence, and both stop-rule exits.
7. Update `pr-review-loop.sh` and `test-pr-review-loop.sh` only if the wrapper
   needs to recognize or forward new reason fields beyond its current generic
   forwarding.
8. Update `.ai-dev-workflow.yaml`, `.ai-dev-workflow.local.example.yaml`, and
   `docs/workflow/development-workflow/integrations/haystack-triage.md`.
9. Update `CHANGELOG.md` under `[Unreleased]` with this literal entry:
   `- **Haystack workflow configuration** (#1116): Added repository-level Haystack reviewer settings with validation, override precedence, and stop-rule documentation.`
10. Run verification:
    - `bash scripts/development-workflow/tests/test-workflow-config-resolver.sh`
    - `bash scripts/development-workflow/tests/test-haystack-reviewer.sh`
    - `bash scripts/development-workflow/tests/test-pr-review-loop.sh` if
      `pr-review-loop.sh` or its tests are touched.
    - `bash scripts/development-workflow/validate-workflow-config.sh`
    - `shellcheck --severity=warning -x scripts/development-workflow/haystack-reviewer.sh scripts/development-workflow/validate-workflow-config.sh scripts/development-workflow/tests/test-haystack-reviewer.sh scripts/development-workflow/tests/test-workflow-config-resolver.sh`
    - `python3 scripts/lint/workflow-shell-guard-lint.py --base-ref origin/develop`
    - `npx markdownlint-cli2 "docs/specs/developments/**/*.md" "docs/testing/workflow/**/*.md" "CHANGELOG.md"`
    - `find docs/specs/developments docs/testing/workflow -name "*.md" -print0 | xargs -0 python3 scripts/lint/markdown-heuristic-lint.py CHANGELOG.md`
    - `bash scripts/lint/check-changelog-duplicate-headers.sh CHANGELOG.md`
    - `git diff --check`

