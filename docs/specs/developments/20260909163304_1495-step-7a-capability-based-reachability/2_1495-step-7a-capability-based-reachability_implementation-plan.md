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

**One recorded product decision, not a literal reading of the spec.** Hosted-service availability is
a best-effort **proxy** for the spec's "installed for the repository and enabled for this review"
clause, because no mechanism available to the gate's user-token credentials can establish that
clause. The residual — an App that was uninstalled after commenting still reads as reachable — is
handled at dispatch under the same unavailable-reviewer policy rather than at availability. Stated in
full, with what the proxy gets wrong and the alternatives rejected, as **Decision 8**; the limitation
is repeated in the probe table, R-3 and R-11, and the runbook's Troubleshooting and Known
Limitations sections, so an operator meets it where they would hit it.

**Estimated complexity**: M

<!-- S: < 1 day | M: 1-3 days | L: 3+ days -->

**Rationale**: One new ~350-line shell script with a fully enumerated output contract, one new
Python subcommand with parse-state detection, three test suites, one shipped configuration change,
and edits to twelve documentation, agent, configuration, and script-header surfaces. No new runtime
dependency and no new concurrency. The bulk of the risk is in getting the state enumeration and the reason
categories exactly right, not in the volume of code. Cross-runner Codex invocation — the piece that
would normally be the unknown — is already shipped and exercised in this repository (see Decision 5
and VL-6).

**Dependencies**: None. The merged spec is the only prerequisite.

**Precondition at implementation start**: this plan is written against the spec as merged at
`8971ba12`. Before the first file edit, re-read
[`1_1495-step-7a-capability-based-reachability_specs.md`](1_1495-step-7a-capability-based-reachability_specs.md)
at the current `develop` head and confirm it still carries the five acceptance-criteria groups and
the decision-gate matrix this plan maps to. If the spec has been amended, reconcile the affected plan
sections first and record the reconciliation in the pull request. If it has been reverted,
superseded, or its acceptance criteria materially changed, stop with `unclear_requirements` and
return the evidence to the parent orchestrator rather than implementing against a prerequisite that
no longer holds.

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

### Decision 8 — Hosted-service availability is a best-effort proxy for the spec's clause, and the residual is handled at dispatch

**This is a decided product tradeoff, not an oversight, and it is a known gap between spec text and
implementation.** It is recorded here in those words so no future reader concludes the spec is
satisfied literally.

**What the spec asks for.** Spec line 151: "For a hosted-service reviewer, availability means the
service is installed for the repository **and enabled for this review**, decided the way
CodeRabbit's already is."

**What the gate can actually establish.** Nothing that reaches that clause. The only endpoint that
answers "is this App installed on this repository" — `gh api repos/{owner}/{repo}/installation` — is
answerable only under GitHub App authentication, and the gate holds a user token. There is no
user-token endpoint that enumerates third-party App installations on a repository, and no endpoint at
all that reports whether a service will accept one particular review. The only way to learn that is
to ask the service to review, which the spec forbids before availability is decided and the policy is
applied.

**What the probe is.** Recent repository comment activity by the reviewer's bot login, plus, for
CodeRabbit, `reviews.auto_review.enabled: true`. This is the second of the two alternatives
`coderabbit.md` already documents. It is a **proxy** for the spec clause, and the plan calls it one.

**What the proxy gets wrong, in both directions:**

- **False Reachable.** The App was installed, commented, and has since been uninstalled, suspended,
  had its repository access revoked, or exhausted its quota. Historical activity outlives the
  installation, and nothing in a comment list says the App is still there.
- **False Unreachable.** The App is installed and enabled but has never commented on this repository
  — a fresh repository, or one newly added to an existing installation. Classified
  `prerequisite-missing`; already recorded as R-3.

**Why accepting this is defensible — the residual is handled at dispatch, not at availability.**
A false Reachable does not become a silently skipped review. `codex-github-reviewer.sh:32` documents
exit `2` as `TIMED_OUT`: "API/auth/setup failures while waiting; treat as unavailable under
configured `internal_reviewers_unavailable_policy`". So a reviewer wrongly classified Reachable is
dispatched, fails to answer, and is then governed by **the same policy** that would have governed the
unreachability verdict — `warn` proceeds with reduced coverage and says so in the summary,
`fail-if-any-unavailable` blocks. What the gate never does is report a clean review that did not
happen or advance a pull request to ready on the strength of an absent reviewer. The failure mode is
a slower, noisier version of the correct outcome, not a wrong one.

This also keeps the spec's own boundary intact, which the same spec line draws: "availability asks
whether the reviewer can be invoked, never whether invoking it will go well."

**Blast radius.** Small, and deliberately so. `codex-github` is canonical but **not** in the shipped
default (Decision 4, Decision 7), and CodeRabbit's availability check is unchanged by this item (spec
Out of Scope item 5). A repository meets this behavior only by deliberately opting a hosted reviewer
into `review.on_draft.runner`. The shipped default reaches this code path not at all.

**Alternatives rejected:**

- *Build a probe that establishes current installation and per-review enablement.* Rejected as not
  buildable with the credentials the gate holds, for the reasons above. Requiring a GitHub App token
  for a read-only availability check would add a secret to a gate whose entire purpose is to be
  cheap, local, and side-effect free.
- *Narrow the spec's hosted-availability clause* to something a user-token gate can establish — for
  example "the gate can post the trigger, and the service has been seen on this repository".
  Rejected **only** because it requires a spec amendment pull request against a merged spec, adding a
  cycle to an item already at three review cycles. It is not rejected on the merits: it is arguably
  what the spec should have said, since it describes exactly what any gate holding user credentials
  can verify. Recorded here so a future reader knows the wording was examined rather than overlooked.
  A follow-up item could adopt it, and this decision would then match the spec literally rather than
  by proxy.

**Where the limitation is visible to an operator**, so it is not buried in a decision record nobody
reads: the availability probe table below, **Risks & Mitigations** R-3 and R-11, the runbook's
Troubleshooting table, and the runbook's Known Limitations. D-21 asserts Protocol 91 carries it too,
and T-38 pins the decided behavior so a later change that silently tightens or loosens the probe
fails a test rather than passing unnoticed.

### Decision 9 — Draft eligibility is guaranteed by conversion, and the conversion moves after the availability decision

Two separate questions, verified rather than assumed.

**Does the probe need a draft-eligibility term? No — and this is already settled behavior.**
Protocol 91's Runtime-availability check carries an explicit note (line 1686 at `8971ba12`): the
`auto_review.drafts: false` restriction "is **not** treated as an unreachability condition here — it
is handled upstream by the 'Draft-state pre-check' at the top of Step 7a, which converts any draft PR
to non-draft before this reachability check runs." Draft eligibility is therefore **guaranteed by
conversion, not tested by probing**, and CodeRabbit's check reading only `auto_review.enabled` is
correct rather than incomplete. This plan adds no draft-eligibility term to the probe, and the
existing note is kept.

**But verifying that surfaced a real ordering defect, and this plan fixes it.** The conversion runs
at the *top* of Step 7a, before "Determining which reviewers to run". The block decision runs *after*
the availability check and policy application. So a run that converts and then blocks leaves the pull
request **non-draft on a blocked gate** — contradicting C5, P2, P3, P6, P7, and P8, every one of
which requires the gate to leave the pull request draft. The same applies to a policy-input block,
which under the fixed evaluation order happens before the reviewer list is even resolved.

**The fix**: split the pre-check's two halves.

- Its **condition evaluation** stays where it is — reading the resolved list to learn whether a
  draft-restricting reviewer is configured. That reading is config-only, through
  `workflow-config-resolver.py review-effective`, so no probing and no `gh` call happens before the
  policy is read.
- Its **`gh pr ready` conversion** moves to immediately before dispatch, after the policy has been
  applied and the gate has decided to proceed.

Proceed path: unchanged in effect — CodeRabbit still sees a non-draft pull request when it is
dispatched, which is the whole purpose of the pre-check. Block path: nothing was converted, because
nothing was dispatched, and the pull request is still draft as the spec requires.

**Scope note**: this changes neither *whether* the conversion happens nor its condition — only *when*
within Step 7a. It is forced by this feature's own acceptance criteria rather than added to them, and
it does not touch which pipeline stages run this gate or when (spec Out of Scope item 9). Asserted by
D-20 and observed in runbook Step 14 Part 5.

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
REMEDY <reason> <text>
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
`CONFIG_LIST_STATE=malformed` means the `review.on_draft.runner` key is present in a file that
**does** parse but its value is not a list. A configuration file that does not parse at all never
reaches that value: it makes the policy input unreadable, so the run blocks in phase 1 with
`BLOCK_CAUSE=policy-unreadable` and prints `CONFIG_LIST_STATE=not-evaluated`, with `UNREADABLE_FILE`
naming the file. The two failures are distinct states with distinct block causes, and neither is
reported in place of the other.

`LOCAL_OVERRIDE_STATE` reuses the three #1560 forms verbatim, derived from `LOCAL_OVERRIDE_FILE`,
`LOCAL_OVERRIDE_ORIGIN`, and `MAIN_CLONE_LOCAL_OVERRIDE_FILE` — never inferred.

One `REMEDY` line is printed for each distinct reason present in the run, from this fixed mapping.
The mapping is the mechanism behind the spec's "at least one action the operator can take": the gate
quotes the matching `REMEDY` text into the warning or hard-fail comment rather than composing prose,
so every Unreachable reviewer carries a remedy by construction rather than by an author remembering
to write one.

| Reason | `REMEDY` text |
| --- | --- |
| `runtime-absent` | `Install the reviewer's runtime on this machine, or remove the reviewer from review.on_draft.runner in .ai-dev-workflow.local.yaml.` |
| `prerequisite-missing` | `Install or enable the review service for this repository, or remove the reviewer from review.on_draft.runner in .ai-dev-workflow.local.yaml.` |
| `check-inconclusive` | `Re-run the gate. If it recurs, run the named command by hand and confirm gh is authenticated for this repository.` |
| `value-not-supported` | `Correct the configured value to one of the supported reviewer values, or remove it from review.on_draft.runner.` |

No `REMEDY` line is printed for `reachable` or `override-excluded` records, because neither is a
failure the operator is being asked to act on.

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

**Known limitation — this probe is a proxy, by decision.** Spec line 151 defines hosted availability
as the service being "installed for the repository and enabled for this review". No mechanism
available to the gate's credentials establishes that, so the activity signal stands in for it. It is
wrong in two ways, both accepted under **Decision 8**:

- **False Unreachable**: an app installed but never active on this repository classifies
  `prerequisite-missing`. The remedy the report offers — verify the app is installed for this
  repository — is the correct action either way. **Risks & Mitigations** R-3.
- **False Reachable**: an app that was installed, commented, and has since been uninstalled,
  suspended, or had its access revoked still shows historical activity and classifies `reachable`.
  It is then dispatched and times out, and `codex-github-reviewer.sh:32` maps that timeout back onto
  the same `internal_reviewers_unavailable_policy` — so the residual is handled at dispatch rather
  than at availability, and never as a clean review that did not happen. **Risks & Mitigations**
  R-11.

Neither hosted reviewer is in the shipped default, so a repository meets this behavior only by
opting one into `review.on_draft.runner` deliberately.

**Draft eligibility is not a probe term.** Protocol 91's existing note keeps
`auto_review.drafts: false` out of the unreachability conditions because the draft-state pre-check
guarantees a non-draft pull request before dispatch. See **Decision 9**, which verifies that and
fixes the ordering defect it exposed.

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
2. **Resolve the list.** Reaching this phase already establishes that both configuration files
   parsed, because a file that did not would have made the policy input unreadable in phase 1. So
   `malformed` here means only one thing: the `review.on_draft.runner` key is present and readable
   and its value is not a list. That → block, `BLOCK_CAUSE=list-malformed`. `absent` or `empty` →
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
| Policy readable; the reviewer-list key is present in a file that parses, but its value is not a list of values | `blocked` | `list-malformed` | `1` | Dispatches nobody; names the file and the `review.on_draft.runner` key; does not fall back | Correct the malformed key |
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
- *A whole-file parse failure reaching `list-malformed`* — a configuration file that will not parse
  makes the **policy** input unreadable, and the policy is read in phase 1, so such a run always
  blocks with `policy-unreadable` and prints `CONFIG_LIST_STATE=not-evaluated`. `list-malformed` is
  reachable only from the narrower, file-parses state named in its row: the
  `review.on_draft.runner` key is present and readable, and its value is a scalar or a mapping where
  a list is required. Both states name the offending file in the block report, which is what the
  spec's "with a configuration file that will not parse at all, the gate blocks and names that file"
  criterion asks for — that the file be named, not that the cause be attributed to the list.
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

## Reversal and Rollback

This change alters a shipped default and a published workflow contract in a **template** repository,
so "revert the PR" is not the whole answer. Each of the three affected populations is stated
separately, and the one part that is not cleanly reversible is named rather than papered over.

**What the change writes.** Documentation, one YAML default, one new script, one new resolver
subcommand, and three test suites. It creates no migration, mutates no tracker, and by contract
(T-14, T-15) changes no pull request state and no tracked file at gate time. There is no durable
state outside the repository to unwind.

### (a) This repository

`git revert` of the merge commit is a complete rollback. It restores `review.on_draft.runner: [codex]`,
the Runner-context constraint commentary, the identity table in Protocol 91, and removes the
resolver, its subcommand, and its tests. Nothing else in the repository depends on the new contract:
`pr-review-loop.sh` (Step 7) reads its lists through the untouched awk helpers, and the existing
`review-overrides` subcommand is unchanged by design (asserted by T-30), so reverting cannot strand a
Step 7 caller.

The revert also restores the defect. Anyone driving the gate from a non-Codex runner is trapped
again, and the documented escape is the machine-local override — which is the situation described in
(c).

### (b) A downstream project that already synced

Two halves propagate differently, and the split is what makes a partial rollback safe:

- **The protocol, the scripts, and the tests** are `always_sync` (`docs/workflow/**` and
  `scripts/development-workflow/**` at manifest lines 65-160). A downstream that runs
  `/sync-template` receives the new gate behavior. Reverting upstream and re-syncing removes it.
- **The shipped default itself does not propagate this way.** `.ai-dev-workflow.yaml` is
  `project_specific` with `mixed_content: true` (manifest line 202), and its own note records that
  "provider selections … are project-specific" while only the schema-description comments above
  `<!-- TEMPLATE-OWNED-END -->` (line 46) are template-owned. The `runner:` list sits below that
  marker. Sync-template therefore never overwrites a downstream's reviewer selection; it may propose
  an additive change that a maintainer accepts or declines. The new default reaches a downstream only
  when someone creates a **new** project from the template, or when a maintainer deliberately adopts
  it. Reverting upstream does not un-adopt it: a downstream that took the new default keeps it until
  it edits its own file.

Both intermediate states are safe, which is why the two halves can be rolled back independently and
in either order:

| Downstream state | Behavior |
| --- | --- |
| New protocol and scripts, old `[codex]` default | Works. The new gate probes `codex` against the environment; on a machine where Codex is installed it is reachable, and where it is not the operator gets a named reason and a remedy instead of the old silent identity verdict. Strictly better than today. |
| Old protocol, new `[claude, cursor, codex]` default | Works. The old identity table classifies the driving runner's own value reachable and the others unreachable, and the `warn` policy proceeds with the reachable subset. Noisier than the new gate, but never blocked. |

There is no combination in which a partially rolled-back downstream blocks on this gate.

### (c) An operator who deleted their local override

**This is the part that is not cleanly reversible, and the plan changes to reduce it.**
`.ai-dev-workflow.local.yaml` is gitignored (`.gitignore:9`) and untracked, so no revert of any
commit restores a file an operator deleted. If this change is reverted after an operator retired
their override on its advice, that operator is back in the trapped state with no file to restore, and
must rewrite it by hand.

Two mitigations are folded into the change rather than left as advice in this section:

1. The retirement guidance in `.ai-dev-workflow.local.example.yaml` and in runbook Step 12 tells the
   operator to **move the file aside** (`mv .ai-dev-workflow.local.yaml .ai-dev-workflow.local.yaml.retired`)
   rather than delete it, so retirement is reversible with a second `mv`.
2. The override's content is two keys under `review.on_draft.runner`, and
   `.ai-dev-workflow.local.example.yaml` carries the shape, so rewriting one from scratch is a
   thirty-second job even for an operator who ignored the first mitigation.

No mitigation makes a deleted untracked file recoverable, and the plan does not claim otherwise.

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
        draft-state pre-check and is not an unreachability condition (Decision 9). State that the
        hosted-service activity signal is a **proxy** for the spec's installed-and-enabled clause,
        name the false-Reachable case, and point at the dispatch-time
        `internal_reviewers_unavailable_policy` treatment as where that residual is handled
        (Decision 8, asserted by D-21).
      - Lines 1496-1556 (*Draft-state pre-check*): keep the condition, the reviewer-to-draft-restriction
        mapping, the posted `INFO` comment, and the "Why this matters" rationale unchanged. Change
        only **where the `gh pr ready` conversion happens**: the condition is still evaluated here,
        from `review-effective`, but the conversion itself moves to immediately before the dispatch
        map, after the policy has been applied. Without this, a run that converts and then blocks
        leaves a non-draft pull request on a blocked gate, contradicting six acceptance criteria
        (Decision 9, asserted by D-20).
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
      operator who wrote this override only to get past the gate can remove the
      `review.on_draft.runner` key, or move the whole file aside with
      `mv .ai-dev-workflow.local.yaml .ai-dev-workflow.local.yaml.retired` if it holds nothing else,
      then re-run — the shipped default now reaches a reviewer on its own. The note must say **move
      aside, not delete**: the file is gitignored and untracked, so a later rollback of this change
      cannot restore a deleted one (**Reversal and Rollback** (c)).
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

**Test types**: Unit (shell harnesses over the resolver), doc assertion (shell harness over the
protocol and the other workflow surfaces), Smoke (manual runbook over the gate).

**Two layers, and why the split matters.** The resolver
(`resolve-reviewer-availability.sh`) computes a verdict and exits; the gate (Protocol 91 Step 7a,
executed by the runner) acts on it. A unit test of the resolver can never be evidence for a criterion
about what the gate then does — a perfect resolver and a gate that ignores it entirely would pass
every resolver test in this plan. The **Acceptance-criterion coverage map** below assigns each
criterion to the layer it constrains and names the evidence for each half.

**How environment-dependent probing is tested without installing every runtime**: every unit test
builds a hermetic `PATH` in a `mktemp -d` directory, symlinking the real coreutils the script needs
and adding fake `claude`, `cursor-agent`, `codex`, and `gh` executables whose behavior the test
controls — exit status, stdout, and delay. This is the pattern already used by
`test-local-ai-reviewer.sh` (VL-11). No test requires any reviewer runtime to be installed on the
machine, and no test makes a network call: `gh` is always the fake. Runtime **absence** is tested by
omitting the fake from the hermetic `PATH`, and runtime **presence** by adding it.

The AC-group column in the two `T-` tables below records which spec group a case contributes to; it
is an index, not a coverage claim — the per-criterion mapping is the coverage map. It abbreviates one
group name: *Configuration inputs* is the spec's *Configuration inputs that are absent, empty,
malformed, or unsupported*. *Contract completeness* is not a spec group at all — it marks a case that
guards this plan's own exit-code contract.

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
| T-31 | `.ai-dev-workflow.yaml` truncated mid-mapping so it will not parse | `POLICY_STATE=unreadable`, `BLOCK_CAUSE=policy-unreadable`, `CONFIG_LIST_STATE=not-evaluated`, the file named in the output, exit `1` | Configuration inputs |
| T-32 | The same fixture and command run three times: fake `codex` absent, then added, then removed | the `codex` record reads `unreachable runtime-absent`, then `reachable`, then `unreachable runtime-absent`, with no configuration file changed between runs | Reachability follows capability |
| T-33 | The repository's own `.ai-dev-workflow.yaml`, hermetic `PATH` containing **none** of `claude`, `cursor-agent`, `codex`, and no local override; run once per `--runner-kind` in `claude`, `cursor`, `codex` | every run exits `0` with `OUTCOME` not `blocked`, and the reviewer matching `--runner-kind` is `reachable` | The shipped default never traps |
| T-34 | Linked-worktree fixture: a `.git` **file** pointing at a main clone that holds the override | `LOCAL_OVERRIDE_STATE` reports the main clone's file with origin `main_clone`, taken from the resolver output | The operator can tell why |
| T-35 | `internal_reviewers_unavailable_policy: [warn]` (a list where a scalar is required) | `POLICY_STATE=unreadable`, `BLOCK_CAUSE=policy-unreadable`, exit `1`; the default policy is not silently applied | Policy behavior is preserved |
| T-36 | Every fixture above, aggregate | no `REVIEWER` detail string contains the run's `RUNNER_KIND` value — no unreachability is attributed to the driving runner | The operator can tell why |
| T-37 | Every fixture above, aggregate | each `unreachable` record's reason is exactly one of the four, and a `REMEDY` line is present for every distinct reason in the run | The operator can tell why |
| T-38 | `runner: [codex-github]`, fake `gh` returning **only historical** bot comments (no other installation signal available to a user token) | `reachable`. This pins the decided behavior of **Decision 8**: historical activity alone is sufficient, and the residual false-Reachable case is handled at dispatch. A later change that silently tightens or loosens the proxy fails here instead of passing unnoticed | Decided-tradeoff guard |

### Acceptance-criterion coverage map

Every individual criterion in the merged spec is listed here with the named evidence that would fail
if the behavior were absent. Criterion IDs number the checkboxes under each **Acceptance Criteria**
sub-heading in spec order: `R` for *Reachability follows capability*, `S` for *The shipped default
never traps*, `O` for *The operator can tell why*, `C` for *Configuration inputs that are absent,
empty, malformed, or unsupported*, `P` for *Policy behavior is preserved*, `A` for *Surfaces agree*.
Forty-one criteria, all mapped.

#### Which layer a criterion constrains, and what each kind of evidence can prove

This feature has two layers, and most criteria constrain the second one.

- **The resolver** — `resolve-reviewer-availability.sh` reads configuration, probes the environment,
  applies the policy, prints a verdict block, and exits. It dispatches nothing and posts nothing.
- **The gate** — Protocol 91 Step 7a, executed by the runner. It calls the resolver and then acts on
  the verdict: dispatches the reachable set or nobody, posts the warning or the hard-fail comment,
  converts the pull request or leaves it draft, escalates or continues.

A criterion such as "the gate blocks, dispatches nobody, leaves the pull request draft, and names the
file" is a statement about the **gate**. A unit test of the resolver cannot be evidence for it: the
resolver printing `OUTCOME=blocked` is consistent with a gate that ignores the verdict entirely and
dispatches anyway, which is the most likely way this feature ships broken. Each criterion below is
therefore mapped to the layer it actually constrains, with these three kinds of evidence:

| Kind | What it is | What it proves | What it cannot prove |
| --- | --- | --- | --- |
| **Resolver unit** | A numbered `T-` case in one of the two script suites | The resolver computes and prints the right verdict for a given environment and configuration | Anything about what the runner then does |
| **Gate doc assertion** | A numbered `D-` case in the surface-consistency suite | Protocol 91 *instructs* the gate behavior, in text that will fail the suite if it is reworded away | That any runner actually followed the instruction |
| **Gate runbook** | A numbered step in the smoke runbook | An operator *observed* the behavior happen on a real pull request with a real runner | Nothing automated re-checks it after the run |

A gate-level criterion needs both gate kinds: the doc assertion keeps the instruction from silently
disappearing between releases, and the runbook step is the only evidence that a runner honoured it.
Neither substitutes for the other, and no `D-` case below should be read as proof of runtime
behavior.

#### The map

| ID | Criterion (abbreviated) | Layer | Evidence |
| --- | --- | --- | --- |
| R1 | Runtime present, different runner driving → dispatched, verdict, no block or override | Both | Resolver unit T-1 for the classification; gate doc assertion D-12 for the instruction to dispatch `REACHABLE`; gate runbook Step 13 Part 1 for the dispatch and verdict |
| R2 | Not Unreachable solely because a different runner drives; runtime present → Reachable | Resolver | T-1, T-4 |
| R3 | Runtime absent → Unreachable, reason `runtime-absent` | Resolver | T-2, T-4 |
| R4 | Fresh each run on the same pull request; the verdict flips both ways | Both | Resolver unit T-32 (three consecutive runs, no caching inside the resolver); gate doc assertion D-13 (the gate re-runs the resolver every cycle and may not reuse an earlier verdict); gate runbook Step 4 |
| R5 | Posts no comment, changes no PR state, modifies no tracked file | Both | Resolver unit T-14, T-15; gate doc assertion D-14 (no mutating command anywhere in the protocol's availability phase); gate runbook Step 5 |
| R6 | Invokes no reviewer; nothing dispatched until availability is decided and the policy applied | Both | Resolver unit T-15 (the resolver itself dispatches nothing); gate doc assertion D-15 (the resolver call precedes the dispatch map and no reviewer is dispatched until it returns) — this ordering is a property of the gate, and no resolver test can observe it; gate runbook Step 5 |
| R7 | Reachable, dispatched, then fails → review failure, not unreachable | Gate | Gate doc assertion D-6; gate runbook Step 13 Part 1, whose expected result covers a dispatched reviewer that then fails. The resolver has already exited before dispatch, so no unit test of this feature can observe it |
| S1 | Shipped default, no override → dispatched reviewer and a verdict on every supported runner | Both | Resolver unit T-33 (a non-blocked verdict for every supported runner kind on a `PATH` holding none of the three runtimes); gate doc assertion D-12; gate runbook Step 1 for the verdict on every supported runner kind and Step 13 Part 1 for the dispatch |
| S2 | The shipped list names at least one reviewer reachable wherever a supported runner drives | Resolver | T-33 |
| S3 | Shipped commentary does not call a hard-fail on a supported runner expected behavior | Surface text | D-9 |
| O1 | Every Unreachable reviewer reported with name, exactly one reason, and at least one action | Both | Resolver unit T-37 (reason is one of four; a `REMEDY` line exists for it); gate doc assertions D-5 (the protocol's four remedies match the script's) and D-16 (the comment formats carry name, reason, and remedy per reviewer); gate runbook Step 13 Part 3 and Step 14 Part 1 read the posted comments |
| O2 | The four reasons are distinguished and never reported in place of one another | Resolver | T-25 (no cross-kind pairing), T-2, T-5, T-8, T-22, T-23 (one per reason) |
| O3 | The gate summary lists every configured reviewer with its verdict, including the ones that ran | Gate | Gate doc assertion D-16; gate runbook Step 13 Part 1. T-19 proves the resolver emits a record per entry, which is the input the summary needs — necessary, not sufficient, so it is not listed as evidence for this criterion |
| O4 | Override-removed reviewer is Excluded by override, no unreachability warning | Both | Resolver unit T-19 (the record carries `override-excluded` with no reason); gate doc assertion D-16 (excluded entries appear in the summary and never in the warning); gate runbook Step 14, which runs the real gate with an override in effect |
| O5 | Block report names the policy, and reports override state from what was resolved | Both | Resolver unit T-16, T-20, T-34, T-13 produce the four field values; gate doc assertion D-18 (the hard-fail formats carry `BLOCK_CAUSE` and `LOCAL_OVERRIDE_STATE` taken from the resolver, never inferred); gate runbook Step 14 Part 1 |
| O6 | No message attributes unavailability to the driving runner's identity | Both | Resolver unit T-36 (no detail string contains the run's `RUNNER_KIND`); gate doc assertions D-17 and D-18 (neither comment template carries a runner-context field), plus D-2 and D-10 for the surrounding surfaces; gate runbook Step 13 Part 3 and Step 14 Part 1 |
| C1 | No list in either file → runs the stage default **once** and records the fallback in the summary | Both | Resolver unit T-10 (`FALLBACK_APPLIED=true`); gate doc assertions D-12 (dispatch the driving runner's stage reviewer exactly once) and D-16 (the summary records that the fallback applied); gate runbook Step 13 Part 2 |
| C2 | The fallback reviewer is the driving runner's own for the stage, so it never blocks | Both | Resolver unit T-10 and T-12 (`FALLBACK_APPLIED=true` for a supported runner, `no-driving-runner` for `unknown`); gate doc assertions D-7 and D-12; gate runbook Step 13 Part 2 |
| C3 | A list resolving to no entries behaves as C1; never reports success having dispatched nobody | Both | Resolver unit T-11; gate doc assertions D-12 and D-16; gate runbook Step 13 Part 2 |
| C4 | Unsupported entry → Unreachable, reason `value-not-supported`, value named in the report | Both | Resolver unit T-8, T-9 (classification and named value in the record); gate doc assertion D-18 (the offending value is named in the block report); gate runbook Step 14 Part 1, second run |
| C5 | List defined but not readable as a list → blocks, names file and input, dispatches nobody, PR stays draft | Both | Resolver unit T-13 (`BLOCK_CAUSE=list-malformed`, exit `1`); gate doc assertions D-18 (the report names the file and the key), D-19 (exit `1` maps to dispatch nobody, no `gh pr ready`, PR stays draft, escalate) and D-20 (no draft conversion can precede the block); gate runbook Step 14 Part 2, with Part 5 for the draft-conversion ordering |
| C6 | A file that will not parse at all → blocks and names that file | Both | Resolver unit T-31, T-29; gate doc assertions D-18 and D-19; gate runbook Step 14 Part 2 |
| C7 | An unsupported value as the only entry → blocks and names it as the cause | Both | Resolver unit T-8; gate doc assertions D-18 and D-19; gate runbook Step 14 Part 1, second run |
| C8 | A determination that cannot complete → `check-inconclusive`; verdict within ten seconds | Resolver | T-6 (per-probe bound), T-7 (whole-list budget with every probe hanging) |
| C9 | A determination that ends promptly without an answer → the same reason, not the other two | Resolver | T-5, T-23 |
| P1 | One unreachable, one reachable, `warn` → warns naming each, then dispatches the rest | Both | Resolver unit T-9 (`OUTCOME=proceeded-reduced`) and T-37 (reason and remedy available to quote); gate doc assertion D-17 (the warning names each unreachable reviewer with its reason and remedy and states the reachable subset) and D-12 (the reachable subset is then dispatched); gate runbook Step 13 Part 3 |
| P2 | `fail-if-any-unavailable` + any unreachable → blocks, dispatches nobody, PR stays draft | Both | Resolver unit T-16; gate doc assertions D-18, D-19 and D-20; gate runbook Step 14 Part 3, with Part 5 for the draft-conversion ordering |
| P3 | No reviewer reachable → blocks under either policy, PR not converted to ready, escalates | Both | Resolver unit T-2 (under `warn`) and T-16 (under the strict policy); gate doc assertions D-19 (exit `1` maps to no `gh pr ready`, draft preserved, escalation) and D-20 (the draft-state pre-check's conversion cannot precede the block); gate runbook Step 14 Part 1 and Part 5 |
| P4 | Every reviewer reachable → no warning, behaves exactly as today | Both | Resolver unit T-1, T-19 (`OUTCOME=proceeded`, `UNREACHABLE` empty, no `REMEDY` line); gate doc assertion D-17 (the warning is posted only when `OUTCOME=proceeded-reduced`); gate runbook Step 13 Part 1 |
| P5 | No policy in either file → the shipped default `warn` applies | Resolver | T-18 |
| P6 | Unsupported policy value → blocks, dispatches nobody, names it, does not silently default | Both | Resolver unit T-17 (`BLOCK_CAUSE=policy-unsupported`, the value carried in the output); gate doc assertions D-18 (the report names the offending value) and D-19 (nobody is dispatched); gate runbook Step 14 Part 4 |
| P7 | Unsupported or unreadable policy with an absent, empty, or malformed list → blocks on the policy | Both | Resolver unit T-17, T-31 (`CONFIG_LIST_STATE=not-evaluated`); gate doc assertion D-18 (the report attributes the block to the policy); gate runbook Step 14 Part 4 |
| P8 | Policy input present but unreadable → blocks and names the input | Both | Resolver unit T-31, T-35; gate doc assertions D-18 and D-19; gate runbook Step 14 Part 2 |
| P9 | A reachable reviewer under a forbidding policy is still classified Reachable in the report | Both | Resolver unit T-16 (the record still reads `reachable`); gate doc assertion D-18 (the block report lists every reviewer with its verdict, including the reachable ones); gate runbook Step 14 Part 3 |
| P10 | Never installs, provisions, or substitutes; the fallback is not a substitution | Both | Resolver unit T-15 (no mutating call in the recorded `gh` argv), T-2 (an absent runtime yields a block, never a stand-in); gate doc assertion D-8; gate runbook Step 13 Part 2 (the fallback dispatches the runner's own reviewer, not a stand-in for an unreachable one) and Step 14 Part 1 (an unreachable reviewer produces a block, never a substitution) |
| A1 | Supported values and the availability rule stated consistently across surfaces | Surface text | D-1, D-5, D-11 |
| A2 | No surface names a value the canonical protocol does not list | Surface text | D-4 |
| A3 | The canonical protocol lists the hosted-service reviewer and states its runtime availability rule | Surface text | D-1 |
| A4 | No surface claims the hosted-service reviewer is unconditionally available | Surface text | D-3 |
| A5 | No surface states or implies availability is decided by runner identity | Surface text | D-2, D-10 |
| A6 | CodeRabbit's runtime-conditions guidance is unchanged and does not contradict the rule | Surface text | D-10 |

#### What this map admits

- **Seven criteria are resolver-only** — R2, R3, O2, S2, C8, C9, P5. Each asserts what the verdict
  *is* for a given environment, which is exactly what a unit test can settle.
- **Seven are statements about surface text** — S3 and A1 to A6. A doc assertion is not second-best
  evidence for these; it is the right instrument, because the criterion is about what the text says.
- **Twenty-seven are gate-level, wholly or in part** — every remaining ID: twenty-five marked
  `Both`, plus R7 and O3, which constrain only the gate. For each, the resolver unit case (where one
  exists) proves only that the verdict handed to the gate was correct. The doc assertion proves the
  protocol instructs the right response, and the runbook step is the only evidence that a runner
  produced it.
- **One criterion, R7, has no achievable automated evidence** and says so: the resolver has exited
  before dispatch, so a reviewer that then fails is observable only in the protocol text (D-6) and in
  runbook Step 13.
- **T-19 is deliberately not listed under O3.** It proves the resolver emits a per-reviewer record —
  the input the summary comment needs — but a gate could receive those records and post a summary
  that omits half of them. Where a resolver test is necessary-but-not-sufficient for a gate
  criterion, it is left out rather than counted.

### New suite: `scripts/development-workflow/tests/test-step7a-surface-consistency.sh`

Several acceptance criteria are statements about what the workflow surfaces say, and many more
constrain gate behavior that lives only in protocol prose — what the runner does with the resolver's
verdict. A grep the implementer runs by hand is not evidence that survives the next edit, so both
groups get a doc-assertion suite. Precedent for the pattern:
`test-protocol-91-readiness-checklist.sh`, `test-protocol-02-portable-parser-guidance.sh`, and
`test-workflow-agent-product-repo-guidance.sh`.

Cases D-1 to D-11 assert what the surfaces **say about themselves**. Cases D-12 to D-21 assert that
Protocol 91 **instructs** each gate behavior a criterion requires, and that it records the decided
hosted-probe limitation where an operator reading the protocol will see it. Neither group proves a runner
obeyed the instruction — the runbook steps are the only evidence of that, and the coverage map above
names them criterion by criterion.

Headers:

```text
# covers: docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md
# covers: .ai-dev-workflow.yaml .ai-dev-workflow.local.example.yaml
# covers: .claude/agents/item-orchestrator.md .cursor/agents/item-orchestrator.md
# covers: docs/workflow/development-workflow/integrations/coderabbit.md
# covers: docs/workflow/development-workflow/integrations/codex-github.md
```

**Surface-text assertions:**

| ID | Assertion | AC |
| --- | --- | --- |
| D-1 | Protocol 91's supported runner reviewer values are exactly `claude`, `cursor`, `codex`, `coderabbit`, `codex-github`, and each is labelled local-runtime or hosted-service | A1, A3 |
| D-2 | Protocol 91 contains neither the phrase `runner identity is a sufficient proxy` nor a `Reachability classification table` heading | A5 |
| D-3 | No live surface contains `universally reachable` — the search excludes `CHANGELOG.md` and `docs/specs/developments/**`, which are historical records | A4 |
| D-4 | Every reviewer value named in `review.on_draft.runner` in `.ai-dev-workflow.yaml` and `.ai-dev-workflow.local.example.yaml` is one of Protocol 91's five | A2 |
| D-5 | Protocol 91 carries a remedy for each of the four reason categories, and the four remedy strings match `resolve-reviewer-availability.sh`'s `REMEDY` mapping character for character | O1 |
| D-6 | Protocol 91 states that a reviewer classified Reachable, dispatched, and then failing, erroring, or timing out is a review failure and not an availability verdict | R7 |
| D-7 | Protocol 91 and `README.md` both describe the fallback as the driving runner's own stage reviewer, and neither names a fixed reviewer for it | C2 |
| D-8 | Protocol 91 states that the gate never installs a missing runtime, provisions a missing prerequisite, or substitutes a different reviewer | P10 |
| D-9 | `.ai-dev-workflow.yaml`'s `review.on_draft.runner` is exactly `claude`, `cursor`, `codex`, and the file contains no text describing a hard-fail of this gate on a supported runner as expected behavior | S3 |
| D-10 | `coderabbit.md` still states both of its availability checks — the App activity signal and `reviews.auto_review.enabled: true` — and its Step 7a hard-fail remedy names no runner context | A6, A5 |
| D-11 | The `codex-github` runner reviewer dispatch block is byte-identical in `.claude/agents/item-orchestrator.md` and `.cursor/agents/item-orchestrator.md` | A1 |

**Gate-instruction assertions:**

| ID | Assertion | AC |
| --- | --- | --- |
| D-12 | On resolver exit `0`, Protocol 91 instructs dispatching every reviewer named in `REACHABLE`, and where `FALLBACK_APPLIED=true` instructs dispatching the driving runner's own stage reviewer exactly once — the word "once" is asserted, because "runs it once" is the criterion | R1, S1, C1, C2, C3, P1 |
| D-13 | Protocol 91 instructs running the availability resolver at the start of every Step 7a cycle, including re-runs after fixes, and states that a verdict from an earlier cycle is never reused | R4 |
| D-14 | Between the resolver call and the dispatch step, Protocol 91's Step 7a text contains no `gh pr comment`, no `gh pr ready`, and no command that writes to the working tree | R5 |
| D-15 | Protocol 91 places the resolver call before the reviewer dispatch map and states that no reviewer is dispatched until the resolver returns and the policy has been applied | R6 |
| D-16 | The Step 7a summary comment format requires one line per configured reviewer with its display label; for each Unreachable one, its reason display label and its remedy; and, where `FALLBACK_APPLIED=true`, a line recording that the fallback applied. Override-excluded entries appear in the summary and never in the warning | O1, O3, O4, C1, C3 |
| D-17 | The warning comment format carries no runner-context field, names each unreachable reviewer with its reason and its remedy, states the reachable subset that will run, and is posted only when `OUTCOME=proceeded-reduced` | O6, P1, P4 |
| D-18 | Each hard-fail comment case names `BLOCK_CAUSE`; every configured reviewer with its verdict, including the reachable ones; the offending value or unreadable input where one exists; the policy where the policy is the cause; and `LOCAL_OVERRIDE_STATE` taken from the resolver rather than inferred. No case carries a runner-context field | O5, O6, C4, C5, C6, C7, P2, P6, P7, P8, P9 |
| D-19 | Protocol 91 maps resolver exit `1` to: dispatch nobody, do not call `gh pr ready`, leave the pull request draft, escalate to a human — and maps exit `2` to the same treatment with cause `availability-resolver-failed` | C5, C6, C7, P2, P3, P6, P8 |
| D-20 | Protocol 91's draft-state pre-check evaluates its condition from `review-effective` before the availability check, but its `gh pr ready` conversion appears **after** the policy-application step and before the dispatch map — so no block path can leave a converted pull request behind. The existing note keeping `auto_review.drafts: false` out of the unreachability conditions is still present | C5, P2, P3, P6, P7, P8; Decision 9 |
| D-21 | Protocol 91's hosted-service probe section states that the activity signal is a proxy for the spec's installed-and-enabled clause, names the false-Reachable case, and points at the dispatch-time `internal_reviewers_unavailable_policy` treatment as where the residual is handled | Decision 8 |

Every case must be shown to fail before the suite is accepted; see Implementation Order step 8.


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
| E-15 | The whole file truncated mid-mapping | `malformed` list plus `unreadable` policy, `UNREADABLE_FILE` set. The resolver reports both states because it evaluates both fields; the gate script never reaches the list field, blocking in phase 1 with `policy-unreadable` (T-31) |
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
| R-3 | A hosted service installed but silent on the repository classifies `prerequisite-missing` (false Unreachable) | Medium | Low | Neither hosted reviewer is in the shipped default; the offered remedy (verify the app is installed) is correct either way. Recorded in the probe table, the runbook's Troubleshooting table, and the runbook's Known Limitations. |
| R-11 | A hosted service that was uninstalled, suspended, or had its access revoked still shows historical activity and classifies `reachable` (false Reachable), so the gate dispatches a reviewer that is not there | Medium | Medium | **Decided tradeoff, not a defect to fix later — see Decision 8.** No mechanism available to the gate's user-token credentials can establish current installation and per-review enablement. The residual is handled at dispatch: `codex-github-reviewer.sh:32` maps the resulting timeout onto the same `internal_reviewers_unavailable_policy`, so `warn` proceeds with reduced coverage and says so and `fail-if-any-unavailable` blocks — never a clean review that did not happen. Blast radius is limited to repositories that opt a hosted reviewer into `review.on_draft.runner`, which the shipped default does not. Visible to operators in the probe table, the runbook's Troubleshooting table, and its Known Limitations; pinned by T-38 and D-21. |
| R-4 | Two config readers now coexist — the Python resolver for Step 7a and the awk helpers for Step 7 — and could drift | Medium | Medium | Decision 2 names the resolver as authoritative for Step 7a and records the non-unification as deliberate; **Out-of-scope notes** carries it forward as a follow-up candidate. |
| R-5 | Re-adding `codex-github` to Step 7a revives the async race #486 moved it out for | Low | Medium | Decision 7: it is canonical but not default, and its dispatch goes through `codex-github-reviewer.sh`, whose pre-trigger wait, retrigger, and exit-code contract were built after #486. |
| R-6 | `run_bounded` duplicates `run_with_timeout` from `local-ai-reviewer.sh` | High | Low | Deliberate, recorded in **Out-of-scope notes**. Extracting the reviewer script's variant would change a heavily used Step 7 path for a Step 7a benefit, which the spec places out of scope. |
| R-7 | The budget test (T-7) is wall-clock sensitive and could flake on a loaded CI runner | Medium | Low | T-7 asserts an upper bound of budget plus one second on a 2-second test budget, not an exact duration, and asserts that every entry was classified — the property that matters is that the gate always reaches a verdict. |
| R-8 | The doc-assertion suite (D-1 to D-21) breaks on innocent rewording of the surfaces it greps | Medium | Low | Each case asserts a short stable phrase or a structural fact (a value list, a byte-for-byte block comparison), never a whole sentence. Implementation Order step 8 requires proving each case can fail before the suite is accepted, so a case that has silently stopped asserting anything is caught at authoring time rather than months later. |
| R-9 | The change is reverted after operators retired their machine-local override on its advice, and the override file cannot be restored by any revert | Low | Medium | Retirement guidance says move the file aside rather than delete it, so a second `mv` restores it; the override is two keys and `.ai-dev-workflow.local.example.yaml` carries the shape. See **Reversal and Rollback** (c) — this is mitigated, not eliminated. |
| R-10 | The resolver is implemented correctly and the gate ignores its verdict — dispatching on a block, or skipping dispatch on a proceed | Medium | High | This is the feature's most likely failure and no resolver test can see it. D-12 and D-19 assert the protocol instructs the exit-code mapping; runbook Steps 13 and 14 are the only evidence a runner honoured it, and the runbook's Troubleshooting table names the symptom as a blocking implementation failure rather than a runbook problem. The coverage map marks all twenty-seven gate-level criteria so no reviewer has to rediscover the distinction. |

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
   to T-26 and T-31 to T-38, using the hermetic-`PATH` pattern from `test-local-ai-reviewer.sh`.
   *Verify*: `bash scripts/development-workflow/tests/test-resolve-reviewer-availability.sh` — confirm
   every case reports PASS. Then run
   `bash scripts/development-workflow/select-test-suites.sh` against the change set and confirm the
   new suite appears in the selection, so no CI workflow edit is needed.

5. **Rewrite Protocol 91 Step 7a** (all seven regions listed under **Backend / Protocol surfaces**, including moving the draft-state pre-check's `gh pr ready` conversion to after policy application per Decision 9).
   *Verify*: `grep -n "runner identity is a sufficient proxy\|Reachability classification table\|default behavior: \`claude\`" docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`
   returns nothing; and read the Step 7a text end to end confirming the only `gh pr ready` before the
   dispatch map is the draft-state conversion, and that it now sits after the policy-application
   step rather than at the top of the section.

6. **Change `.ai-dev-workflow.yaml`**: the default list, the supported-values comment, the deleted
   Runner-context constraint block and its replacement, and the policy comment.
   *Verify*: re-run the step-1 command and confirm `EFFECTIVE_RUNNER_LIST` reports the new default
   when no local override is in effect; and
   `grep -n "expected behaviour" .ai-dev-workflow.yaml` returns nothing.

7. **Update the remaining surfaces**, all ten: `README.md`, `integrations/coderabbit.md`,
   `integrations/codex-github.md`, `.claude/agents/item-orchestrator.md`,
   `.cursor/agents/item-orchestrator.md`, `.cursor/BUGBOT.md`,
   `.ai-dev-workflow.local.example.yaml` (including the move-aside retirement guidance from
   **Reversal and Rollback** (c)), the `codex-github-reviewer.sh` header, the
   `claude-code-action-reviewer.sh` header, and the `sync-manifest.yaml` entry.

   For `claude-code-action-reviewer.sh` the edit is **the header comment only** — replace the
   "Classifies as universally reachable" sentence at line 9 with the hosted-service statement. Do not
   change its stage attribution, its options, its exit codes, or any behavior: it is dispatched
   through `review.on_ready.github`, which is Step 7 and out of scope.
   *Verify*: `grep -rn "universally reachable" --include="*.md" --include="*.sh" . | grep -v node_modules`
   returns only the two historical records named in VL-4 (`CHANGELOG.md` and the 2026-05 development
   artifact) and no live surface; and `diff <(sed -n '/codex-github. runner reviewer dispatch/,/^$/p' .claude/agents/item-orchestrator.md) <(sed -n '/codex-github. runner reviewer dispatch/,/^$/p' .cursor/agents/item-orchestrator.md)`
   reports no differences.

8. **Write `tests/test-step7a-surface-consistency.sh`** with the `# covers:` headers and cases D-1 to
   D-21. Write it **after** steps 5 to 7, because D-1 to D-11 target text those steps produce on the
   surrounding surfaces and D-12 to D-19 target the Step 7a gate instructions written in step 5.
   *Verify*: `bash scripts/development-workflow/tests/test-step7a-surface-consistency.sh` — confirm
   every case reports PASS. Then revert one surface edit locally, re-run, and confirm the matching
   case reports FAIL before restoring it: a doc-assertion suite that cannot fail is worthless.

9. **Re-run the residual verification** (VL-2 and VL-4) at the implementation head and record both
   outputs in the pull request, per **Residual verification strategy**.

10. **Execute the smoke test runbook**
   `docs/testing/workflow/1495-step-7a-capability-based-reachability.smoke-test.md` end to end and
   record the assertion results in the pull request.

11. **Update project docs** per the **Documentation Updates** section above.

12. **Add the changelog fragment** `changelog.d/1495.fixed.step-7a-capability-based-reachability.md`
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
