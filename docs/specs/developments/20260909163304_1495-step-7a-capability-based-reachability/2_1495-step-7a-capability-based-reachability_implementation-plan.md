# Step 7a Capability-Based Reviewer Reachability — Implementation Plan

**Spec**: [`1_1495-step-7a-capability-based-reachability_specs.md`](1_1495-step-7a-capability-based-reachability_specs.md)
**Smoke test runbook**: [`../../../testing/workflow/1495-step-7a-capability-based-reachability.smoke-test.md`](../../../testing/workflow/1495-step-7a-capability-based-reachability.smoke-test.md)
**Issue**: #1495

---

## Summary

**Approach**: Replace Protocol 91's static runner-identity reachability table with a deterministic
helper script, `scripts/development-workflow/resolve-reviewer-availability.sh`, that reads the
unavailable-reviewer policy first, resolves the effective reviewer list through a new
`workflow-config-resolver.py review-effective` subcommand, marks override exclusions, probes each
remaining reviewer against the environment under a fixed ten-second budget, applies the policy, and
prints a `KEY=value` verdict block the gate reports verbatim. The shipped default
`review.on_draft.runner` changes from `[codex]` to `[claude, cursor, codex]` so that whichever
supported runner drives the gate, that runner's own reviewer is reachable by construction. The
canonical protocol regains `codex-github` as a supported runner reviewer value (hosted-service
kind), and six mirror surfaces are corrected so no surface attributes availability to runner
identity.

**Estimated complexity**: M

<!-- S: < 1 day | M: 1-3 days | L: 3+ days -->

**Rationale**: One new ~350-line shell script with a fully enumerated output contract, one new
Python subcommand with parse-state detection, two new/extended test suites, one shipped
configuration change, and edits to nine documentation or agent surfaces. No new runtime dependency
and no new concurrency. The bulk of the risk is in getting the state enumeration and the reason
categories exactly right, not in the volume of code. Cross-runner Codex invocation — the piece that
would normally be the unknown — is already shipped and exercised in this repository (see Decision 5
and VL-6).

**Dependencies**: None. The merged spec is the only prerequisite.

---

## Verification Log

All commands were run at repo revision `8971ba12` (`origin/develop`) on 2026-09-09T21:43:29Z from
the repository root.

| Check | Command / query | Result |
| --- | --- | --- |
| VL-1 — Repo revision | `git rev-parse --short HEAD` | `8971ba12` |
| VL-2 — Live surfaces naming the reviewer key | `grep -rln "on_draft\.runner\|internal_reviewers" --include="*.md" --include="*.yaml" . \| sed 's\|^\./\|\|' \| grep -v node_modules \| grep -Ev '^(docs/specs/developments/\|docs/testing/\|CHANGELOG\.md$)' \| sort` | 15 paths. All 15 are classified in **Surface disposition** below; 9 change, 6 do not. Historical `docs/specs/developments/**` and `docs/testing/**` artifacts and `CHANGELOG.md` are excluded as records of past decisions, not live surfaces. |
| VL-3 — Canonical anchors in Protocol 91 | `grep -n "Supported runner reviewer values\|default behavior: \`claude\`\|Reachability classification table\|runner identity is a sufficient proxy" docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` | Lines 1658 (supported values), 1661 (fallback names `claude`), 1672 (identity-proxy sentence), 1674 (table heading) |
| VL-4 — "Universally reachable" claims | `grep -rn "universally reachable" --include="*.md" --include="*.sh" . \| grep -v node_modules` | 6 hits. Four are live surfaces and all four change: `.claude/agents/item-orchestrator.md:198`, `.cursor/agents/item-orchestrator.md:205`, `scripts/development-workflow/codex-github-reviewer.sh:5`, `scripts/development-workflow/claude-code-action-reviewer.sh:9`. Two are historical records left alone: `CHANGELOG.md:2557` and a 2026-05 development artifact. |
| VL-5 — README fallback statement | `grep -n "falls back to running the stage-appropriate" docs/workflow/development-workflow/README.md` | Line 561, naming a fixed `claude` reviewer |
| VL-6 — Cross-runner Codex invocation already ships | `grep -n "exec --sandbox read-only" scripts/development-workflow/local-codex-review-command.sh; grep -n "local-codex-review-command" scripts/development-workflow/local-ai-reviewer.sh` | `local-codex-review-command.sh:39` assembles `codex_args=(exec --sandbox read-only ...)`; `local-ai-reviewer.sh:103` selects that script as the default backend preset. Cross-runner Codex invocation is shipped behavior, not new machinery. |
| VL-7 — Bounded-call and command-probe helpers already exist | `grep -n "^gh_api_bounded()\|^have_cmd()\|^gh_available()\|^reviewer_for_branch()" scripts/development-workflow/workflow-lib.sh` | Lines 182, 186, 217, 485. `gh_api_bounded` already returns `124` on timeout and honours `WORKFLOW_GH_API_TIMEOUT_SECONDS`. |
| VL-8 — Resolver reads only the local file today | `grep -n "def resolve_review_overrides" -A 12 scripts/development-workflow/workflow-config-resolver.py` | `resolve_review_overrides` parses `.ai-dev-workflow.local.yaml` only; the shipped `.ai-dev-workflow.yaml` list is left for the caller to read by hand. This is why a new subcommand is needed rather than extra keys on `review-overrides`. |
| VL-9 — `list_override_from_path` conflates absent with non-list | `grep -n "def list_override_from_path" -A 10 scripts/development-workflow/workflow-config-resolver.py` | Returns `([], False)` both when the key is missing and when it is present but not a list. This is the specific defect that makes "malformed blocks, absent falls back" unimplementable today. |
| VL-10 — Test-suite discovery is convention-driven | `grep -n "covers:" scripts/development-workflow/select-test-suites.sh \| head -3` and `head -3 scripts/development-workflow/tests/test-local-ai-reviewer.sh` | Suites are discovered from a `# covers:` header or the `test-<script>.sh` naming convention. A new suite needs no `.github/workflows/workflow-tests.yml` edit. |
| VL-11 — Hermetic mock-PATH test pattern exists | `sed -n '12,32p' scripts/development-workflow/tests/test-local-ai-reviewer.sh` | The suite builds temporary `PATH` directories from symlinks to real coreutils plus fake binaries. This is the pattern the availability tests reuse (see **Testing Strategy**). |
| VL-12 — Sync manifest coverage | `grep -n "scripts/development-workflow/" sync-manifest.yaml` | Line 105 covers the directory at `hub_only` scope via `glob: "**/*"`; lines 109-129 add explicit `product_repo_injection` entries for the seven runtime helpers a product repo needs. |
| VL-13 — Bounded same-surface open-PR scan | `gh pr list --state open --limit 50 --json number,title,headRefName` | Empty. No open pull request touches `review.on_draft.runner`, Protocol 91 Step 7a, or the reviewer-availability surface. |
| VL-14 — Local runtimes present on the authoring machine | `command -v claude cursor-agent codex; codex --version` | All three resolve under `~/.local/bin`; `codex-cli 0.150.1`. Recorded because it is the exact environment the current identity table classifies as Codex-unreachable. |

---

## Cross-Cutting Operational Assumption Check

### Applicable

| Assumption surface | Recorded value | Authoritative source | Verified at | Bounded cross-check scope | Result |
| --- | --- | --- | --- | --- | --- |
| Shipped default `review.on_draft.runner` | `[codex]` today; this plan changes it to `[claude, cursor, codex]` | `.ai-dev-workflow.yaml` lines 52-59 | 2026-09-09T21:43:29Z at `8971ba12` | This invocation carries only item #1495. VL-13 shows zero open pull requests, so no sibling work can be changing the same key. | `Verified` |
| Plan artifact base branch and artifact owner | Base `develop`; the current repository owns the plan (`mode` absent in `.ai-dev-workflow.yaml`, so `single_repo`) | `.ai-dev-workflow.yaml` (no `mode` key); `run-nested-artifact-guard.sh --mode pre-create` returned `RESULT=clean`, `APPROVED_BASE=develop` | 2026-09-09T21:43:29Z at `8971ba12` | Same invocation; guard scan found `CANONICAL_COUNT=0`, `UNEXPECTED_COUNT=0` | `Verified` |
| Machine-local override in the authoring checkout | `.ai-dev-workflow.local.yaml` sets `review.on_draft.runner: [claude]`; the file is gitignored (`.gitignore:9`) and must never enter a diff | `git check-ignore -v .ai-dev-workflow.local.yaml`; `git status --porcelain` empty | 2026-09-09T21:43:29Z at `8971ba12` | Same invocation | `Verified` |

No conflicts were found, so no evidence needs returning to the parent orchestrator.

---

## Definitions

These terms are load-bearing and are used with exactly these meanings everywhere in this plan, in
the protocol text it produces, and in the smoke runbook.

- **Driving runner** — the agent runtime executing the internal review gate for this pull request.
  Its kind is one of `claude`, `cursor`, `codex`, or `unknown`. `unknown` means the gate was invoked
  from a context that provides no stage reviewer of its own (a bare shell, a CI harness).
- **Supported runner** — a driving runner whose kind is `claude`, `cursor`, or `codex`. These are
  exactly the kinds that supply a stage reviewer, which is what makes the spec's fallback reachable
  by construction. A bare shell or CI harness is not a supported runner; the spec's Use Case 3
  explicitly does not promise a reviewer there.
- **Local-runtime reviewer** — a configured reviewer dispatched by invoking a command on this
  machine: `claude`, `cursor`, `codex`.
- **Hosted-service reviewer** — a configured reviewer dispatched by asking a service installed on
  the repository to review: `coderabbit`, `codex-github`. It needs no local runtime beyond an
  authenticated `gh`.
- **Availability probe** — the single bounded, read-only check that decides one reviewer's
  classification. It never dispatches a review.
- **Availability budget** — the fixed ten-second wall-clock ceiling covering resolution of the whole
  configured list, from the moment the resolver starts.

---

## Decisions

Each decision is referenced by these indices throughout the plan.

### Decision 1 — Availability probing lives in a new dedicated helper script

`scripts/development-workflow/resolve-reviewer-availability.sh` owns environment probing, budget
enforcement, policy application, and the verdict report. It is a new file rather than an extension
of an existing one.

**Alternatives rejected:**

- *Protocol-level prose only* (tell the agent to run `command -v codex`). Rejected: prose is exactly
  what produced the defect. The spec sets a hard ten-second ceiling, a mandatory four-category reason
  vocabulary, and a fixed evaluation order — none of which prose can guarantee, and none of which is
  testable. Every other deterministic gate in this repository (`pr-review-loop.sh`,
  `pr-ci-loop.sh`, `run-epic-delegated-gate.sh`) is a script with a `KEY=value` contract.
- *Extend `workflow-config-resolver.py` to do the probing.* Rejected: the resolver is contractually
  forbidden from invoking `git` or `gh` — the docstring at `workflow-config-resolver.py:300-312`
  records that callers such as `run-epic-policy-recommender.sh` depend on it staying process-free.
  Hosted-service probing needs `gh`. Mixing the two would break an existing contract.
- *Fold it into `pr-review-loop.sh`.* Rejected: that script owns Step 7 (external reviewers), which
  the spec places out of scope (Out of Scope item 4). Step 7a and Step 7 must not share an entry
  point.

### Decision 2 — Config reading stays in `workflow-config-resolver.py`, via a new `review-effective` subcommand

The Python resolver already owns YAML parsing, local-override precedence, and worktree-aware
override location. It gains one subcommand that returns the *effective* list and policy — shipped
file merged with local override — plus explicit parse-state fields. The shell script consumes it and
does no YAML parsing of its own.

**Alternatives rejected:**

- *Use the awk readers in `workflow-lib.sh`* (`workflow_config_review_nested_list`). Rejected: they
  return an empty list for absent, empty, and malformed input alike, so "malformed blocks, absent
  falls back" is unimplementable on top of them. They stay in place for `pr-review-loop.sh`
  (Step 7); this plan does not unify the two readers — see **Out-of-scope notes**.
- *Parse the YAML in the new shell script.* Rejected: a third parser for the same file.

### Decision 3 — Identity can make a reviewer reachable; it can never make one unreachable

A reviewer is Reachable when the driving runner's kind equals the reviewer value, **or** when the
capability probe for that reviewer succeeds. Identity is one more piece of evidence for capability —
a Claude Code session can dispatch a Claude reviewer subagent whether or not a `claude` binary is on
`PATH` — and it is never evidence against it. This is the precise reading of the spec's rule that
"the driving runner counts as one of the runtimes present in the environment; it does not exclude
the others". When the driving runner's kind is `unknown`, the identity branch contributes nothing
and capability alone decides.

### Decision 4 — The shipped default reviewer list becomes `[claude, cursor, codex]`

This is the only list that satisfies the spec's guarantee literally: for every environment in which
a supported runner drives the gate, the list names at least one reviewer reachable in that
environment — the driving runner's own, reachable by Decision 3.

**Alternatives rejected:**

- *Ship no list and rely on the fallback.* Rejected: the acceptance criterion says "The shipped
  default reviewer **list names** at least one reviewer that is reachable…", which presupposes a
  list. Shipping none would satisfy the behavior and fail the criterion.
- *Ship `[codex-github]`.* Rejected: it needs the Codex GitHub App installed on the repository. A
  fresh downstream repository without it would block — trading a runner trap for an installation
  trap. This is also the configuration that #486 deliberately moved out of Step 7a.
- *Ship `[codex, codex-github]` or `[claude, codex]`.* Rejected: each leaves at least one supported
  runner with nothing reachable (a Cursor machine with neither CLI installed, respectively).
- *Introduce a new sentinel value such as `runner-native`.* Rejected as scope creep: the spec
  authorizes the canonical list to name `codex-github`, and nothing else new. A sentinel would also
  blur the spec's deliberate separation between a configured reviewer and the fallback.

**Accepted cost**: under the default `warn` policy, a machine that reaches only some of the three
gets a reduced-coverage warning naming the others. That warning is accurate — the operator's
configured intent genuinely was not fully met — and Use Case 4's override is the documented way to
narrow it. It never blocks. On the authoring machine all three runtimes are present (VL-14), so the
warning does not fire there at all.

### Decision 5 — Cross-runner `codex` dispatch uses `codex exec --sandbox read-only`

When the driving runner is Codex, the `codex` reviewer is dispatched as the Codex review skill
exactly as today. When the driving runner is not Codex and the `codex` binary is callable, the same
stage reviewer is dispatched through `codex exec --sandbox read-only`, which is the invocation shape
already shipped in `local-codex-review-command.sh` and already exercised from non-Codex sessions
(VL-6). The prompt names the stage reviewer's protocol and `REVIEW.md`, and requires the response to
end with a single line `VERDICT: APPROVED` or `VERDICT: NEEDS REVISION`.

A non-zero exit, a missing verdict line, or an unparseable response is a **review failure**, never an
unreachability verdict — availability was already settled before dispatch. This is protocol prose,
not a new script: `claude` and `cursor` dispatch are prose in the same table, and building a fourth
dispatcher would exceed the spec.

### Decision 6 — Probes are sequential, not parallel

The budget is enforced by an absolute deadline plus per-probe clamping (see **The availability
budget**), which bounds a sequential walk just as tightly as a parallel one for a list of at most
five entries whose slowest probe is a single `gh` GET. Sequential probing keeps the run log ordered
and deterministic and introduces no shared mutable state across execution contexts — which is why
the concurrent-event-source classifier does not apply.

### Decision 7 — `codex-github` returns to the canonical Step 7a list as an opt-in hosted-service reviewer

The spec requires the canonical protocol to list it. It is **not** added to the shipped default
(Decision 4), so the async-dispatch concern recorded in #486 — which moved it from Step 7a to Step 7
— does not reappear by default. Repositories that opt in get a documented synchronous dispatch path
through `codex-github-reviewer.sh`, whose exit codes are already defined at
`codex-github-reviewer.sh:29-35`.

---

## Contracts

### `workflow-config-resolver.py review-effective`

```text
python3 scripts/development-workflow/workflow-config-resolver.py review-effective \
  --repo-root <path> [--json]
```

Read-only. Never invokes `git` or `gh`. Emits `KEY=value` lines (or one JSON object with `--json`):

| Key | Values |
| --- | --- |
| `EFFECTIVE_RUNNER_LIST` | comma-joined reviewer values, empty when none resolve |
| `EFFECTIVE_RUNNER_STATE` | `defined` / `absent` / `empty` / `malformed` |
| `EFFECTIVE_RUNNER_SOURCE` | absolute path of the file the list came from, or empty |
| `SHIPPED_RUNNER_LIST` | the `.ai-dev-workflow.yaml` list, for reporting what an override replaced |
| `OVERRIDE_EXCLUDED_LIST` | entries in `SHIPPED_RUNNER_LIST` that the override left out, empty when no override is in effect |
| `EFFECTIVE_POLICY` | `warn` / `fail-if-any-unavailable` / the offending raw value / empty |
| `EFFECTIVE_POLICY_STATE` | `defined` / `absent` / `empty` / `unsupported` / `unreadable` |
| `EFFECTIVE_POLICY_SOURCE` | absolute path of the file the policy came from, or empty |
| `UNREADABLE_FILE` | absolute path of the configuration file that would not parse, or empty |
| `UNREADABLE_DETAIL` | the parser's message, or empty |
| `LOCAL_OVERRIDE_FILE`, `LOCAL_OVERRIDE_ORIGIN`, `MAIN_CLONE_LOCAL_OVERRIDE_FILE` | reused verbatim from the existing `review-overrides` output, so the `<local-override-state>` reporting introduced by #1560 keeps working unchanged |

Exit codes: `0` always when the command ran, including for `malformed`, `unsupported`, and
`unreadable` states — those are **data**, reported in the state fields, not crashes. `2` only for
argument errors or an unreadable `--repo-root`. A `ConfigError` raised while parsing either
configuration file is caught and reported as `EFFECTIVE_POLICY_STATE=unreadable` plus
`EFFECTIVE_RUNNER_STATE=malformed` with `UNREADABLE_FILE` naming the file — the existing
`review-overrides` behavior of exiting `2` on `ConfigError` is unchanged, because other callers
depend on it.

**Why a whole-file parse failure reports as a policy-input failure**: the policy is read first, and a
file that will not parse makes the policy input unreadable. Under the fixed evaluation order the
gate therefore blocks on the policy and names the file — which satisfies both "with a configuration
file that will not parse at all, the gate blocks and names that file" and "with the policy
unsupported or unreadable and the reviewer list absent, empty, or malformed at the same time, the
gate blocks on the policy". The two criteria agree; they are not two different outcomes.

### `resolve-reviewer-availability.sh`

```text
scripts/development-workflow/resolve-reviewer-availability.sh \
  --repo-root <path> --owner <owner> --repo <repo> [--runner-kind claude|cursor|codex|unknown]
```

`--runner-kind` defaults to `$WORKFLOW_RUNNER_KIND`, then to `unknown`. There is no budget flag: the
availability budget is a fixed property of the gate, and the internal override
`WORKFLOW_REVIEWER_AVAILABILITY_BUDGET_SECONDS` is honoured **only** when
`WORKFLOW_REVIEWER_AVAILABILITY_TEST_MODE=1` is also set, so no operator can shorten or lengthen it
on a real run.

Emits one `REVIEWER` record per configured entry, in configured order, followed by the summary
block:

```text
REVIEWER <name> <status> <reason-or-hyphen> <detail>
...
RUNNER_KIND=<claude|cursor|codex|unknown>
BUDGET_SECONDS=10
ELAPSED_SECONDS=<integer>
POLICY=<warn|fail-if-any-unavailable>
POLICY_SOURCE=<path|default>
POLICY_STATE=<defined|absent|empty|unsupported|unreadable>
CONFIG_LIST_STATE=<defined|absent|empty|malformed|not-evaluated>
CONFIG_LIST_SOURCE=<path|>
LOCAL_OVERRIDE_STATE=<none|<file> (<origin>), applied|present but unpropagated: <file>>
CONFIGURED=<comma list>
OVERRIDE_EXCLUDED=<comma list>
REACHABLE=<comma list>
UNREACHABLE=<comma list>
FALLBACK_APPLIED=<true|false>
OUTCOME=<proceeded|proceeded-reduced|blocked>
BLOCK_CAUSE=<none|policy-unreadable|policy-unsupported|list-malformed|zero-reachable|policy-forbids-reduced-coverage|no-driving-runner>
```

`CONFIG_LIST_STATE=not-evaluated` appears only when the run blocked on the policy before resolving
the list, which is what makes the fixed evaluation order visible in the output.

`LOCAL_OVERRIDE_STATE` reuses the three #1560 forms verbatim, derived from `LOCAL_OVERRIDE_FILE`,
`LOCAL_OVERRIDE_ORIGIN`, and `MAIN_CLONE_LOCAL_OVERRIDE_FILE` — never inferred.

**Exit codes** (complete):

| Exit | Meaning | `OUTCOME` printed | What the gate does |
| --- | --- | --- | --- |
| `0` | The gate may dispatch | `proceeded` or `proceeded-reduced` | Dispatch `REACHABLE`, or the driving runner's stage reviewer when `FALLBACK_APPLIED=true`. Post the reduced-coverage warning first when `OUTCOME=proceeded-reduced`. |
| `1` | The gate must block | `blocked` | Dispatch nobody, leave the pull request draft, post the hard-fail comment naming `BLOCK_CAUSE`, escalate to a human |
| `2` | The resolver could not run at all | none | Treat as blocked with cause `availability-resolver-failed`; the hard-fail comment quotes the resolver's stderr. This is not a reviewer verdict — no reviewer was classified. |

**Purity guarantee**: the script performs only `command -v`, `<binary> --version`, `gh api` GET
requests, and reads of `.coderabbit.yaml`. It never calls `gh pr comment`, `gh pr ready`, or any
mutating `gh api` verb, and writes nothing outside `$TMPDIR`. This is enforced by two tests, not by
convention — see **Testing Strategy** T-14 and T-15.

### Availability probe table (complete, all supported values)

`runtime-absent` is only ever produced for a local-runtime reviewer; `prerequisite-missing` is only
ever produced for a hosted-service reviewer. Both invariants are asserted by tests.

| Value | Kind | `reachable` when | `runtime-absent` when | `prerequisite-missing` when | `check-inconclusive` when |
| --- | --- | --- | --- | --- | --- |
| `claude` | local-runtime | `RUNNER_KIND=claude`, or `claude` resolves on `PATH` and `claude --version` exits `0` within its bound | not on `PATH` and `RUNNER_KIND` is not `claude` | never | on `PATH` but `--version` exits non-zero, or the bound elapsed |
| `cursor` | local-runtime | `RUNNER_KIND=cursor`, or `cursor-agent` resolves on `PATH` and `cursor-agent --version` exits `0` within its bound | not on `PATH` and `RUNNER_KIND` is not `cursor` | never | on `PATH` but `--version` exits non-zero, or the bound elapsed |
| `codex` | local-runtime | `RUNNER_KIND=codex`, or `codex` resolves on `PATH` and `codex --version` exits `0` within its bound | not on `PATH` and `RUNNER_KIND` is not `codex` | never | on `PATH` but `--version` exits non-zero, or the bound elapsed |
| `coderabbit` | hosted-service | the repository shows `coderabbitai[bot]` activity **and** `.coderabbit.yaml` sets `reviews.auto_review.enabled: true` | never | the activity signal is definitively absent, or `auto_review.enabled` is not `true` | `gh` is missing or unauthenticated, the API call errored, or the bound elapsed |
| `codex-github` | hosted-service | the repository shows activity from `${CODEX_GITHUB_BOT_LOGIN:-chatgpt-codex-connector[bot]}` | never | the activity signal is definitively absent | `gh` is missing or unauthenticated, the API call errored, or the bound elapsed |
| any other value | unsupported | never | never | never | never — the entry is `unreachable` with reason `value-not-supported` and no probe is run |

**Why an absent `gh` is `check-inconclusive` and not `runtime-absent`**: `gh` is not the hosted
reviewer's runtime — the reviewer runs on GitHub's servers. Without `gh` the question "is the
service installed for this repository" was never asked, let alone answered, so reporting
`runtime-absent` or `prerequisite-missing` would send the operator to fix something that may be
perfectly fine. That is exactly the case the spec assigns to `check-inconclusive`.

**Hosted-service activity probe**: one bounded call,
`gh api "repos/<owner>/<repo>/issues/comments?per_page=100"`, matching the bot login with and
without its `[bot]` suffix (GraphQL omits the suffix; the REST login carries it — the repository
already documents this at Protocol 91 and in `codex-github-reviewer.sh`). `coderabbit.md` documents
two alternatives for this signal, `gh api repos/{owner}/{repo}/installation` **or** recent-comment
inspection; the gate uses the second because the first only answers under GitHub App authentication,
which the gate does not hold. Selecting between two already-documented alternatives is not a change
to CodeRabbit's determination.

**Known limitation**: an app that is installed but has never commented on the repository classifies
as `prerequisite-missing`. The remedy the report offers — verify the app is installed for this
repository — is the correct action either way, and neither hosted reviewer is in the shipped
default. Recorded in **Risks & Mitigations** R-3.

### The availability budget

Three constants, named once and used with these names everywhere:

| Constant | Value | Role |
| --- | --- | --- |
| `AVAILABILITY_BUDGET_SECONDS` | `10` | Wall-clock ceiling for resolving the whole configured list |
| `LOCAL_PROBE_CAP_SECONDS` | `3` | Per-probe cap for a local-runtime reviewer |
| `HOSTED_PROBE_CAP_SECONDS` | `5` | Per-probe cap for a hosted-service reviewer |

Enforcement:

1. The script records `deadline = now + AVAILABILITY_BUDGET_SECONDS` as its **first** action, before
   invoking the config resolver. The spec's criterion measures from "starting to resolve the list",
   so resolver time counts against the budget.
2. Before each probe, `remaining = deadline - now`. If `remaining <= 0`, that reviewer and every one
   after it is recorded `unreachable` / `check-inconclusive` with detail
   `availability budget exhausted before this check started`, and no probe runs.
3. Otherwise the probe runs with bound `min(remaining, cap)` for its kind. If it does not finish, the
   reviewer is `unreachable` / `check-inconclusive` with detail `check exceeded its <n>s bound`.
4. `ELAPSED_SECONDS` is printed so a run that came close to the ceiling is visible in the log.

Because the deadline is absolute and every per-probe bound is clamped to the remaining budget, total
probing time cannot exceed `AVAILABILITY_BUDGET_SECONDS` for any list length. The per-reviewer caps
are subordinate to the ceiling, never additive to it.

Bounding mechanism: `gh_api_bounded` from `workflow-lib.sh` for hosted probes, exporting
`WORKFLOW_GH_API_TIMEOUT_SECONDS` set to the computed bound (it already returns `124` on timeout,
VL-7); a local `run_bounded` helper of the same shape — GNU `timeout --kill-after` when available,
otherwise a `setsid`-plus-poll fallback — for `--version` probes. `run_bounded` is a new function in
`resolve-reviewer-availability.sh` rather than an extraction from `local-ai-reviewer.sh`; see
**Out-of-scope notes** for why that duplication is deliberate.

### Fixed evaluation order

The script executes exactly these phases, in this order, and the output makes the order visible:

1. **Read the policy.** `unreadable` → block, `BLOCK_CAUSE=policy-unreadable`. `unsupported` → block,
   `BLOCK_CAUSE=policy-unsupported`. `absent` or `empty` → `POLICY=warn`, `POLICY_SOURCE=default`.
   Both block paths print `CONFIG_LIST_STATE=not-evaluated`.
2. **Resolve the list.** `malformed` → block, `BLOCK_CAUSE=list-malformed`. `absent` or `empty` →
   `FALLBACK_APPLIED=true`, jump to phase 6.
3. **Mark override exclusions.** Entries in `SHIPPED_RUNNER_LIST` absent from the override list
   become `override-excluded`. They are never probed, which is why "excluded and also unreachable"
   is not a reachable combination.
4. **Probe** each remaining entry under the budget.
5. **Apply the policy** to the resulting classification set.
6. **Report** the verdict block and exit.

---

## Decision-Gate Consistency Matrix

The internal review gate is a complex workflow decision gate and this plan changes one of its
inputs, so the gate's inputs, outcomes, next actions, mirror surfaces, and examples are enumerated
here. This matrix restates the spec's matrix in the terms this plan implements; where the spec
speaks of a classification, this table names the field of `resolve-reviewer-availability.sh` that
carries it.

### Gate inputs

| Input | Where the implementation reads it | Field that carries it |
| --- | --- | --- |
| The configured reviewer list | `review-effective` `EFFECTIVE_RUNNER_LIST` | `CONFIGURED` |
| Which reviewers the override left out | `review-effective` `OVERRIDE_EXCLUDED_LIST` | `OVERRIDE_EXCLUDED` |
| Whether each reviewer can be invoked here | The availability probe table. **Changed by this feature**: was the driving runner's identity, is now capability | `REVIEWER <name> <status>` |
| The reason a reviewer cannot be invoked | The same probe | `REVIEWER <name> unreachable <reason>` |
| The unavailable-reviewer policy | `review-effective` `EFFECTIVE_POLICY` and `EFFECTIVE_POLICY_STATE` | `POLICY`, `POLICY_STATE` |
| Whether each configured value is supported | The probe table's final row | `value-not-supported` reason |
| The driving runner's kind | `--runner-kind` / `$WORKFLOW_RUNNER_KIND` | `RUNNER_KIND` |

### Allowed outcomes and required next actions

Every row is reachable under the fixed evaluation order. Combinations that the order makes
unreachable are listed under the table so their absence is not read as an omission.

| Gate input state | `OUTCOME` | `BLOCK_CAUSE` | Exit | What the gate does | Operator's next action |
| --- | --- | --- | --- | --- | --- |
| Policy unreadable, list in any state | `blocked` | `policy-unreadable` | `1` | Dispatches nobody; names the input that could not be read and the file; prints `CONFIG_LIST_STATE=not-evaluated` | Correct the unreadable input |
| Policy present but not a supported value, list in any state | `blocked` | `policy-unsupported` | `1` | Dispatches nobody; names the offending value; prints `CONFIG_LIST_STATE=not-evaluated` | Correct the policy value |
| Policy readable; list defined but not a list of values, or its file will not parse | `blocked` | `list-malformed` | `1` | Dispatches nobody; names the file and the input; does not fall back | Correct the malformed input |
| Policy readable; no list in either file, or a list resolving to no entries; driving runner supported | `proceeded` | `none` | `0` | Runs the driving runner's own stage reviewer once; `FALLBACK_APPLIED=true` | None |
| Policy readable; fallback path reached with `RUNNER_KIND=unknown` | `blocked` | `no-driving-runner` | `1` | Dispatches nobody; reports that no supported runner is driving the gate | Re-run from a supported runner |
| Every kept reviewer reachable | `proceeded` | `none` | `0` | Dispatches all of them; no warning comment | None |
| Some reviewers excluded by the override, every remaining one reachable | `proceeded` | `none` | `0` | Dispatches the kept subset; excluded entries reported `override-excluded` with no reason and no warning | None |
| At least one unreachable, at least one reachable, `POLICY=warn` | `proceeded-reduced` | `none` | `0` | Posts the reduced-coverage warning naming each unreachable reviewer, its reason and its remedy, then dispatches the rest | Optionally restore the missing runtime or prerequisite |
| At least one unreachable, at least one reachable, `POLICY=fail-if-any-unavailable` | `blocked` | `policy-forbids-reduced-coverage` | `1` | Dispatches nobody; names the policy as the cause; the reachable reviewer is still reported `reachable` | Restore the missing reviewer, or change the policy for this machine |
| No kept reviewer reachable, under either policy | `blocked` | `zero-reachable` | `1` | Dispatches nobody; reports every reviewer with its reason and `LOCAL_OVERRIDE_STATE` | Restore a runtime or prerequisite, or narrow the list locally |
| An unsupported value is the only kept entry | `blocked` | `zero-reachable` | `1` | Same as the row above; the record names the value with reason `value-not-supported` | Correct the configured value |
| The resolver itself could not run | none printed | not printed; the gate reports `availability-resolver-failed` | `2` | Treated as blocked; the hard-fail comment quotes the resolver's stderr | Fix the invocation or the missing dependency named on stderr |
| A reviewer is reachable, is dispatched, and then fails, errors, times out, or returns no parseable verdict | not an availability outcome | not applicable | not applicable | Reported through the gate's existing review-outcome handling | Address the review failure |

Unreachable combinations, stated so their absence is intentional:

- *Excluded by override and also unreachable* — exclusion is settled in phase 3 and excluded entries
  are never probed.
- *Unreadable or unsupported policy resolving to anything other than a block* — the policy is read in
  phase 1 and the run stops there, which is why both such rows print
  `CONFIG_LIST_STATE=not-evaluated`.
- *A malformed list reaching the fallback* — the fallback is entered only from `absent` or `empty`.
- *`runtime-absent` for a hosted-service reviewer, or `prerequisite-missing` for a local-runtime
  reviewer* — excluded by construction in the probe table and asserted by test T-25.

No outcome installs software, provisions access, substitutes a reviewer, or converts the pull
request out of draft.

### Mirror surfaces

| Surface | Relationship | How this plan satisfies it |
| --- | --- | --- |
| Protocol 91 Step 7a | Canonical | Rewritten to state capability, the supported values including `codex-github`, and the outcome and reason vocabulary above |
| `.claude/agents/item-orchestrator.md`, `.cursor/agents/item-orchestrator.md` | Restate `codex-github` dispatch | Keep naming the value; the unconditional-reachability claim becomes a hosted-service statement. Both files carry byte-identical text, verified in Implementation Order step 7 |
| `.ai-dev-workflow.yaml` and its commentary | Ships the default and explains it | New default list; the "expected behaviour — not a misconfiguration" block deleted |
| `integrations/coderabbit.md` | Already decides availability from runtime conditions | The two checks are untouched; one remedy cell that implied identity is reworded |
| Codex skills, Cursor rules, `AGENTS.md`, `docs/workflow/setup/protocol.md` | Point at the key without restating the rule | Left unchanged, as the spec permits |
| `README.md` configuration reference | Restates the fallback | Restated as the driving runner's own stage reviewer |

### Examples

Each example is an instance of exactly one row above; none contradicts the rule beside it.

| Situation | `OUTCOME` / `BLOCK_CAUSE` | Which row |
| --- | --- | --- |
| `runner: [codex]`, `RUNNER_KIND=claude`, `codex` callable | `proceeded` | Every kept reviewer reachable |
| The same repository where `codex` is not on `PATH` | `blocked` / `zero-reachable`, reason `runtime-absent` | No kept reviewer reachable |
| `runner: [claude, codex]`, `codex` absent, `POLICY=warn` | `proceeded-reduced` | At least one unreachable with `warn` |
| The same with `POLICY=fail-if-any-unavailable` | `blocked` / `policy-forbids-reduced-coverage` | Policy forbids reduced coverage |
| Override keeps `codex` of a shipped `[claude, cursor, codex]`, `codex` callable | `proceeded` | Some excluded, remaining reachable |
| `runner: [coderabbit]`, the app never active on the repository | `blocked` / `zero-reachable`, reason `prerequisite-missing` | No kept reviewer reachable |
| `runner: [codex-github]`, the app active, any `RUNNER_KIND` | `proceeded` | Every kept reviewer reachable |
| `runner: [codex-github]`, dispatched, then never answers | not an availability outcome | Review failure row |
| `runner: [typo-reviewer, codex]`, `codex` callable, `POLICY=warn` | `proceeded-reduced`, reason `value-not-supported` on the first entry | At least one unreachable with `warn` |
| `internal_reviewers_unavailable_policy: Warn` with no list configured | `blocked` / `policy-unsupported` | Policy unsupported |

---

## Layer-by-Layer Changes

### Infrastructure / Configuration

- [ ] `.ai-dev-workflow.yaml` — change `review.on_draft.runner` from `[codex]` to
      `[claude, cursor, codex]` (Decision 4). Extend the supported-values comment block with
      `codex-github` (Decision 7) and label each value local-runtime or hosted-service.
      **Delete** the "Runner-context constraint" comment block at lines 174-183 in its entirety —
      it is the shipped commentary that calls a hard-fail on a supported runner "expected behaviour
      — not a misconfiguration", which AC *The shipped default never traps* forbids. Replace it with
      commentary that states the default guarantee: each supported runner's own reviewer is reachable
      by construction, other entries are probed against this machine, and a local override narrows
      the list when an operator does not want the reduced-coverage warning. Update the
      `internal_reviewers_unavailable_policy` comment so it describes the policy input rather than
      "unreachable from the current runner".
      *Covers*: AC group *The shipped default never traps*.
- [ ] `sync-manifest.yaml` — add
      `scripts/development-workflow/resolve-reviewer-availability.sh` with
      `mode_scope: product_repo_injection`, alongside the existing `pr-review-loop.sh` and
      `workflow-config-resolver.py` entries (VL-12). Step 7a runs against product-owned
      implementation pull requests, so the helper must be injectable; the directory glob at line 105
      is `hub_only` and would not carry it.
      *Covers*: AC group *Surfaces agree* (a product repository must resolve the same verdicts).

### Shared Packages / Libraries

- [ ] `scripts/development-workflow/workflow-config-resolver.py` — add the `review-effective`
      subcommand and its `cmd_review_effective` handler per **Contracts**. Add
      `typed_value_from_path(data, path) -> tuple[Any, bool]` returning the raw value and whether the
      key was present, so `defined` / `absent` / `empty` / `malformed` can be told apart (VL-9).
      Leave `list_override_from_path`, `resolve_review_overrides`, and `cmd_review_overrides`
      behaviorally unchanged — other callers depend on them.
      *Covers*: AC group *Configuration inputs that are absent, empty, malformed, or unsupported*.
- [ ] `scripts/development-workflow/resolve-reviewer-availability.sh` — **new**. Implements the
      contract, the probe table, the budget, and the fixed evaluation order above. Sources
      `workflow-lib.sh` for `have_cmd`, `gh_available`, and `gh_api_bounded` (VL-7). Executable bit
      set; passes `shellcheck --severity=warning`.
      *Covers*: AC groups *Reachability follows capability*, *The operator can tell why*,
      *Policy behavior is preserved*.
- [ ] `scripts/development-workflow/codex-github-reviewer.sh` — header comment only. Replace
      "Classifies as universally reachable: requires only gh CLI access" (lines 5-7) with a statement
      that it is a hosted-service reviewer whose availability is decided at runtime from whether the
      Codex GitHub App is installed for the repository, and that no runner is inherently barred
      because it needs no local Codex runtime. No behavior change.
      *Covers*: AC "No surface claims the hosted-service reviewer is available from every runner
      unconditionally."
- [ ] `scripts/development-workflow/claude-code-action-reviewer.sh` — header comment only. Line 9
      carries the same "Classifies as universally reachable" sentence (VL-4), and lines 2-7 present
      the script as a Step 7a reviewer path. Apply the same hosted-service correction to the
      reachability sentence. Do **not** change its stage attribution or any behavior: this reviewer
      is dispatched through `review.on_ready.github`, which is Step 7 and out of scope
      (`integrations/claude-code-action.md:268`). Only the unconditional-availability claim is in
      scope, because it is a surface stating how a reviewer's availability is decided.
      *Covers*: AC "Every workflow surface that states which reviewers this gate supports, or how
      their availability is decided, must agree with the canonical protocol statement."

### Backend / Protocol surfaces

- [ ] `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` — **canonical**.
      - Line 1658: extend supported runner reviewer values to
        `claude`, `cursor`, `codex`, `coderabbit`, `codex-github`, each labelled local-runtime or
        hosted-service.
      - Line 1661: restate the fallback as the **driving runner's own stage reviewer**, not `claude`.
      - Lines 1670-1686 (*Runtime-availability check*): delete the sentence "runner identity is a
        sufficient proxy for reviewer reachability" and delete the *Reachability classification
        table* outright. Replace with: the fixed evaluation order, the `resolve-reviewer-availability.sh`
        invocation, its exit-code table, the probe table, the budget constants, and the
        status/reason vocabulary (`reachable`, `unreachable`, `override-excluded`;
        `runtime-absent`, `prerequisite-missing`, `check-inconclusive`, `value-not-supported`).
        Keep the existing note that `auto_review.drafts: false` is handled upstream by the
        draft-state pre-check and is not an unreachability condition.
      - Lines 1688-1716 (*Policy resolution*): keep both allowed policy values, their meanings, and
        the `warn` default unchanged. Extend the condition table with the three blocking
        configuration-input rows (`policy-unreadable`, `policy-unsupported`, `list-malformed`), the
        fallback row, and the `no-driving-runner` row.
      - Lines 1718-1726 (*Warning comment format*): replace `(<runner-context>)` with
        `(<reason-display-label>)` and add the remedy clause. New wording:
        `WARNING: internal_reviewer '<reviewer>' unreachable — <reason-display-label>. Remedy: <remedy>. Only '<reachable-list>' will run in this Step 7a cycle. Reviewer coverage is reduced from <total> to <reachable-count>.`
        Replace the worked example with one that names a reason rather than a runner.
      - Lines 1728-1751 (*Hard-fail comment format*): keep Case A and Case B, add Case C for a
        blocking configuration input. Every case names `BLOCK_CAUSE`, every unreachable reviewer with
        its reason display label, at least one remedy, and `LOCAL_OVERRIDE_STATE` taken from the
        resolver (`#1560`), never inferred. Remove "run Step 7a from a runner that supports all
        configured reviewers" as the leading remedy — it attributes the block to identity.
      - Lines 1753-1770 (*Reviewer dispatch map*): add three `codex-github` rows (one per branch
        class) dispatching `codex-github-reviewer.sh <pr_number> <owner> <repo>` with its documented
        exit codes; add the cross-runner `codex` dispatch note from Decision 5.
      - Lines 1822-1867 (*Step 7a summary comment*): require the per-reviewer verdict list — every
        configured reviewer with its display label, and its reason where Unreachable — plus the gate
        outcome. Update both worked examples so neither attributes a skip to a runner.
      *Covers*: every AC group.
- [ ] `docs/workflow/development-workflow/README.md` line 561 — restate the fallback as the driving
      runner's own stage reviewer for the pull request's stage. Add one sentence naming the shipped
      default list and the guarantee it carries.
      *Covers*: AC "The reviewer the fallback runs is the driving runner's own reviewer for the pull
      request's stage."
- [ ] `docs/workflow/development-workflow/integrations/coderabbit.md` — the *Availability Check*
      section (lines 159-166) keeps its two checks unchanged. Add one clarifying sentence naming
      recent-comment inspection as the signal the gate uses and why. In the Troubleshooting table,
      rewrite the remedy in the "All Step 7a reviewers unreachable — hard-fail" row (line 175): drop
      "Run Step 7a from a context where at least one reviewer is reachable" and replace it with
      making the missing runtime or prerequisite available, or narrowing the list locally.
      *Covers*: AC "The guidance that determines CodeRabbit's availability from runtime conditions is
      unchanged, and does not contradict the general rule", and AC "No workflow surface states or
      implies that availability is decided by the identity of the driving runner."
- [ ] `docs/workflow/development-workflow/integrations/codex-github.md` — add a short "Step 7a runner
      reviewer" section: `codex-github` is a supported runner reviewer value, its availability is
      decided at runtime from whether the Codex GitHub App is installed for the repository, it is not
      in the shipped default, and opting in means adding it to `review.on_draft.runner`. Cross-link
      the existing verification checklist at line 143.
      *Covers*: AC "The canonical protocol lists the hosted-service reviewer among its supported
      values, and states that its availability is decided at runtime."
- [ ] `.claude/agents/item-orchestrator.md` line 198 — keep the `codex-github` dispatch block and its
      exit-code semantics; replace "This script is universally reachable from all runner contexts
      (Claude Code, Cursor, Codex, headless CI) because it uses only `gh` CLI — no Codex CLI runtime
      is needed" with a hosted-service statement: it needs no local Codex runtime, so no runner is
      inherently barred, and its availability is decided at runtime from whether the app is installed
      for the repository — unavailable with reason `prerequisite-missing` when it is not.
      *Covers*: AC "No surface claims the hosted-service reviewer is available from every runner
      unconditionally."
- [ ] `.cursor/agents/item-orchestrator.md` line 205 — apply the identical replacement. These two
      files must stay byte-identical in this block; the implementation step verifies that.
      *Covers*: same as above.
- [ ] `.cursor/BUGBOT.md` line 24 — the Non-Issues entry names the literal default
      `review.on_draft.runner: [codex]`, which this change makes stale. Restate it without the
      literal: do not flag the shipped default reviewer list by itself, and local narrowing belongs
      in `.ai-dev-workflow.local.yaml`.
      *Covers*: AC "No workflow surface names a reviewer value that the canonical protocol does not
      list as supported" (kept true as the default changes).
- [ ] `.ai-dev-workflow.local.example.yaml` lines 30-36 — the Cursor pilot comment presents the
      override as what you do "while running `/run-work` from Cursor so Step 7a dispatches the Cursor
      review agents instead of Codex", which reads as an identity-driven necessity. Rewrite it as a
      deliberate narrowing for a machine that lacks some runtimes, and add the retirement note: an
      operator who wrote this override only to get past the gate can delete the
      `review.on_draft.runner` key (and the file, if it holds nothing else) and re-run — the shipped
      default now reaches a reviewer on its own.
      *Covers*: AC group *The shipped default never traps*; Use Case 4.

### Surface disposition (all 15 VL-2 paths)

| Path | Disposition |
| --- | --- |
| `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` | **Change** — canonical |
| `.ai-dev-workflow.yaml` | **Change** — default list and commentary |
| `.claude/agents/item-orchestrator.md` | **Change** — unconditional-reachability claim |
| `.cursor/agents/item-orchestrator.md` | **Change** — mirrored claim |
| `docs/workflow/development-workflow/README.md` | **Change** — fallback names a fixed reviewer |
| `docs/workflow/development-workflow/integrations/coderabbit.md` | **Change** — one remedy cell and one clarifying sentence; the check itself is untouched |
| `.cursor/BUGBOT.md` | **Change** — names the stale default literal |
| `.ai-dev-workflow.local.example.yaml` | **Change** — override framed as an identity-driven necessity |
| `sync-manifest.yaml` | **Change** — new `product_repo_injection` entry (the line-208 mention of `internal_reviewers` is an unrelated example and stays) |
| `AGENTS.md` | **No change** — points at the key, states no rule |
| `.cursor/rules/workflow.mdc` | **No change** — same pointer text |
| `docs/workflow/setup/protocol.md` | **No change** — same pointer text |
| `.codex/skills/workflow-sync-template/SKILL.md` | **No change** — points at the key for a sync run |
| `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md` | **No change** — lines 353 and 960 are scope pointers to Protocol 91, not restatements |
| `docs/workflow/development-workflow/repository-modes.md` | **No change** — line 443 is a YAML example carrying the policy key with no rule attached |

Three further paths are changed although VL-2 does not match them:
`scripts/development-workflow/codex-github-reviewer.sh` and
`scripts/development-workflow/claude-code-action-reviewer.sh` (both carry the VL-4 header claim),
and `docs/workflow/development-workflow/integrations/codex-github.md` (needs the Step 7a section).

**Residual verification strategy** (evidence for AC group *Surfaces agree*): before
`ready-for-human-review`, the implementation re-runs VL-2 and VL-4 at the implementation head and records the output in the pull request. VL-4 must return
only the two historical records named in VL-4. Every VL-2 path must appear in the disposition table
above with its recorded disposition unchanged; a new path means a surface appeared during
implementation and must be classified before readiness.

---

## Testing Strategy

**Test types**: Unit (shell harnesses), Smoke (manual runbook).

**How environment-dependent probing is tested without installing every runtime**: every unit test
builds a hermetic `PATH` in a `mktemp -d` directory, symlinking the real coreutils the script needs
and adding fake `claude`, `cursor-agent`, `codex`, and `gh` executables whose behavior the test
controls — exit status, stdout, and delay. This is the pattern already used by
`test-local-ai-reviewer.sh` (VL-11). No test requires any reviewer runtime to be installed on the
machine, and no test makes a network call: `gh` is always the fake. Runtime **absence** is tested by
omitting the fake from the hermetic `PATH`, and runtime **presence** by adding it.

The AC-group column in the tables below uses the spec's sub-headings under **Acceptance Criteria**,
abbreviating one of them: *Configuration inputs* is the spec's *Configuration inputs that are absent,
empty, malformed, or unsupported* group. *Contract completeness* is not a spec group — it marks a
case that guards this plan's own exit-code contract rather than a criterion.

### New suite: `scripts/development-workflow/tests/test-resolve-reviewer-availability.sh`

Header: `# covers: scripts/development-workflow/resolve-reviewer-availability.sh` so CI discovers it
with no workflow edit (VL-10).

| ID | Scenario | Asserts | AC group |
| --- | --- | --- | --- |
| T-1 | `runner: [codex]`, `--runner-kind claude`, fake `codex` present | `REVIEWER codex reachable -`, `OUTCOME=proceeded`, exit `0` | Reachability follows capability |
| T-2 | Same config, fake `codex` removed from `PATH` | `REVIEWER codex unreachable runtime-absent`, `OUTCOME=blocked`, `BLOCK_CAUSE=zero-reachable`, exit `1` | Reachability follows capability |
| T-3 | `runner: [claude]`, `--runner-kind claude`, no `claude` on `PATH` | `reachable` by identity (Decision 3) | Reachability follows capability |
| T-4 | `runner: [claude]`, `--runner-kind cursor`, no `claude` on `PATH` | `unreachable runtime-absent` — identity never causes unreachability, absence does | Reachability follows capability |
| T-5 | Fake `codex` present but `--version` exits `1` | `unreachable check-inconclusive`, not `runtime-absent` | Configuration inputs |
| T-6 | Fake `codex` present but sleeps past `LOCAL_PROBE_CAP_SECONDS` | `unreachable check-inconclusive`, detail names the bound | Configuration inputs |
| T-7 | Five configured entries, every fake binary sleeping; `WORKFLOW_REVIEWER_AVAILABILITY_TEST_MODE=1` with a 2s budget | wall-clock duration under the budget plus one second, all entries classified, `ELAPSED_SECONDS` printed, exit is `0` or `1` but never a hang | Configuration inputs (ten-second ceiling) |
| T-8 | `runner: [not-a-reviewer]` | `unreachable value-not-supported`, the value named in the record, `OUTCOME=blocked`, `BLOCK_CAUSE=zero-reachable` | Configuration inputs |
| T-9 | `runner: [not-a-reviewer, codex]` with `codex` present, policy `warn` | `OUTCOME=proceeded-reduced`, both records present, exit `0` | Configuration inputs |
| T-10 | No `runner` key in either file | `CONFIG_LIST_STATE=absent`, `FALLBACK_APPLIED=true`, `OUTCOME=proceeded`, exit `0` | Configuration inputs |
| T-11 | `runner: []` | `CONFIG_LIST_STATE=empty`, same outcome as T-10 | Configuration inputs |
| T-12 | Fallback path with `--runner-kind unknown` | `OUTCOME=blocked`, `BLOCK_CAUSE=no-driving-runner`, exit `1` | Configuration inputs |
| T-13 | `runner: codex` (scalar, not a list) | `CONFIG_LIST_STATE=malformed`, `BLOCK_CAUSE=list-malformed`, `FALLBACK_APPLIED=false`, exit `1` | Configuration inputs |
| T-14 | Any run, executed inside a temporary git checkout | `git status --porcelain` is empty afterwards | Reachability follows capability (purity) |
| T-15 | Fake `gh` records its argv to a file | no recorded invocation is `pr comment`, `pr ready`, or a non-GET `api` call | Reachability follows capability (purity) |
| T-16 | Policy `fail-if-any-unavailable`, one reachable and one absent | `OUTCOME=blocked`, `BLOCK_CAUSE=policy-forbids-reduced-coverage`, the reachable reviewer still recorded `reachable`, exit `1` | Policy behavior is preserved |
| T-17 | Policy `maybe` (unsupported), `runner` absent | `POLICY_STATE=unsupported`, `BLOCK_CAUSE=policy-unsupported`, `CONFIG_LIST_STATE=not-evaluated`, exit `1` | Policy behavior is preserved |
| T-18 | Policy key absent from both files | `POLICY=warn`, `POLICY_SOURCE=default` | Policy behavior is preserved |
| T-19 | Local override keeps `codex` of a shipped `[claude, cursor, codex]` | the two dropped entries are `override-excluded` with no reason, `UNREACHABLE` empty, `OUTCOME=proceeded` | The operator can tell why |
| T-20 | Override in effect and one kept reviewer absent | `LOCAL_OVERRIDE_STATE` reports the file and origin from the resolver, not a guess | The operator can tell why |
| T-21 | `runner: [coderabbit]`, fake `gh` returns comments containing `coderabbitai[bot]`, `.coderabbit.yaml` enables auto-review | `reachable` | Reachability follows capability |
| T-22 | Same, fake `gh` returns comments with no bot activity | `unreachable prerequisite-missing`, never `runtime-absent` | The operator can tell why |
| T-23 | Same, no `gh` on the hermetic `PATH` | `unreachable check-inconclusive`, never `prerequisite-missing` | Configuration inputs |
| T-24 | `runner: [codex-github]`, fake `gh` returns comments from the configured bot login | `reachable` regardless of `--runner-kind` | Reachability follows capability |
| T-25 | Every scenario above, aggregate | no record ever pairs `runtime-absent` with a hosted-service value, or `prerequisite-missing` with a local-runtime value | The operator can tell why |
| T-26 | Missing `--owner`/`--repo` | exit `2`, no `OUTCOME` line, message on stderr | Contract completeness |

### Extended suite: `scripts/development-workflow/tests/test-workflow-config-resolver.sh`

| ID | Scenario | Asserts | AC group |
| --- | --- | --- | --- |
| T-27 | `review-effective` with a shipped list and no local file | `EFFECTIVE_RUNNER_LIST` from `.ai-dev-workflow.yaml`, `EFFECTIVE_RUNNER_STATE=defined`, `OVERRIDE_EXCLUDED_LIST` empty | Configuration inputs |
| T-28 | Local file overrides the list | `EFFECTIVE_RUNNER_SOURCE` names the local file; `SHIPPED_RUNNER_LIST` still reports the shipped list; `OVERRIDE_EXCLUDED_LIST` is the set difference | Configuration inputs |
| T-29 | `.ai-dev-workflow.yaml` truncated mid-mapping so it will not parse | `EFFECTIVE_POLICY_STATE=unreadable`, `EFFECTIVE_RUNNER_STATE=malformed`, `UNREADABLE_FILE` names the file, exit `0` | Configuration inputs |
| T-30 | `review-overrides` output on the same fixtures | byte-identical to the pre-change output — the existing subcommand is unchanged | Regression guard |

### Parser-risk addendum

**Classification**: parser-risk **applies**. `review-effective` materially changes how a
structured-text configuration file is interpreted: it must distinguish absent, empty, present-but-not-a-list,
and unparseable, where the current code path collapses the first three (VL-9). The list value and the
policy scalar are the parsed constructs.

**Edge-case enumeration** — concrete inputs for `review.on_draft.runner` and
`review.internal_reviewers_unavailable_policy`, each mapped to an expected `EFFECTIVE_*_STATE`:

| # | Input | Expected state |
| --- | --- | --- |
| E-1 | `runner:` key entirely absent | `absent` |
| E-2 | `runner:` with nothing after the colon and no child lines | `empty` |
| E-3 | `runner: []` (inline empty list) | `empty` |
| E-4 | `runner: [claude, codex]` (inline list) | `defined`, two entries |
| E-5 | `runner:` followed by `- claude` block entries | `defined` |
| E-6 | `runner: codex` (scalar where a list is required) | `malformed` |
| E-7 | `runner: {a: b}` (mapping where a list is required) | `malformed` |
| E-8 | `runner:` followed only by a comment line, then a sibling key | `empty` |
| E-9 | `runner: [ claude , codex ]` (padded inline entries) | `defined`, entries trimmed to `claude`, `codex` |
| E-10 | `runner: ["claude", 'codex']` (quoted entries, both quote styles) | `defined`, quotes stripped |
| E-11 | `runner: [claude] # trailing comment` | `defined`, one entry, comment discarded |
| E-12 | A line reading `  # runner: [codex]` (commented-out lookalike) | `absent` — must not match |
| E-13 | `runner_extra: [codex]` (prefix lookalike key) | `absent` — must not match |
| E-14 | `runner:` nested under `on_ready:` instead of `on_draft:` | `absent` for `on_draft` — sibling-bucket lookalike must not match |
| E-15 | The whole file truncated mid-mapping | `malformed` list plus `unreadable` policy, `UNREADABLE_FILE` set |
| E-16 | A tab character used for indentation under `review:` | `malformed`, `UNREADABLE_DETAIL` names the line |
| E-17 | `internal_reviewers_unavailable_policy: warn` | policy `defined`, value `warn` |
| E-18 | `internal_reviewers_unavailable_policy:` with no value | policy `empty` → default `warn` |
| E-19 | `internal_reviewers_unavailable_policy: Warn` (wrong case) | policy `unsupported` — matching is exact, so a near-miss is reported rather than guessed |
| E-20 | `internal_reviewers_unavailable_policy: [warn]` (list where a scalar is required) | policy `unreadable` |
| E-21 | Both `runner: [codex]` and `internal_reviewers_unavailable_policy: bogus` present | policy `unsupported`; the list is still parsed by the resolver but the script prints `CONFIG_LIST_STATE=not-evaluated` because the gate stops at the policy |
| E-22 | Local file present with a `product_repos` section but no `review` section, in a linked worktree | the main clone's `review` section applies (existing #1560 behavior, must not regress) |

**Unit test mapping**: every case E-1 through E-22 gets one automated case in
`scripts/development-workflow/tests/test-workflow-config-resolver.sh`, named `review-effective E-<n>`,
asserting the exact expected state string. E-22 additionally asserts `LOCAL_OVERRIDE_ORIGIN=main_clone`.

**Suppression semantics**: not applicable — the feature recognizes no inline suppression directives.
`#` comments are YAML comments handled by the existing parser (E-11, E-12), not suppressions.

### Concurrent-event-source addendum

**Classification**: does **not** apply. Per Decision 6 the probes run sequentially in a single
process with no event listeners, socket callbacks, timers, async queues, or state shared across
execution contexts. The only child processes are short-lived, bounded probes whose results are read
synchronously before the next probe starts. Each of the seven checklist items is therefore not
applicable for the same reason: there is exactly one execution context.

---

## Seed Data

| Entity | Values / Scenario | File |
| --- | --- | --- |
| Fixture shipped config | `review.on_draft.runner` variants E-1 to E-16 | written per-test into `$TMP_ROOT/<case>/.ai-dev-workflow.yaml` by the harness |
| Fixture local override | `review.on_draft.runner: [codex]`; and a `product_repos`-only file for E-22 | `$TMP_ROOT/<case>/.ai-dev-workflow.local.yaml` |
| Fixture CodeRabbit config | `reviews.auto_review.enabled: true` and a `false` variant | `$TMP_ROOT/<case>/.coderabbit.yaml` |
| Fake reviewer binaries | `claude`, `cursor-agent`, `codex` — exit `0` / exit `1` / sleeping variants | `$TMP_ROOT/bin/` on the hermetic `PATH` |
| Fake `gh` | returns a canned `issues/comments` JSON array, with and without each bot login; and an argv-recording variant for T-15 | `$TMP_ROOT/bin/gh` |

No repository-level seed data and no database are involved. All fixtures are created and removed by
the harness `trap`.

---

## Documentation Updates

Most documentation edits are the feature itself and are listed under **Layer-by-Layer Changes**. The
following are the remaining documentation-only updates the developer must make:

- [ ] `docs/workflow/development-workflow/README.md` — the configuration-reference bullet at line 561
      (fallback wording plus the shipped-default guarantee sentence).
- [ ] `docs/workflow/development-workflow/integrations/coderabbit.md` — the one clarifying sentence
      and the one Troubleshooting remedy cell.
- [ ] `docs/workflow/development-workflow/integrations/codex-github.md` — the new Step 7a runner
      reviewer section.
- [ ] `docs/testing/workflow/1495-step-7a-capability-based-reachability.smoke-test.md` — update in the
      In Development stage with any deviation found while executing it.
- [ ] `AGENTS.md` — **no change**. Its `review.on_draft.runner` sentence points at the key without
      restating the availability rule, which the spec explicitly permits.
- [ ] `docs/project/*` — **none**. This feature adds no domain entity, no repository-structure
      change, and no data model.

---

## Risks & Mitigations

| ID | Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- | --- |
| R-1 | The three-entry default produces a reduced-coverage warning on machines missing a runtime, and operators read routine warnings as noise | High | Low | The warning names a reason and a remedy and never blocks; `.ai-dev-workflow.local.example.yaml` documents narrowing as the supported response. Decision 4 records the tradeoff explicitly. |
| R-2 | Cross-runner `codex` dispatch returns free-form text and the verdict cannot be parsed | Medium | Medium | Decision 5 fixes a single-line `VERDICT:` contract and classifies any parse failure as a review failure, not unreachability. The invocation shape is already shipped and exercised (VL-6). |
| R-3 | A hosted service installed but silent on the repository classifies `prerequisite-missing` | Medium | Low | Neither hosted reviewer is in the shipped default; the offered remedy (verify the app is installed) is correct either way. Recorded in the probe table and the runbook's Known Limitations. |
| R-4 | Two config readers now coexist — the Python resolver for Step 7a and the awk helpers for Step 7 — and could drift | Medium | Medium | Decision 2 names the resolver as authoritative for Step 7a and records the non-unification as deliberate; **Out-of-scope notes** carries it forward as a follow-up candidate. |
| R-5 | Re-adding `codex-github` to Step 7a revives the async race #486 moved it out for | Low | Medium | Decision 7: it is canonical but not default, and its dispatch goes through `codex-github-reviewer.sh`, whose pre-trigger wait, retrigger, and exit-code contract were built after #486. |
| R-6 | `run_bounded` duplicates `run_with_timeout` from `local-ai-reviewer.sh` | High | Low | Deliberate, recorded in **Out-of-scope notes**. Extracting the reviewer script's variant would change a heavily used Step 7 path for a Step 7a benefit, which the spec places out of scope. |
| R-7 | The budget test (T-7) is wall-clock sensitive and could flake on a loaded CI runner | Medium | Low | T-7 asserts an upper bound of budget plus one second on a 2-second test budget, not an exact duration, and asserts that every entry was classified — the property that matters is that the gate always reaches a verdict. |

---

## Code Samples

None. Every contract in this plan is expressed as a table or a command signature rather than as
source, so there is nothing for a reviewer to mistake for production code.

---

## Implementation Order

1. **`workflow-config-resolver.py`**: add `typed_value_from_path`, `resolve_review_effective`,
   `cmd_review_effective`, and the `review-effective` subparser per **Contracts**. Do not touch
   `list_override_from_path`, `resolve_review_overrides`, or `cmd_review_overrides`.
   *Verify*: run
   `python3 scripts/development-workflow/workflow-config-resolver.py review-effective --repo-root "$(pwd -P)"`
   and confirm the output lists every key in the contract table, that
   `EFFECTIVE_RUNNER_STATE` is `defined`, and that the reported list matches what
   `.ai-dev-workflow.yaml` (or the local override, if one is in effect) actually contains.

2. **Extend `tests/test-workflow-config-resolver.sh`** with cases T-27 to T-30 and `review-effective E-1`
   through `review-effective E-22`.
   *Verify*: `bash scripts/development-workflow/tests/test-workflow-config-resolver.sh` — read the
   output and confirm every new case reports PASS and no pre-existing case regressed.

3. **Write `scripts/development-workflow/resolve-reviewer-availability.sh`** implementing the
   evaluation order, the probe table, the budget constants, the output block, and the three exit
   codes. Source `workflow-lib.sh`. `chmod +x`.
   *Verify*: `shellcheck --severity=warning scripts/development-workflow/resolve-reviewer-availability.sh`
   reports nothing; then run it against this repository with
   `--runner-kind claude` and confirm the printed `OUTCOME`, `REACHABLE`, and `UNREACHABLE` values
   match what is actually installed on the machine.

4. **Write `tests/test-resolve-reviewer-availability.sh`** with the `# covers:` header and cases T-1
   to T-26, using the hermetic-`PATH` pattern from `test-local-ai-reviewer.sh`.
   *Verify*: `bash scripts/development-workflow/tests/test-resolve-reviewer-availability.sh` — confirm
   every case reports PASS. Then run
   `bash scripts/development-workflow/select-test-suites.sh` against the change set and confirm the
   new suite appears in the selection, so no CI workflow edit is needed.

5. **Rewrite Protocol 91 Step 7a** (all six regions listed under **Backend / Protocol surfaces**).
   *Verify*: `grep -n "runner identity is a sufficient proxy\|Reachability classification table\|default behavior: \`claude\`" docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`
   returns nothing.

6. **Change `.ai-dev-workflow.yaml`**: the default list, the supported-values comment, the deleted
   Runner-context constraint block and its replacement, and the policy comment.
   *Verify*: re-run the step-1 command and confirm `EFFECTIVE_RUNNER_LIST` reports the new default
   when no local override is in effect; and
   `grep -n "expected behaviour" .ai-dev-workflow.yaml` returns nothing.

7. **Update the remaining surfaces**: `README.md`, `integrations/coderabbit.md`,
   `integrations/codex-github.md`, `.claude/agents/item-orchestrator.md`,
   `.cursor/agents/item-orchestrator.md`, `.cursor/BUGBOT.md`,
   `.ai-dev-workflow.local.example.yaml`, `codex-github-reviewer.sh` header, and the
   `sync-manifest.yaml` entry.
   *Verify*: `grep -rn "universally reachable" --include="*.md" --include="*.sh" . | grep -v node_modules`
   returns only the two historical records named in VL-4 (`CHANGELOG.md` and the 2026-05 development
   artifact) and no live surface; and `diff <(sed -n '/codex-github. runner reviewer dispatch/,/^$/p' .claude/agents/item-orchestrator.md) <(sed -n '/codex-github. runner reviewer dispatch/,/^$/p' .cursor/agents/item-orchestrator.md)`
   reports no differences.

8. **Re-run the residual verification** (VL-2 and VL-4) at the implementation head and record both
   outputs in the pull request, per **Residual verification strategy**.

9. **Execute the smoke test runbook**
   `docs/testing/workflow/1495-step-7a-capability-based-reachability.smoke-test.md` end to end and
   record the assertion results in the pull request.

10. **Update project docs** per the **Documentation Updates** section above.

11. **Add the changelog fragment** `changelog.d/1495.fixed.step-7a-capability-based-reachability.md`
    with exactly this body:

    ```markdown
    - **Step 7a decides reviewer reachability from capability, not runner identity** (#1495): the internal review gate used to consult a fixed table that called the Codex reviewer unreachable whenever a different runner was driving the gate, even on a machine where the Codex command was installed and about to be used successfully by the next gate in the same pipeline — and since the shipped configuration named Codex as the only internal reviewer, the gate found nothing to dispatch and blocked. The gate now probes each configured reviewer against the environment it is actually running in, under a fixed ten-second ceiling, and reports each one as Reachable, Unreachable with one of four named reasons and a remedy, or Excluded by override. The shipped default reviewer list changed so that whichever supported runner drives the gate, that runner's own reviewer is reachable by construction, and the Codex GitHub App review is supported as a hosted-service reviewer whose availability is decided from whether the app is installed for the repository.
    ```

---

## Out-of-scope notes

Recorded so a reviewer can see these were considered and deliberately excluded, not missed.

- **Unifying the two configuration readers.** `workflow-lib.sh`'s awk readers keep serving Step 7
  (`pr-review-loop.sh`). Unifying them would change the external reviewer stage, which the spec
  places out of scope (Out of Scope item 4). Follow-up candidate (R-4).
- **Extracting a shared bounded-execution helper.** `local-ai-reviewer.sh:174` already has
  `run_with_timeout`, shaped around long-running reviewer processes with stdout/stderr files and
  process-group semantics. The availability probe needs a smaller helper for short-lived `--version`
  commands. Extraction would modify a heavily used Step 7 script for a Step 7a benefit (R-6).
- **`claude-code-action.md:179`**, which maps a Step 7 platform outcome onto
  `internal_reviewers_unavailable_policy`. That cross-wiring predates this item and concerns the
  external reviewer stage. Unchanged.
- **Re-deciding runs already blocked by the current behavior.** Spec Out of Scope item 10.
- **Changing what reviewers look for, the policy's allowed values, its meanings, or its default.**
  Spec Out of Scope items 3 and 8.
