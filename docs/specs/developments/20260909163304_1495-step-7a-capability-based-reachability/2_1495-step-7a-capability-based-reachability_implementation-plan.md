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
handled at dispatch as a review failure rather than as a new availability verdict. Stated in
full, with what the proxy gets wrong and the alternatives rejected, as **Decision 8**; the limitation
is repeated in the probe table, R-3 and R-11, and the runbook's Troubleshooting and Known
Limitations sections, so an operator meets it where they would hit it.

**Estimated complexity**: M

<!-- S: < 1 day | M: 1-3 days | L: 3+ days -->

**Rationale**: One new ~350-line shell script with a fully enumerated output contract, one new
Python subcommand with parse-state detection, three test suites, one shipped configuration change,
and edits to twelve documentation, agent, configuration, and script-header surfaces. The portable timeout fallback uses the existing Perl dependency when GNU `timeout` and
`setsid` are absent; no other runtime dependency or new concurrency is introduced. The bulk of the risk is in getting the state enumeration and the reason
categories exactly right, not in the volume of code. Cross-runner Codex invocation — the piece that
would normally be the unknown — is already shipped and exercised in this repository (see Decision 5
and VL-6).

**Dependencies**: None. The merged spec is the only prerequisite.

**Precondition at implementation start**: this plan is written against the spec as merged at
`8971ba12`. Before the first file edit, re-read
[`1_1495-step-7a-capability-based-reachability_specs.md`](1_1495-step-7a-capability-based-reachability_specs.md)
at the current `develop` head and confirm it still carries the six acceptance-criteria groups and
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

### Decision 5 — Every reachable local runtime has an explicit dispatch path

When reviewer kind matches the driving runner, use that runner's native stage reviewer as today.
Otherwise, invoke the installed CLI from the artifact repository root, after availability and policy
have both completed. Dispatch sequentially using these argument shapes:

| Reviewer | Cross-runner command | Evidence |
| --- | --- | --- |
| `codex` | `codex exec --sandbox read-only "$review_prompt"` | Existing `local-codex-review-command.sh` invocation (VL-6) |
| `claude` | `claude -p --output-format text "$review_prompt"` | [Claude CLI reference](https://code.claude.com/docs/en/cli-reference), verified 2026-09-10 |
| `cursor` | `cursor-agent --print --output-format text "$review_prompt"` | [Cursor headless CLI](https://docs.cursor.com/en/cli/headless), verified 2026-09-10; the executable is the same one the availability probe checks |

The prompt names the exact stage protocol, `REVIEW.md`, the spec/brief and plan paths, the reviewed
head and base, and the active review pass when applicable. Request a read-only review and a final
single line `VERDICT: APPROVED` or `VERDICT: NEEDS REVISION`. The parent applies deterministic fixes
and re-runs the required reviewers after a push. Preserve the CLI's existing permission controls;
do not add permission-bypass flags or substitute another runtime when dispatch cannot complete.
The read-only request is an instruction; only the Codex command above additionally enforces a
read-only sandbox.

Capture exit status and the complete response. A non-zero exit, denied required operation,
missing/ambiguous verdict, or dispatch timeout is a **review failure**, never an unreachability
verdict. Approval requires exit `0` and exactly one valid terminal verdict. Availability was already
settled before dispatch. This remains protocol guidance, not a new dispatcher script; it fills the
cross-runtime cases the new capability rule makes possible. D-6 checks all three invocation paths,
and runbook Step 13 verifies each using a different driving runner. CLI shapes are documented here;
their real authenticated dispatch is not claimed tested at plan stage.

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

**The residual is handled as a review failure after dispatch.** A false Reachable does not
become a silently skipped or approved review. Once dispatched, a reviewer that fails, errors,
exhausts quota, times out, or supplies no parseable verdict is a **review failure**, under either
unavailable-reviewer policy. The gate retains its original Reachable classification, reports the
failure separately, and does not advance on reduced coverage because that reviewer failed.

The historical `codex-github-reviewer.sh:32` header instead says to treat exit `2` as unavailable.
That is existing caller guidance, not policy enforcement in the script, and conflicts with the
merged spec's post-dispatch boundary. Update that header and both mirrored caller blocks for Step 7a:
exit `0` is approval, exit `1` enters the revision path, exits `2` and `3` are review failures,
and exit `4` remains waiting on the reviewer, never approval or an unavailable skip. The script's
exit numbers and runtime behavior remain unchanged. Protocol 91 must apply the same failure rule
to CodeRabbit after dispatch. No Step 7 external-reviewer policy changes are included.

The accepted product tradeoff is the availability proxy's false-positive and false-negative
classifications. It does not waive the spec's separate requirement that a dispatched failure remain
a review failure. D-6, D-21, and runbook Step 13 Part 4 verify that distinction.

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
correct rather than incomplete. This plan adds no draft-eligibility term to the probe. Update the
note's timing language: conversion guarantees eligibility before dispatch, not before availability.

**But verifying that surfaced a real ordering defect, and this plan fixes it.** The conversion runs
at the *top* of Step 7a, before "Determining which reviewers to run". The block decision runs *after*
the availability check and policy application. So a run that converts and then blocks leaves the pull
request **non-draft on a blocked gate** — contradicting C5, P2, P3, P6, P7, and P8, every one of
which requires the gate to leave the pull request draft. The same applies to a policy-input block,
which under the fixed evaluation order happens before the reviewer list is even resolved.

**The fix**: split the pre-check's two halves.

- Its **condition evaluation** moves after the availability helper returns a proceed verdict. It
  reads the helper's indexed reviewer records to learn whether a draft-restricting reviewer is
  configured. The pre-check never invokes `review-effective` separately: the helper's bounded call
  is the sole configuration resolution, so a stalled parser cannot hang before its deadline starts.
- Its **`gh pr ready` conversion** moves to immediately before dispatch, after the policy has been
  applied and the gate has decided to proceed.

Proceed path: unchanged in effect — CodeRabbit still sees a non-draft pull request when it is
dispatched, which is the whole purpose of the pre-check. Block path: nothing was converted, because
nothing was dispatched, and the pull request is still draft as the spec requires.

**Scope note**: this changes neither *whether* the conversion happens nor its condition — only *when*
within Step 7a and which already-resolved records supply the condition. It is forced by this feature's own acceptance criteria rather than added to them, and
it does not touch which pipeline stages run this gate or when (spec Out of Scope item 9). Asserted by
D-20 and observed in runbook Step 14 Part 5.

### Decision 10 — Per-entry indexed `KEY=value` fields, escaped with the repository's existing helper

A configured value is an arbitrary YAML scalar. `- "codex, claude"` and `- "my reviewer"` are each
**one** entry, and each is an unsupported value that the spec requires to be "reported by name" and
"never silently discarded". A comma-joined list field and a whitespace-delimited positional record
can represent neither: the first splits one entry into two, the second splits one name into two
fields. That is a hole exactly where the spec is strictest.

**Chosen**: every reviewer entry is emitted as indexed `KEY=value` fields — one field per attribute,
each value written with `print_kv_escaped` from `workflow-lib.sh`. The positional
`REVIEWER <name> <status> …` record and the free-standing `REMEDY` lines are replaced by them.

Why this and not something else:

- **`KEY=value` where the value runs to end of line is already unambiguous** for commas and
  whitespace. The only character class that can forge a field or a line boundary is a control
  character, and `print_kv_escaped` (`workflow-lib.sh:543`) already escapes backslash, carriage
  return, newline, and tab. So no escaping scheme is invented; an existing shipped helper is used as
  it is, and `pr-review-loop.sh` already emits its output this way.
- **Indexing removes the join.** With `REVIEWER_1_REASON` and `REVIEWER_1_REMEDY` side by side, "every
  Unreachable reviewer carries a remedy" is structurally true rather than a lookup the gate has to
  perform correctly.
- The positional record was the only non-`KEY=value` line in the block, and it was the second place
  the delimiter hole bit.

**Alternatives rejected:**

- *Reject delimiter-bearing values at parse time with a distinct block cause.* Rejected on the
  merits, not on cost: the supported reviewer values are all `[a-z-]+`, so a value containing a comma
  or a space **is** an unsupported value, and C4 and C7 require it to be classified
  `value-not-supported` and named. Blocking it under a different cause would report the wrong thing
  about it and would drop the name the spec insists on.
- *Invent an escaping or quoting scheme for the comma-joined fields.* Rejected: this plan is already
  parser-risk, and a bespoke escape syntax is the classic way to add parser bugs to a change whose
  entire point is to stop guessing at malformed input.
- *Shell-quote the values with `shlex.quote`.* Rejected as unnecessary once the fields are indexed —
  it would require every consumer to `eval` the block, which is a sharper tool than reading a line.

The aggregate fields (`CONFIGURED`, `REACHABLE`, `UNREACHABLE`, `OVERRIDE_EXCLUDED`) survive as
**display-only summaries**, defined as not a parsing surface. To stop them claiming to hold something
they cannot represent, any entry whose name does not match `^[a-z][a-z0-9-]*$` is rendered in them as
`<entry N>`, pointing at the indexed record that holds the real value.

#### The transport is lossless at every hop, not only at the last one

A contract that is lossless only where the values are printed is not lossless. The entries enter the
pipeline in the Python resolver, so that is where a comma-joined field would destroy them — and no
downstream indexing could recover what was already merged. Every hop is therefore named:

| Hop | Representation | Why it cannot lose or split a value |
| --- | --- | --- |
| YAML scalar → Python | `list[str]` from `parse_yaml_subset`, read through `typed_value_from_path` | The existing parser already returns one list element per YAML sequence entry. Nothing splits on a delimiter at any point, so `- "codex, claude"` arrives as one string |
| Python → stdout | **One JSON object**, reviewer lists as JSON arrays of strings | `json.dumps` escaping is a standard, not something this plan invents, and it round-trips any scalar including commas, whitespace, quotes, and control characters |
| stdout → shell | `jq` writes NUL-delimited entries to a temporary file; a Bash 3.2 `while IFS= read -r -d ''` loop appends each entry to an array | NUL cannot occur in the supported YAML scalar input. Reading from a file keeps the loop in the current shell and allows checking `jq`'s exit status first. `select-test-suites.sh:65` and `batch-merge.sh:531` explicitly avoid `mapfile` for Bash 3.2 compatibility |
| shell → verdict block | `print_kv_escaped` into `REVIEWER_N_NAME` | `KEY=value` to end of line, with control characters escaped by the existing helper |

**`review-effective` emits JSON only — there is no shell `KEY=value` form for this subcommand.** That
is a deliberate divergence from the resolver's other subcommands, whose shell form exists so callers
can `eval` it. A flat `KEY=value` map cannot carry a list losslessly without a delimiter, which is the
exact defect being closed; and this subcommand has one consumer, which already requires `jq` — a hard
dependency of `pr-review-loop.sh`, `local-ai-reviewer.sh`, and `workflow-lib.sh` alike. One
representation cannot drift from itself, so JSON is the only one. `review-overrides` keeps its
existing shell and `--json` forms unchanged, because other callers depend on them (T-30).

### Decision 11 — The availability budget covers the configuration-resolver call, because that call is inside the spec's window

The spec measures the ten-second ceiling from "starting to resolve the list". The
`review-effective` invocation **is** the resolution of the list, so it is inside the window by
definition, not before it.

Recording a deadline and then making an unbounded call would leave the deadline observable only
*after* the call returns. A stalled resolver — a hung filesystem, a `python3` that will not start —
would blow the ceiling with nothing able to stop it, and the later per-probe checks would notice only
once it was far too late to matter. That is not a bounded gate; it is a gate that reports how long it
overran.

**Chosen**: the `review-effective` call is bounded exactly like a probe, with
`min(remaining, CONFIG_RESOLVE_CAP_SECONDS)`, using the same `run_bounded` helper. When it is the
thing that times out, the run blocks with the new block cause `config-resolution-inconclusive` and no
per-reviewer reason, because no reviewer was classified — see **Why a stalled resolver gets its own
block cause** under the contract below.

---

## Contracts

### `workflow-config-resolver.py review-effective`

```text
python3 scripts/development-workflow/workflow-config-resolver.py review-effective \
  --repo-root <path>
```

Read-only. Never invokes `git` or `gh`. Emits **one JSON object on stdout and nothing else** — there
is no shell `KEY=value` form and no `--json` flag, because JSON is the only form (Decision 10).
Reviewer lists are JSON arrays of strings, so an entry containing a comma, whitespace, a quote, or a
control character is transported verbatim with no delimiter anywhere in the path.

| Field | Type and values |
| --- | --- |
| `effective_runner` | array of strings — the resolved reviewer entries, verbatim and in configured order. `[]` when none resolve |
| `effective_runner_state` | string — `defined` / `absent` / `empty` / `malformed` |
| `effective_runner_source` | string — absolute path of the file the list came from, `""` when none |
| `shipped_runner` | array of strings — the `.ai-dev-workflow.yaml` list, for reporting what an override replaced |
| `override_excluded` | array of strings — entries in `shipped_runner` that the override left out; `[]` when no override is in effect |
| `effective_policy` | string — `warn` / `fail-if-any-unavailable` / the offending raw value / `""` |
| `policy_input` | JSON value — original policy scalar or collection; `null` when absent or not evaluated. Preserve type so the shell can report malformed collections as JSON |
| `effective_policy_state` | string — `defined` / `absent` / `empty` / `unsupported` / `unreadable` |
| `effective_policy_source` | string — absolute path of the file the policy came from, `""` when none |
| `unreadable_file` | string — absolute path of the configuration file that would not parse, `""` when none |
| `unreadable_detail` | string — the parser's message, `""` when none |
| `local_override_file`, `local_override_origin`, `main_clone_local_override_file` | strings — the same three values `review-overrides` already emits, so the `<local-override-state>` reporting introduced by #1560 keeps working unchanged |

The consuming side reads scalars with `jq -r` and arrays NUL-delimited, which is the one delimiter a
YAML scalar cannot contain:

<!-- workflow-shell-contract: bash -->
```bash
# Illustrative — adapt during implementation; both paths are temporary files.
set -euo pipefail
jq -j '.effective_runner[] | . + "\u0000"' "$resolver_output" > "$entries_file" || exit 2
configured=()
while IFS= read -r -d '' entry; do
  configured+=("$entry")
done < "$entries_file"
```

Exit codes: `0` always when the command ran, including for `malformed`, `unsupported`, and
`unreadable` states — those are **data**, reported in the state fields, not crashes. `2` only for
argument errors or an unreadable `--repo-root`, in which case stdout is empty and the message goes to
stderr, so a consumer never has to distinguish a partial object from a complete one. A `ConfigError`
raised while parsing either configuration file is caught and reported as
`effective_policy_state: "unreadable"` plus `effective_runner_state: "malformed"` with
`unreadable_file` naming the file — the existing
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
on a real run. The two tests that assert the ten-second contract — T-7 and T-40 — deliberately do
**not** use that override: they run at the shipped budget, because a ceiling asserted against a
shortened budget proves nothing about the shipped one.

Emits one `REVIEWER` record per configured entry, in configured order, followed by the summary
block:

```text
REVIEWER_COUNT=<integer>
REVIEWER_1_NAME=<configured value, verbatim>
REVIEWER_1_STATUS=<reachable|unreachable|override-excluded>
REVIEWER_1_REASON=<runtime-absent|prerequisite-missing|check-inconclusive|value-not-supported|>
REVIEWER_1_REMEDY=<remedy text, empty unless REASON is set>
REVIEWER_1_DETAIL=<what the probe saw>
...one such group per configured entry, numbered from 1 in configured order...
RUNNER_KIND=<claude|cursor|codex|unknown>
BUDGET_SECONDS=8
ELAPSED_SECONDS=<decimal seconds including cleanup>
POLICY=<warn|fail-if-any-unavailable|>
POLICY_INPUT=<raw scalar, or JSON for a non-scalar; empty when absent or not evaluated>
POLICY_SOURCE=<path|default>
POLICY_STATE=<defined|absent|empty|unsupported|unreadable|not-evaluated>
UNREADABLE_FILE=<configuration path, empty unless unreadable>
UNREADABLE_DETAIL=<parse/type error, empty unless unreadable>
CONFIG_LIST_STATE=<defined|absent|empty|malformed|not-evaluated>
CONFIG_LIST_SOURCE=<path|>
LOCAL_OVERRIDE_STATE=<none|<file> (<origin>), applied|present but unpropagated: <file>>
CONFIGURED=<comma list>
OVERRIDE_EXCLUDED=<comma list>
REACHABLE=<comma list>
UNREACHABLE=<comma list>
FALLBACK_APPLIED=<true|false>
OUTCOME=<proceeded|proceeded-reduced|blocked>
BLOCK_CAUSE=<none|config-resolution-inconclusive|policy-unreadable|policy-unsupported|list-malformed|zero-reachable|policy-forbids-reduced-coverage|no-driving-runner>
```

**Serialization contract.** Every line is `KEY=value` and the value runs to the end of the line, so a
value containing commas or whitespace needs no escaping and cannot split a field. Every value is
written with `print_kv_escaped` (`workflow-lib.sh:543`), which escapes backslash, carriage return,
newline, and tab, so no configured value can forge a line break or a second field either. A consumer
that needs a reviewer's name, status, reason, remedy, or detail reads the indexed fields.
The scalar state and diagnostic fields are also parsing surfaces; only the four aggregate reviewer
lists are display-only (Decision 10). `POLICY` is empty on unsupported, unreadable, or not-evaluated
paths. Preserve `POLICY_INPUT` from the JSON resolver's `policy_input` value and render non-scalars as JSON.
Carry `UNREADABLE_FILE` and `UNREADABLE_DETAIL` from the resolver, including type errors at a known
policy path. The gate quotes these fields in its block report, without rerunning configuration
resolution. T-48 and D-18 verify the diagnostic path end to end to the gate instructions.

- `REVIEWER_N_NAME` is the configured value **verbatim**, including one that contains a comma, a
  space, or both. It is what the report names, which is how "reported by name, never silently
  discarded" is satisfied for a value the supported set does not contain.
- An entry configured as the empty string has `REVIEWER_N_NAME=` and is rendered in prose as
  `(empty value)`, so a report never reads as though it forgot to name something.
- `REVIEWER_N_REASON` and `REVIEWER_N_REMEDY` are empty for `reachable` and `override-excluded`
  records, and both are set for every `unreachable` record. The remedy text comes from the fixed
  mapping below.
- `CONFIGURED`, `REACHABLE`, `UNREACHABLE`, and `OVERRIDE_EXCLUDED` are **display-only** comma-joined
  summaries, not a parsing surface. An entry whose name does not match `^[a-z][a-z0-9-]*$` appears in
  them as `<entry N>` rather than inline, so a summary never claims to contain a value it cannot
  represent. The indexed record always holds the real value.

`CONFIG_LIST_STATE=not-evaluated` appears when configuration resolution did not complete or
when the run blocked on the policy before evaluating the list. This makes the fixed evaluation
order visible in the output.
`CONFIG_LIST_STATE=malformed` means the `review.on_draft.runner` key is present in a file that
**does** parse but its value is not a list. A configuration file that does not parse at all never
reaches that value: it makes the policy input unreadable, so the run blocks in phase 1 with
`BLOCK_CAUSE=policy-unreadable` and prints `CONFIG_LIST_STATE=not-evaluated`, with `UNREADABLE_FILE`
naming the file. The two failures are distinct states with distinct block causes, and neither is
reported in place of the other.

`LOCAL_OVERRIDE_STATE` reuses the three #1560 forms verbatim, derived from `LOCAL_OVERRIDE_FILE`,
`LOCAL_OVERRIDE_ORIGIN`, and `MAIN_CLONE_LOCAL_OVERRIDE_FILE` — never inferred.

`REVIEWER_N_REMEDY` is filled from this fixed mapping whenever `REVIEWER_N_REASON` is set. The
mapping is the mechanism behind the spec's "at least one action the operator can take": the gate
quotes the field into the warning or hard-fail comment rather than composing prose, so every
Unreachable reviewer carries a remedy by construction rather than by an author remembering to write
one — and because the remedy travels in the same record as the reason, the gate performs no lookup
that could go wrong.

| Reason | `REMEDY` text |
| --- | --- |
| `runtime-absent` | `Install the reviewer's runtime on this machine, or remove the reviewer from review.on_draft.runner in .ai-dev-workflow.local.yaml.` |
| `prerequisite-missing` | `Install or enable the review service for this repository, or remove the reviewer from review.on_draft.runner in .ai-dev-workflow.local.yaml.` |
| `check-inconclusive` | `Re-run the gate. If it recurs, run the named command by hand and confirm gh is authenticated for this repository.` |
| `value-not-supported` | `Correct the configured value to one of the supported reviewer values, or remove it from review.on_draft.runner.` |

`REVIEWER_N_REMEDY` is empty for `reachable` and `override-excluded` records, because neither is a
failure the operator is being asked to act on.

**Exit codes** (complete):

| Exit | Meaning | `OUTCOME` printed | What the gate does |
| --- | --- | --- | --- |
| `0` | The gate may dispatch | `proceeded` or `proceeded-reduced` | Dispatch `REACHABLE`, or the driving runner's stage reviewer when `FALLBACK_APPLIED=true`. Post the reduced-coverage warning first when `OUTCOME=proceeded-reduced`. |
| `1` | The gate must block | `blocked` | Dispatch nobody, leave the pull request draft, post the hard-fail comment naming `BLOCK_CAUSE`, escalate to a human |
| `2` | The availability resolver could not run at all — a usage error, a missing dependency, an unreadable `--repo-root`, or `review-effective` reporting an invocation error of its own | none | Treat as blocked with cause `availability-resolver-failed`; the hard-fail comment quotes the resolver's stderr. This is not a reviewer verdict — no reviewer was classified. |

**Why a stalled configuration resolver gets its own block cause.** When the `review-effective` call
exceeds its bound, the run blocks with `BLOCK_CAUSE=config-resolution-inconclusive`, exit `1`,
`POLICY_STATE=not-evaluated`, `CONFIG_LIST_STATE=not-evaluated`, and `REVIEWER_COUNT=0`. There is
**no per-reviewer reason**, because no reviewer was reached, classified, or even named.

It would be simpler to reuse `policy-unreadable`, and it would be wrong for the reason the spec
itself gives when it separates *Availability check did not complete* from *Prerequisite missing*: a
check that did not answer has not shown the input to be bad. Reporting "your policy value is
unreadable — correct it" when the resolver merely hung would send an operator to fix a file that is
perfectly fine. `config-resolution-inconclusive` says what happened — the configuration could not be
read in time — and its remedy is to re-run and, if it recurs, check that `python3` and the repository
root are reachable.

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
  It is then dispatched and may time out. That is a review failure under either policy,
  with its original Reachable classification retained; it cannot become an unavailable skip or
  approval. The gate reports the failure and does not advance on reduced coverage. **Risks & Mitigations**
  R-11.

Neither hosted reviewer is in the shipped default, so a repository meets this behavior only by
opting one into `review.on_draft.runner` deliberately.

**Draft eligibility is not a probe term.** Protocol 91's existing note keeps
`auto_review.drafts: false` out of the unreachability conditions because the draft-state pre-check
guarantees a non-draft pull request before dispatch. See **Decision 9**, which verifies that and
fixes the ordering defect it exposed.

### The availability budget

Four constants, named once and used with these names everywhere:

| Constant | Value | Role |
| --- | --- | --- |
| `AVAILABILITY_BUDGET_SECONDS` | `8` | The **internal** budget the script allots itself. Deliberately below the spec's ten-second contract so that timeout and poll cleanup overhead fits inside the contract rather than being excused by a loosened assertion — see **The contract is ten seconds; the budget is eight** below |
| `CONFIG_RESOLVE_CAP_SECONDS` | `2` | Cap for the `review-effective` call. Generous for pure local file parsing; it exists so a hung filesystem or a `python3` that will not start cannot consume the whole budget before any probe runs |
| `LOCAL_PROBE_CAP_SECONDS` | `3` | Per-probe cap for a local-runtime reviewer |
| `HOSTED_PROBE_CAP_SECONDS` | `4` | Per-probe cap for a hosted-service reviewer |

Enforcement:

1. The script records `deadline = now + AVAILABILITY_BUDGET_SECONDS` as its **first** action, before
   invoking the config resolver. The spec's criterion measures from "starting to resolve the list",
   so the resolver call is inside the window, not before it.
2. **The `review-effective` call is bounded, not merely timed** (Decision 11). It runs under
   `run_bounded` with `min(remaining, CONFIG_RESOLVE_CAP_SECONDS)`. Setting a deadline and then
   making an unbounded call would let the deadline be observed only after the call returned, so a
   stalled resolver would overrun the ceiling with nothing able to stop it. If the bound elapses, the
   run blocks immediately with `BLOCK_CAUSE=config-resolution-inconclusive`, exit `1`,
   `POLICY_STATE=not-evaluated`, `CONFIG_LIST_STATE=not-evaluated`, `REVIEWER_COUNT=0`, and no
   per-reviewer reason — no reviewer was named, so none can be classified. Asserted by T-40.
3. For each entry, resolve classifications that need no probe first: an unsupported value is
   `unreachable` / `value-not-supported`, and the driving runner's own reviewer is `reachable`.
   These classifications remain valid after the budget is exhausted. For every other entry,
   compute `remaining = deadline - now`. If `remaining <= 0`, record that entry as
   `unreachable` / `check-inconclusive` with detail
   `availability budget exhausted before this check started`, and run no probe. Continue through
   the remaining entries so a later native reviewer or unsupported value receives its own correct
   classification. This ordering preserves the shipped default guarantee even when earlier probes
   hang; T-43 exercises that case.
4. Otherwise the probe runs with bound `min(remaining, cap)` for its kind. If it does not finish, the
   reviewer is `unreachable` / `check-inconclusive` with detail `check exceeded its <n>s bound`.
5. `ELAPSED_SECONDS` is printed so a run that came close to the ceiling is visible in the log.

Because the deadline is absolute and **every** call the script makes — the configuration resolution
as well as each probe — runs under a bound clamped to the remaining budget, total wall-clock time
cannot exceed `AVAILABILITY_BUDGET_SECONDS` plus cleanup for any list length or any configuration
state. The per-call caps are subordinate to the budget, never additive to it. There is no unbounded
call between the moment the deadline is set and the moment the verdict is printed.

#### The contract is ten seconds; the budget is eight

The spec says resolving the whole configured list takes **at most ten seconds**. That is the
assertion, and it is asserted with no tolerance: T-7, T-40, and runbook Steps 6 and 16 fail when
measured wall time exceeds ten seconds. A test that passed at 10.9 seconds would not be testing the
contract, and a runbook step that accepted "well under fifteen" would be testing nothing.

Cleanup overhead is real, so it is absorbed by the **implementation's** budget rather than by a
loosened assertion. The arithmetic, worst case:

| Component | Worst case | Source |
| --- | --- | --- |
| `AVAILABILITY_BUDGET_SECONDS` | 8 s | this plan |
| Poll-loop granularity on a host without GNU `timeout` | +1 s | the fallbacks in `gh_api_bounded` and `run_with_timeout` sleep in one-second steps, so an elapsed bound can be noticed up to a second late |
| `SIGTERM` → `SIGKILL` grace for a child that ignores the first signal | +1 s | `gh_api_bounded` sleeps 1 s between the two signals; GNU `timeout` is invoked with `--kill-after=1` |
| **Total** | **10 s** | equals the contract, with nothing left over |

The budget is 8 rather than 10 precisely so the contract can be asserted hard. If a future host makes
cleanup slower than two seconds, the correct response is to lower `AVAILABILITY_BUDGET_SECONDS`
again, never to raise the assertion: the assertion is the spec's contract, and the budget is the
implementation's problem.

`ELAPSED_SECONDS` reports the full elapsed window, including cleanup, and the tests
assert it is at most ten seconds. `BUDGET_SECONDS=8` is only the internal scheduling budget. That is an additional check, not the ceiling check — the
ceiling is asserted from outside the script against wall-clock time, because a script that
mis-measured its own elapsed time would otherwise report a compliance it did not achieve.

Bounding mechanism: one new `run_bounded` helper — GNU `timeout --kill-after` when available,
otherwise a process-group-plus-poll fallback — for configuration resolution, local `--version`
probes, and hosted `gh api` GETs. Do not call `gh_api_bounded` here: its existing fallback lacks
process-group isolation without `setsid` and may leave descendants alive when the leader exits.
Keep that shared helper unchanged for its existing callers; the new helper returns `124` on timeout.
Use `setsid` when available, otherwise `perl -e 'setpgrp; exec @ARGV' --`, following
`local-ai-reviewer.sh`'s existing portable launch mechanism. The new helper uses a **one-second**
TERM-to-KILL grace (not that script's two seconds), redirects child output to temporary files,
and always kills the process group after the grace even if its leader already exited. Check for
Perl when both GNU `timeout` and `setsid` are absent; missing launch support is exit `2`.
T-46 exercises a TERM-ignoring descendant with neither GNU `timeout` nor `setsid` present,
for both local probes and hosted GETs, including a leader that exits on TERM before its child.

Do not call `gh_available`: `workflow-lib.sh:186` runs an unbounded `gh auth status`.
Use `have_cmd gh` followed directly by the bounded GET instead; its auth/API failure already maps
to `check-inconclusive`. There is no separate authentication preflight to hang. T-47 asserts that
`gh auth status` is never invoked and that a stalled GET stays bounded. `run_bounded` is a new function in
`resolve-reviewer-availability.sh` rather than an extraction from `local-ai-reviewer.sh`; see
**Out-of-scope notes** for why that duplication is deliberate.

### Fixed evaluation order

The script executes exactly these phases, in this order, and the output makes the order visible:

0. **Resolve the configuration**, under a bound (Decision 11). If the call does not complete → block,
   `BLOCK_CAUSE=config-resolution-inconclusive`, with both state fields `not-evaluated`. This phase
   is numbered zero because it produces no classification of its own: it is the single call that
   supplies the policy and the list that phases 1 and 2 then read.
1. **Read the policy.** `unreadable` → block, `BLOCK_CAUSE=policy-unreadable`. `unsupported` → block,
   `BLOCK_CAUSE=policy-unsupported`. `absent` or `empty` → `POLICY=warn`, `POLICY_SOURCE=default`.
   Both block paths print `CONFIG_LIST_STATE=not-evaluated`.
2. **Resolve the list.** Reaching this phase already establishes that both configuration files
   parsed, because a file that did not would have made the policy input unreadable in phase 1. So
   `malformed` here means only one thing: the `review.on_draft.runner` key is present and readable
   and its value is not a list. That → block, `BLOCK_CAUSE=list-malformed`. `absent` or `empty` →
   `FALLBACK_APPLIED=true`, continue to phase 3 before reporting the fallback.
3. **Mark override exclusions.** Entries in `shipped_runner` absent from the `effective_runner` list
   become `override-excluded`. They are never probed, which is why "excluded and also unreachable"
   is not a reachable combination. After recording them, a fallback run jumps to phase 6; an empty
   override therefore still reports every removed shipped reviewer (T-45).
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
| The configured reviewer list | `review-effective` `effective_runner` (JSON array) | `REVIEWER_COUNT` and each `REVIEWER_N_NAME`; `CONFIGURED` is the display-only summary of the same set |
| Which reviewers the override left out | `review-effective` `override_excluded` (JSON array) | `REVIEWER_N_STATUS=override-excluded`; `OVERRIDE_EXCLUDED` is the display-only summary |
| Whether each reviewer can be invoked here | The availability probe table. **Changed by this feature**: was the driving runner's identity, is now capability | `REVIEWER_N_STATUS` |
| The reason a reviewer cannot be invoked | The same probe | `REVIEWER_N_REASON`, with `REVIEWER_N_REMEDY` beside it |
| The unavailable-reviewer policy | `review-effective` `effective_policy` and `effective_policy_state` | `POLICY`, `POLICY_STATE` |
| Whether each configured value is supported | The probe table's final row | `value-not-supported` reason |
| The driving runner's kind | `--runner-kind` / `$WORKFLOW_RUNNER_KIND` | `RUNNER_KIND` |

### Allowed outcomes and required next actions

Every row is reachable under the fixed evaluation order. Combinations that the order makes
unreachable are listed under the table so their absence is not read as an omission.

| Gate input state | `OUTCOME` | `BLOCK_CAUSE` | Exit | What the gate does | Operator's next action |
| --- | --- | --- | --- | --- | --- |
| The configuration resolution did not complete within its bound | `blocked` | `config-resolution-inconclusive` | `1` | Dispatches nobody; reports that the configuration could not be read in time; prints `POLICY_STATE=not-evaluated`, `CONFIG_LIST_STATE=not-evaluated`, `REVIEWER_COUNT=0`, and no per-reviewer reason | Re-run; if it recurs, check that `python3` and the repository root are reachable |
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
- *A per-reviewer reason accompanying `config-resolution-inconclusive`* — that block happens in
  phase 0, before any reviewer is named, so there is nothing to attach a reason to. It is the one
  block cause with no `REVIEWER_*` records at all.
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
      Add a keyword-only `preserve_empty_values=False` option to `parse_yaml_subset`, `parse_mapping`,
      and `parse_list`, threading it through recursive calls. Only `review-effective` enables it:
      a bare key with no child becomes `None`, while an explicit `{}` stays a mapping. Existing
      consumers retain the current `{}` representation for bare keys. For the new command, bare/null
      reviewer values are `empty`, an empty mapping is `malformed`; bare/null policy values are
      `empty`, an empty mapping is `unreadable`. E-28 through E-31 and T-30 pin both modes.
      Leave `list_override_from_path`, `resolve_review_overrides`, and `cmd_review_overrides`
      behaviorally unchanged — other callers depend on them.
      *Covers*: AC group *Configuration inputs that are absent, empty, malformed, or unsupported*.
- [ ] `scripts/development-workflow/resolve-reviewer-availability.sh` — **new**. Implements the
      contract, the probe table, the budget, and the fixed evaluation order above. Sources
      `workflow-lib.sh` for `have_cmd` and output helpers (VL-7); hosted GETs use the new
      `run_bounded` wrapper, never the shared `gh_api_bounded`. Never call the
      unbounded `gh_available` authentication preflight. Executable bit
      set; passes `shellcheck --severity=warning`.
      *Covers*: AC groups *Reachability follows capability*, *The operator can tell why*,
      *Policy behavior is preserved*.
- [ ] `scripts/development-workflow/codex-github-reviewer.sh` — header comment only. Replace
      "Classifies as universally reachable: requires only gh CLI access" (lines 5-7) with a statement
      that it is a hosted-service reviewer whose availability is decided at runtime from whether the
      Codex GitHub App is installed for the repository, and that no runner is inherently barred
      because it needs no local Codex runtime. Correct the exit `2`/`3` caller guidance per
      Decision 8; no script runtime behavior or exit number changes.
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
        Keep the rule that `auto_review.drafts: false` is not an unreachability condition, but update
        its note to say the draft pre-check guarantees eligibility before dispatch, after the
        availability decision (Decision 9). State that the
        hosted-service activity signal is a **proxy** for the spec's installed-and-enabled clause,
        name the false-Reachable case, and require post-dispatch failures to remain review
        failures under either unavailable-reviewer policy
        (Decision 8, asserted by D-21).
      - Lines 1496-1556 (*Draft-state pre-check*): keep the condition, the reviewer-to-draft-restriction
        mapping, the posted `INFO` comment, and the "Why this matters" rationale unchanged. Move
        condition evaluation and `gh pr ready` conversion to immediately before the dispatch map,
        after the availability helper returns a proceed verdict. Evaluate the condition from the
        helper's indexed reviewer records, with no independent `review-effective` call. Without this,
        an unbounded preliminary parse can hang before the deadline, and a run that converts and then blocks
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
        exit codes; add all three cross-runner local CLI dispatch paths and verdict handling from Decision 5.
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
      decided by the bounded repository-activity proxy from Decision 8, it is not
      in the shipped default, and opting in means adding it to `review.on_draft.runner`. Cross-link
      the existing verification checklist at line 143.
      *Covers*: AC "The canonical protocol lists the hosted-service reviewer among its supported
      values, and states that its availability is decided at runtime."
- [ ] `.claude/agents/item-orchestrator.md` line 198 — keep the `codex-github` dispatch block and exit numbers, but align its
      post-dispatch failure handling with Decision 8; replace "This script is universally reachable from all runner contexts
      (Claude Code, Cursor, Codex, headless CI) because it uses only `gh` CLI — no Codex CLI runtime
      is needed" with a hosted-service statement: it needs no local Codex runtime, so no runner is
      inherently barred, and its availability uses the repository-activity proxy from Decision 8 — unavailable with
      reason `prerequisite-missing` when activity is absent, subject to the documented false
      classifications. Keep the post-dispatch review-failure rule explicit.
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
| T-1 | `runner: [codex]`, `--runner-kind claude`, fake `codex` present | `REVIEWER_COUNT=1`, `REVIEWER_1_NAME=codex`, `REVIEWER_1_STATUS=reachable`, `REVIEWER_1_REASON=` and `REVIEWER_1_REMEDY=` both empty, `OUTCOME=proceeded`, exit `0` | Reachability follows capability |
| T-2 | Same config, fake `codex` removed from `PATH` | `REVIEWER_1_STATUS=unreachable`, `REVIEWER_1_REASON=runtime-absent`, `REVIEWER_1_REMEDY` non-empty, `OUTCOME=blocked`, `BLOCK_CAUSE=zero-reachable`, exit `1` | Reachability follows capability |
| T-3 | `runner: [claude]`, `--runner-kind claude`, no `claude` on `PATH` | `REVIEWER_1_STATUS=reachable` by identity (Decision 3) | Reachability follows capability |
| T-4 | `runner: [claude]`, `--runner-kind cursor`, no `claude` on `PATH` | `REVIEWER_1_STATUS=unreachable` with `REVIEWER_1_REASON=runtime-absent` — identity never causes unreachability, absence does | Reachability follows capability |
| T-5 | Fake `codex` present but `--version` exits `1` | `REVIEWER_1_REASON=check-inconclusive`, not `runtime-absent` | Configuration inputs |
| T-6 | Fake `codex` present but sleeps past `LOCAL_PROBE_CAP_SECONDS`, under `WORKFLOW_REVIEWER_AVAILABILITY_TEST_MODE=1` with a shortened budget so the per-probe bound is what the case exercises | `REVIEWER_1_REASON=check-inconclusive`, `REVIEWER_1_DETAIL` names the bound | Configuration inputs |
| T-7 | Five configured entries, every fake binary sleeping, run at the **shipped** budget with no test-mode override | measured wall time, captured outside the script, is **at most 10 seconds**: a host Python supervisor records `time.monotonic()` before and after `subprocess.run`, passing the hermetic PATH only to the child, and fails when the unrounded elapsed value exceeds `10.0`, with no tolerance added. Every entry is classified, `ELAPSED_SECONDS` is at most ten seconds including cleanup, and the exit status is `0` or `1` but never a hang | Configuration inputs (ten-second ceiling) |
| T-8 | `runner: [not-a-reviewer]` | `REVIEWER_1_NAME=not-a-reviewer` with `REVIEWER_1_STATUS=unreachable` and `REVIEWER_1_REASON=value-not-supported`, `OUTCOME=blocked`, `BLOCK_CAUSE=zero-reachable` | Configuration inputs |
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
| T-19 | Local override keeps `codex` of a shipped `[claude, cursor, codex]` | the two dropped entries have `REVIEWER_N_STATUS=override-excluded` with empty `REASON` and `REMEDY`, `UNREACHABLE` empty, `OUTCOME=proceeded` | The operator can tell why |
| T-20 | Override in effect and one kept reviewer absent | `LOCAL_OVERRIDE_STATE` reports the file and origin from the resolver, not a guess | The operator can tell why |
| T-21 | `runner: [coderabbit]`, fake `gh` returns comments containing `coderabbitai[bot]`, `.coderabbit.yaml` enables auto-review | `REVIEWER_1_STATUS=reachable` | Reachability follows capability |
| T-22 | Same, fake `gh` returns comments with no bot activity | `REVIEWER_1_REASON=prerequisite-missing`, never `runtime-absent` | The operator can tell why |
| T-23 | Same, no `gh` on the hermetic `PATH` | `REVIEWER_1_REASON=check-inconclusive`, never `prerequisite-missing` | Configuration inputs |
| T-24 | `runner: [codex-github]`, fake `gh` returns comments from the configured bot login | `REVIEWER_1_STATUS=reachable` regardless of `--runner-kind` | Reachability follows capability |
| T-25 | Every scenario above, aggregate | no `REVIEWER_N_*` group ever pairs `runtime-absent` with a hosted-service name, or `prerequisite-missing` with a local-runtime name | The operator can tell why |
| T-26 | Missing `--owner`/`--repo` | exit `2`, no `OUTCOME` line, message on stderr | Contract completeness |
| T-31 | `.ai-dev-workflow.yaml` truncated mid-mapping so it will not parse | `POLICY_STATE=unreadable`, `BLOCK_CAUSE=policy-unreadable`, `CONFIG_LIST_STATE=not-evaluated`, the file named in the output, exit `1` | Configuration inputs |
| T-32 | The same fixture and command run three times: fake `codex` absent, then added, then removed | the `codex` record reads `unreachable runtime-absent`, then `reachable`, then `unreachable runtime-absent`, with no configuration file changed between runs | Reachability follows capability |
| T-33 | The repository's own `.ai-dev-workflow.yaml`, hermetic `PATH` containing **none** of `claude`, `cursor-agent`, `codex`, and no local override; run once per `--runner-kind` in `claude`, `cursor`, `codex` | every run exits `0` with `OUTCOME` not `blocked`, and the reviewer matching `--runner-kind` is `reachable` | The shipped default never traps |
| T-34 | Linked-worktree fixture: a `.git` **file** pointing at a main clone that holds the override | `LOCAL_OVERRIDE_STATE` reports the main clone's file with origin `main_clone`, taken from `review-effective`'s `local_override_origin` | The operator can tell why |
| T-35 | `internal_reviewers_unavailable_policy: [warn]` (a list where a scalar is required) | `POLICY_STATE=unreadable`, `BLOCK_CAUSE=policy-unreadable`, exit `1`; the default policy is not silently applied | Policy behavior is preserved |
| T-36 | Every fixture above, aggregate | no `REVIEWER_N_DETAIL` contains the run's `RUNNER_KIND` value — no unreachability is attributed to the driving runner | The operator can tell why |
| T-37 | Every fixture above, aggregate | every `REVIEWER_N_STATUS=unreachable` group has a `REVIEWER_N_REASON` that is exactly one of the four and a non-empty `REVIEWER_N_REMEDY`; every `reachable` and `override-excluded` group has both empty | The operator can tell why |
| T-38 | `runner: [codex-github]`, fake `gh` returning **only historical** bot comments (no other installation signal available to a user token) | `REVIEWER_1_STATUS=reachable`. This pins the decided behavior of **Decision 8**: historical activity alone is sufficient, and the residual false-Reachable case is handled at dispatch. A later change that silently tightens or loosens the proxy fails here instead of passing unnoticed | Decided-tradeoff guard |
| T-39 | Each of the five delimiter-bearing fixtures from E-23 to E-27, one run per fixture | `REVIEWER_COUNT=1`; `REVIEWER_1_NAME` equals the configured value byte for byte; `REVIEWER_1_STATUS=unreachable` with `REVIEWER_1_REASON=value-not-supported`; and the display-only `CONFIGURED` field renders it as `<entry 1>` rather than splitting it. E-26's empty entry additionally asserts `REVIEWER_1_NAME=` with the record still present | Configuration inputs |
| T-40 | Fake `python3` on the hermetic `PATH` that sleeps past `CONFIG_RESOLVE_CAP_SECONDS`, run at the shipped budget | exit `1`, `BLOCK_CAUSE=config-resolution-inconclusive`, `POLICY_STATE=not-evaluated`, `CONFIG_LIST_STATE=not-evaluated`, `REVIEWER_COUNT=0`, no `REVIEWER_*` group, and measured wall time **at most 10 seconds**, asserted exactly as in T-7. This is the case a deadline-without-a-bound would hang on | Configuration inputs |
| T-41 | Fake `python3` that exits `2` immediately | exit `2`, no `OUTCOME` line, the resolver's stderr on stderr — an invocation failure, not a configuration state | Contract completeness |
| T-42 | A reviewer name or detail containing a tab and a newline, injected through a fixture | the emitted block still has exactly one line per field: `print_kv_escaped` escaped them, so no value forged a line break or a second field. `review-effective`'s JSON carries the same value and the shell reads it NUL-delimited, so the round-trip is asserted end to end | Configuration inputs |
| T-43 | `runner: [claude, cursor, codex, not-a-reviewer]`, driving runner `codex`; earlier fake runtimes hang and exhaust a shortened test-mode budget before the last two entries | `codex` remains `reachable`, `not-a-reviewer` has reason `value-not-supported`, and default `warn` yields `proceeded-reduced`, never `zero-reachable`. Repeat the native-last case for each supported runner kind | The shipped default never traps |
| T-44 | Run the delimiter fixtures T-39 and the normal/default cases T-1 and T-33 under Bash 3.2, including `/bin/bash` on macOS | Same exit codes and indexed values; no `mapfile`/`readarray` dependency, no lost empty entry, and no array state lost in a pipeline subshell | Contract completeness |
| T-45 | Shipped `[claude, cursor, codex]`, local `runner: []`, supported driving runner | Fallback proceeds; all three shipped entries remain `override-excluded` with empty reason/remedy, `UNREACHABLE` empty, and fallback is dispatched only by the gate | The operator can tell why |
| T-46 | Shipped-budget timeout case on a PATH with neither GNU `timeout` nor `setsid`; Perl present; fake local probe and fake hosted GET each spawn a TERM-ignoring descendant while the leader exits on TERM | Verdict within ten seconds; `ELAPSED_SECONDS <= 10`; descendant and leader both gone after cleanup, temporary output does not hold stdout open. Repeat under Bash 3.2 | Contract completeness |
| T-47 | Hosted reviewer with fake `gh` whose `auth status` would hang; exercise a successful GET and a hanging GET | No auth-preflight invocation; success classifies reachable with activity, hanging GET yields `check-inconclusive` within ten seconds | Configuration inputs |
| T-48 | Unsupported scalar policy containing whitespace/control characters, non-scalar policy, and unparseable file | `POLICY_INPUT`, `UNREADABLE_FILE`, and `UNREADABLE_DETAIL` preserve resolver diagnostics through escaped shell fields; `POLICY` is empty on invalid paths. Runbook Step 14 checks the same values reach the block comment | Policy behavior is preserved |

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
| R7 | Reachable, dispatched, then fails → review failure, not unreachable | Gate | Gate doc assertion D-6; gate runbook Step 13 Part 4 deliberately makes a callable reviewer fail only at dispatch. The resolver has already exited before dispatch, so no unit test of this feature can observe it |
| S1 | Shipped default, no override → dispatched reviewer and a verdict on every supported runner | Both | Resolver unit T-33 (a non-blocked verdict for every supported runner kind on a `PATH` holding none of the three runtimes); gate doc assertion D-12; gate runbook Step 1 for the verdict on every supported runner kind and Step 13 Part 1 for the dispatch |
| S2 | The shipped list names at least one reviewer reachable wherever a supported runner drives | Resolver | T-33, T-43 |
| S3 | Shipped commentary does not call a hard-fail on a supported runner expected behavior | Surface text | D-9 |
| O1 | Every Unreachable reviewer reported with name, exactly one reason, and at least one action | Both | Resolver unit T-37 (the reason is one of four and `REVIEWER_N_REMEDY` is non-empty); gate doc assertions D-5 (the protocol's four remedies match the script's) and D-16 (the comment formats carry name, reason, and remedy per reviewer); gate runbook Step 13 Part 3 and Step 14 Part 1 read the posted comments |
| O2 | The four reasons are distinguished and never reported in place of one another | Resolver | T-25 (no cross-kind pairing), T-2, T-5, T-8, T-22, T-23 (one per reason) |
| O3 | The gate summary lists every configured reviewer with its verdict, including the ones that ran | Gate | Gate doc assertion D-16; gate runbook Step 13 Part 1. T-19 proves the resolver emits a `REVIEWER_N_*` group per entry, which is the input the summary needs — necessary, not sufficient, so it is not listed as evidence for this criterion |
| O4 | Override-removed reviewer is Excluded by override, no unreachability warning | Both | Resolver units T-19 and T-45 (the group carries `REVIEWER_N_STATUS=override-excluded` with empty reason); gate doc assertion D-16 (excluded entries appear in the summary and never in the warning); gate runbook Step 14, which runs the real gate with an override in effect |
| O5 | Block report names the policy, and reports override state from what was resolved | Both | Resolver unit T-16, T-20, T-34, T-13 produce the four field values; gate doc assertion D-18 (the hard-fail formats carry `BLOCK_CAUSE` and `LOCAL_OVERRIDE_STATE` taken from the resolver, never inferred); gate runbook Step 14 Part 1 |
| O6 | No message attributes unavailability to the driving runner's identity | Both | Resolver unit T-36 (no detail string contains the run's `RUNNER_KIND`); gate doc assertions D-17 and D-18 (neither comment template carries a runner-context field), plus D-2 and D-10 for the surrounding surfaces; gate runbook Step 13 Part 3 and Step 14 Part 1 |
| C1 | No list in either file → runs the stage default **once** and records the fallback in the summary | Both | Resolver unit T-10 (`FALLBACK_APPLIED=true`); gate doc assertions D-12 (dispatch the driving runner's stage reviewer exactly once) and D-16 (the summary records that the fallback applied); gate runbook Step 13 Part 2 |
| C2 | The fallback reviewer is the driving runner's own for the stage, so it never blocks | Both | Resolver unit T-10 and T-12 (`FALLBACK_APPLIED=true` for a supported runner, `no-driving-runner` for `unknown`); gate doc assertions D-7 and D-12; gate runbook Step 13 Part 2 |
| C3 | A list resolving to no entries behaves as C1; never reports success having dispatched nobody | Both | Resolver unit T-11; gate doc assertions D-12 and D-16; gate runbook Step 13 Part 2 |
| C4 | Unsupported entry → Unreachable, reason `value-not-supported`, value named in the report | Both | Resolver unit T-8, T-9 (classification and named value in the `REVIEWER_N_NAME` field) and T-39 (a value containing a comma, whitespace, both, an apostrophe, or nothing at all still round-trips byte for byte and is named, never split or dropped — Decision 10); gate doc assertion D-18 (the offending value is named in the block report); gate runbook Step 14 Part 1, second run, and Step 15 |
| C5 | List defined but not readable as a list → blocks, names file and input, dispatches nobody, PR stays draft | Both | Resolver unit T-13 (`BLOCK_CAUSE=list-malformed`, exit `1`); gate doc assertions D-18 (the report names the file and the key), D-19 (exit `1` maps to dispatch nobody, no `gh pr ready`, PR stays draft, escalate) and D-20 (no draft conversion can precede the block); gate runbook Step 14 Part 2, with Part 5 for the draft-conversion ordering |
| C6 | A file that will not parse at all → blocks and names that file | Both | Resolver unit T-31, T-29; gate doc assertions D-18 and D-19; gate runbook Step 14 Part 2 |
| C7 | An unsupported value as the only entry → blocks and names it as the cause | Both | Resolver unit T-8 and T-39; gate doc assertions D-18 and D-19; gate runbook Step 14 Part 1, second run, and Step 15 |
| C8 | A determination that cannot complete → `check-inconclusive`; verdict within ten seconds | Both | T-6 (per-probe bound), T-7 (whole-list budget with every probe hanging), T-40 (the configuration-resolver call bounded too, so the ceiling holds for the one call that precedes every probe — Decision 11); D-20 excludes an unbounded pre-check; gate runbook Step 6 and Step 16, including the complete gate entry path |
| C9 | A determination that ends promptly without an answer → the same reason, not the other two | Resolver | T-5, T-23 |
| P1 | One unreachable, one reachable, `warn` → warns naming each, then dispatches the rest | Both | Resolver unit T-9 (`OUTCOME=proceeded-reduced`) and T-37 (reason and remedy available to quote); gate doc assertion D-17 (the warning names each unreachable reviewer with its reason and remedy and states the reachable subset) and D-12 (the reachable subset is then dispatched); gate runbook Step 13 Part 3 |
| P2 | `fail-if-any-unavailable` + any unreachable → blocks, dispatches nobody, PR stays draft | Both | Resolver unit T-16; gate doc assertions D-18, D-19 and D-20; gate runbook Step 14 Part 3, with Part 5 for the draft-conversion ordering |
| P3 | No reviewer reachable → blocks under either policy, PR not converted to ready, escalates | Both | Resolver unit T-2 (under `warn`) and T-16 (under the strict policy); gate doc assertions D-19 (exit `1` maps to no `gh pr ready`, draft preserved, escalation) and D-20 (the draft-state pre-check's conversion cannot precede the block); gate runbook Step 14 Part 1 and Part 5 |
| P4 | Every reviewer reachable → no warning, behaves exactly as today | Both | Resolver unit T-1, T-19 (`OUTCOME=proceeded`, `UNREACHABLE` empty, every `REVIEWER_N_REMEDY` empty); gate doc assertion D-17 (the warning is posted only when `OUTCOME=proceeded-reduced`); gate runbook Step 13 Part 1 |
| P5 | No policy in either file → the shipped default `warn` applies | Resolver | T-18 |
| P6 | Unsupported policy value → blocks, dispatches nobody, names it, does not silently default | Both | Resolver unit T-17 (`BLOCK_CAUSE=policy-unsupported`, the value carried in the output); gate doc assertions D-18 (the report names the offending value) and D-19 (nobody is dispatched); gate runbook Step 14 Part 4 |
| P7 | Unsupported or unreadable policy with an absent, empty, or malformed list → blocks on the policy | Both | Resolver unit T-17, T-31 (`CONFIG_LIST_STATE=not-evaluated`); gate doc assertion D-18 (the report attributes the block to the policy); gate runbook Step 14 Part 4 |
| P8 | Policy input present but unreadable → blocks and names the input | Both | Resolver unit T-31, T-35; gate doc assertions D-18 and D-19; gate runbook Step 14 Part 2 |
| P9 | A reachable reviewer under a forbidding policy is still classified Reachable in the report | Both | Resolver unit T-16 (the group still reads `REVIEWER_N_STATUS=reachable`); gate doc assertion D-18 (the block report lists every reviewer with its verdict, including the reachable ones); gate runbook Step 14 Part 3 |
| P10 | Never installs, provisions, or substitutes; the fallback is not a substitution | Both | Resolver unit T-15 (no mutating call in the recorded `gh` argv), T-2 (an absent runtime yields a block, never a stand-in); gate doc assertion D-8; gate runbook Step 13 Part 2 (the fallback dispatches the runner's own reviewer, not a stand-in for an unreachable one) and Step 14 Part 1 (an unreachable reviewer produces a block, never a substitution) |
| A1 | Supported values and the availability rule stated consistently across surfaces | Surface text | D-1, D-5, D-11 |
| A2 | No surface names a value the canonical protocol does not list | Surface text | D-4 |
| A3 | The canonical protocol lists the hosted-service reviewer and states its runtime availability rule | Surface text | D-1 |
| A4 | No surface claims the hosted-service reviewer is unconditionally available | Surface text | D-3 |
| A5 | No surface states or implies availability is decided by runner identity | Surface text | D-2, D-10 |
| A6 | CodeRabbit's runtime-conditions guidance is unchanged and does not contradict the rule | Surface text | D-10 |

#### What this map admits

- **Six criteria are resolver-only** — R2, R3, O2, S2, C9, P5. Each asserts what the verdict
  *is* for a given environment, which is exactly what a unit test can settle.
- **Seven are statements about surface text** — S3 and A1 to A6. A doc assertion is not second-best
  evidence for these; it is the right instrument, because the criterion is about what the text says.
- **Twenty-eight are gate-level, wholly or in part** — every remaining ID: twenty-six marked
  `Both`, plus R7 and O3, which constrain only the gate. For each, the resolver unit case (where one
  exists) proves only that the verdict handed to the gate was correct. The doc assertion proves the
  protocol instructs the right response, and the runbook step is the only evidence that a runner
  produced it.
- **One criterion, R7, has no achievable automated evidence** and says so: the resolver has exited
  before dispatch, so a reviewer that then fails is observable only in the protocol text (D-6) and in
  runbook Step 13.
- **T-19 is deliberately not listed under O3.** It proves the resolver emits a per-reviewer `REVIEWER_N_*` group —
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

Cases D-1 to D-11 assert what the surfaces **say about themselves**. Cases D-12 to D-22 assert that
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
| D-6 | Protocol 91 states that a reviewer classified Reachable, dispatched, and then failing, erroring, or timing out is a review failure and not an availability verdict; its dispatch guidance includes all three local CLI paths and terminal-verdict validation from Decision 5 | R7, R1 |
| D-7 | Protocol 91 and `README.md` both describe the fallback as the driving runner's own stage reviewer, and neither names a fixed reviewer for it | C2 |
| D-8 | Protocol 91 states that the gate never installs a missing runtime, provisions a missing prerequisite, or substitutes a different reviewer | P10 |
| D-9 | `.ai-dev-workflow.yaml`'s `review.on_draft.runner` is exactly `claude`, `cursor`, `codex`, and the file contains no text describing a hard-fail of this gate on a supported runner as expected behavior | S3 |
| D-10 | `coderabbit.md` still states both of its availability checks — the App activity signal and `reviews.auto_review.enabled: true` — and its Step 7a hard-fail remedy names no runner context | A6, A5 |
| D-11 | The `codex-github` runner reviewer dispatch block is byte-identical in `.claude/agents/item-orchestrator.md` and `.cursor/agents/item-orchestrator.md` | A1 |

**Gate-instruction assertions:**

| ID | Assertion | AC |
| --- | --- | --- |
| D-12 | On resolver exit `0`, Protocol 91 instructs dispatching each indexed `REVIEWER_N_NAME` whose `REVIEWER_N_STATUS` is `reachable`, and where `FALLBACK_APPLIED=true` instructs dispatching the driving runner's own stage reviewer exactly once — the word "once" is asserted, because "runs it once" is the criterion | R1, S1, C1, C2, C3, P1 |
| D-13 | Protocol 91 instructs running the availability resolver at the start of every Step 7a cycle, including re-runs after fixes, and states that a verdict from an earlier cycle is never reused | R4 |
| D-14 | During availability determination, from helper invocation until its return, Protocol 91 instructs no `gh pr comment`, no `gh pr ready`, and no command that writes to the working tree. After it returns, policy warning/block comments and the proceed path's conditional draft conversion are permitted before dispatch | R5 |
| D-15 | Protocol 91 places the resolver call before the reviewer dispatch map and states that no reviewer is dispatched until the resolver returns and the policy has been applied | R6 |
| D-16 | The Step 7a summary comment format requires one line per configured reviewer with its display label; for each Unreachable one, its reason display label and its remedy; and, where `FALLBACK_APPLIED=true`, a line recording that the fallback applied. Override-excluded entries appear in the summary and never in the warning | O1, O3, O4, C1, C3 |
| D-17 | The warning comment format carries no runner-context field, names each unreachable reviewer with its reason and its remedy, states the reachable subset that will run, and is posted only when `OUTCOME=proceeded-reduced` | O6, P1, P4 |
| D-18 | Each hard-fail comment case names `BLOCK_CAUSE`; every configured reviewer with its verdict, including the reachable ones; the offending value or unreadable input where one exists; the policy where the policy is the cause; and `LOCAL_OVERRIDE_STATE` taken from the resolver rather than inferred. No case carries a runner-context field | O5, O6, C4, C5, C6, C7, P2, P6, P7, P8, P9 |
| D-19 | Protocol 91 maps resolver exit `1` to: dispatch nobody, do not call `gh pr ready`, leave the pull request draft, escalate to a human — and maps exit `2` to the same treatment with cause `availability-resolver-failed` | C5, C6, C7, P2, P3, P6, P8 |
| D-20 | Protocol 91 invokes the bounded availability helper before evaluating the draft pre-check; condition evaluation consumes its indexed records only after a proceed verdict, with no independent `review-effective` call. Conversion appears after that verdict and before dispatch. The draft-eligibility note says conversion guarantees non-draft at dispatch, not at availability time. Runbook Step 16 also exercises a stalled parser through the complete gate entry path | C5, P2, P3, P6, P7, P8, C8; Decision 9 |
| D-21 | Protocol 91's hosted-service probe section states that the activity signal is a proxy for the spec's installed-and-enabled clause, names the false-Reachable case, and requires any resulting dispatch failure to remain a review failure under either policy, retaining the original availability classification | Decision 8 |
| D-22 | Protocol 91 instructs the gate to read reviewer names, reasons, remedies, and details from the indexed `REVIEWER_N_*` fields, and states that the comma-joined aggregate fields are display-only. No instruction anywhere in Step 7a splits an aggregate field on commas or whitespace to recover a reviewer name | C4, C7; Decision 10 |

### Planted-violation proofs

`REVIEW.md` line 325 is explicit and I am not going to argue it down: *"Planted-violation proof
presence (blocking): confirm the PR evidence includes, **for each new or materially modified check**, a
demonstrated run at a concrete file and line showing (a) the check fails when the targeted violation is
present at that location, and (b) the check passes once the violation is removed."* Line 400 adds that
the plant must be able to change that check's answer — *"a proof whose plant is masked by an earlier
rule is not a proof"*. One plant per assertion *mechanism* would not satisfy either clause, so the
plan commits to per-check proofs. The exemption at line 328 (pure refactors of already-proven logic)
does not apply: every check here is new.

What the rule does and does not reach is worth stating, because it bounds the work honestly:

- **In scope — the 22 `D-` cases.** Each is an automated check over repository content, which is
  exactly what the clause names. Each gets its own plant, listed below.
- **In scope — `resolve-reviewer-availability.sh` as a guard.** Its planted-violation evidence already
  exists in the `T-` suite as fail-and-pass pairs over the same fixture shape, and naming them is
  enough: T-2/T-1 (reviewer absent then present), T-13/T-27 (malformed then well-formed list),
  T-17/T-18 (unsupported then absent policy), T-31/T-29 (unparseable then parseable file),
  T-16/T-9 (strict then permissive policy). The implementer records those pairs as the guard's proof
  rather than writing new cases.
- **Out of scope — the `T-` and `E-` cases themselves.** A unit test of a script is not a check,
  guard, lint rule, or CI job; it is the test of one. Treating each as requiring its own planted
  violation would recurse without end.

**Plant table.** Each row is a one-line mutation at a real location that flips exactly one case. The
harness reports per-case `PASS`/`FAIL`, so the implementer records, per row, the failing run with the
plant applied and the passing run after reverting it.

| Case | File to plant in | Mutation that flips it |
| --- | --- | --- |
| D-1 | `91-orchestrate-work-protocol.md`, supported-values line | delete `codex-github` from the list |
| D-2 | `91-orchestrate-work-protocol.md`, availability section | re-insert the sentence `runner identity is a sufficient proxy for reviewer reachability` |
| D-3 | `codex-github-reviewer.sh` header | restore the words `universally reachable` |
| D-4 | `.ai-dev-workflow.local.example.yaml`, `review.on_draft.runner` | add an entry `greptile`, which the canonical protocol does not list as a runner reviewer; leave the shipped default unchanged so D-9 still passes |
| D-5 | `91-orchestrate-work-protocol.md`, reason-to-remedy table | change one word of the `runtime-absent` remedy so it no longer matches the script's string |
| D-6 | `91-orchestrate-work-protocol.md`, dispatch section | delete the sentence classifying a dispatched-then-failed reviewer as a review failure |
| D-7 | `README.md`, configuration-reference bullet | reintroduce `the stage-appropriate \`claude\` reviewer` as the fallback |
| D-8 | `91-orchestrate-work-protocol.md`, policy section | delete the never-installs-never-substitutes sentence |
| D-9 | `.ai-dev-workflow.yaml`, commentary | re-add a sentence calling a hard-fail on a supported runner expected behaviour |
| D-10 | `integrations/coderabbit.md`, availability check | delete the `reviews.auto_review.enabled: true` requirement |
| D-11 | `.cursor/agents/item-orchestrator.md`, `codex-github` block | change one word so it no longer matches `.claude/agents/item-orchestrator.md` |
| D-12 | `91-orchestrate-work-protocol.md`, dispatch instruction | delete the word `once` from the fallback-dispatch sentence |
| D-13 | `91-orchestrate-work-protocol.md`, Step 7a re-run rules | delete the instruction to re-run the resolver on every cycle |
| D-14 | `91-orchestrate-work-protocol.md`, availability phase | insert an instruction to post `gh pr comment` while availability determination is still running, before the helper returns |
| D-15 | `91-orchestrate-work-protocol.md` | move the resolver-call block below the dispatch map |
| D-16 | `91-orchestrate-work-protocol.md`, summary-comment format | delete the required per-reviewer verdict line |
| D-17 | `91-orchestrate-work-protocol.md`, warning format | re-add a `(<runner-context>)` field |
| D-18 | `91-orchestrate-work-protocol.md`, hard-fail Case A | delete `Local override:` from the template |
| D-19 | `91-orchestrate-work-protocol.md`, exit-code mapping | change the exit `1` row to call `gh pr ready` |
| D-20 | `91-orchestrate-work-protocol.md`, draft-state pre-check | move the `gh pr ready` conversion back above the availability check |
| D-21 | `91-orchestrate-work-protocol.md`, hosted-probe section | delete the sentence naming the activity signal a proxy |
| D-22 | `91-orchestrate-work-protocol.md`, gate-consumption instruction | change it to split `CONFIGURED` on commas to recover reviewer names |

Sixteen of the twenty-two plant into Protocol 91 because that is the canonical surface the suite
exists to protect; each targets a different sentence, so no plant is masked by another rule. Where two
cases read nearby text, the plant is chosen to change only the one case's answer — the implementer
must confirm that from the per-case output, not assume it. See Implementation Order step 8.


### Extended suite: `scripts/development-workflow/tests/test-workflow-config-resolver.sh`

| ID | Scenario | Asserts | AC group |
| --- | --- | --- | --- |
| T-27 | `review-effective` with a shipped list and no local file | stdout parses as a single JSON object; `effective_runner` equals the `.ai-dev-workflow.yaml` list as an array, `effective_runner_state` is `defined`, `override_excluded` is `[]` | Configuration inputs |
| T-28 | Local file overrides the list | `effective_runner_source` names the local file; `shipped_runner` still reports the shipped list; `override_excluded` is the set difference | Configuration inputs |
| T-29 | `.ai-dev-workflow.yaml` truncated mid-mapping so it will not parse | `effective_policy_state` is `unreadable`, `effective_runner_state` is `malformed`, `unreadable_file` names the file, exit `0` with valid JSON on stdout | Configuration inputs |
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
| E-23 | `runner: ["codex, claude"]` — one quoted entry containing a comma | `defined`, and `effective_runner` is a one-element array whose element is `codex, claude` verbatim. Never two elements |
| E-24 | `runner: ["my reviewer"]` — one quoted entry containing whitespace | `defined`, one entry whose value is `my reviewer` verbatim, internal space preserved |
| E-25 | `runner: ["a, b c"]` — one entry containing both a comma and whitespace | `defined`, one entry, value verbatim |
| E-26 | `runner: [""]` — one empty-string entry | `defined`, one entry whose value is the empty string. Not `empty`: the list has an entry, and that entry is unsupported |
| E-27 | `runner: ["it's"]` — one entry containing a single quote | `defined`, one entry, value verbatim. The apostrophe survives because the field is `KEY=value` to end of line rather than shell-quoted (Decision 10) |
| E-28 | `runner: {}` compared with bare `runner:` | Mapping is `malformed`; bare value is `empty`; legacy parser mode retains its original outputs |
| E-29 | `runner: null` and `runner: ~` | `empty`, matching the bare empty scalar |
| E-30 | `internal_reviewers_unavailable_policy: {}` compared with the bare policy key | Mapping is `unreadable` with file/type diagnostics; bare value is `empty` |
| E-31 | Policy value `null` and `~` | `empty`, default `warn`; legacy parser output remains unchanged |

**Unit test mapping**: every case E-1 through E-31 gets one automated case in
`scripts/development-workflow/tests/test-workflow-config-resolver.sh`, named `review-effective E-<n>`,
asserting the exact expected state string. E-22 additionally asserts `LOCAL_OVERRIDE_ORIGIN=main_clone`.
E-23 to E-27 each additionally assert the **entry count** — one, never two — and that the entry's
value round-trips byte for byte, which is the property a comma-joined field could not provide.

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
| R-12 | The gate re-derives reviewer names by splitting a display-only aggregate field, reintroducing the delimiter hole one layer up | Medium | Medium | D-22 asserts Protocol 91 instructs reading the indexed fields and never splitting the aggregates, and the contract labels the aggregates display-only at the point of definition. The aggregates render an unsafe value as `<entry N>` precisely so a gate that splits them anyway produces something obviously wrong rather than something plausibly wrong. |
| R-11 | A hosted service that was uninstalled, suspended, or had its access revoked still shows historical activity and classifies `reachable` (false Reachable), so the gate dispatches a reviewer that is not there | Medium | Medium | **Decided tradeoff, not a defect to fix later — see Decision 8.** No mechanism available to the gate's user-token credentials can establish current installation and per-review enablement. The residual is handled at dispatch as a review failure under either policy, retaining its Reachable classification and preventing advancement on reduced coverage; correct the old header and mirrored Step 7a caller guidance that instead treated the timeout as unavailable. Blast radius is limited to repositories that opt a hosted reviewer into `review.on_draft.runner`, which the shipped default does not. Visible to operators in the probe table, the runbook's Troubleshooting table, and its Known Limitations; pinned by T-38 and D-21. |
| R-4 | Two config readers now coexist — the Python resolver for Step 7a and the awk helpers for Step 7 — and could drift | Medium | Medium | Decision 2 names the resolver as authoritative for Step 7a and records the non-unification as deliberate; **Out-of-scope notes** carries it forward as a follow-up candidate. |
| R-5 | Re-adding `codex-github` to Step 7a revives the async race #486 moved it out for | Low | Medium | Decision 7: it is canonical but not default, and its dispatch goes through `codex-github-reviewer.sh`, whose pre-trigger wait, retrigger, and exit-code contract were built after #486. |
| R-6 | `run_bounded` duplicates `run_with_timeout` from `local-ai-reviewer.sh` | High | Low | Deliberate, recorded in **Out-of-scope notes**. Extracting the reviewer script's variant would change a heavily used Step 7 path for a Step 7a benefit, which the spec places out of scope. |
| R-7 | The ceiling tests (T-7, T-40) assert a hard 10-second wall-clock bound and could flake on a heavily loaded CI runner | Medium | Low | The assertion is not loosened to accommodate load, because then it would stop testing the contract. Headroom comes from the budget instead: 8 seconds of work plus at most 2 seconds of documented cleanup equals the 10-second contract, so a run has to be delayed by more than two seconds of pure scheduling latency before it fails. If that proves too tight in practice the fix is to lower `AVAILABILITY_BUDGET_SECONDS`, which keeps the contract intact; raising the assertion would not. |
| R-13 | The twenty-two planted-violation proofs are mechanical and an implementer may batch them carelessly, producing plants that do not actually change the cited case's answer | Medium | Medium | The plant table names a different sentence per case and the verification step requires confirming that no other case changed answer, which is the specific failure `REVIEW.md` line 400 calls out. Sixteen plants land in one file, so the per-case output is the only way to tell them apart — the step says to read it rather than assume. |
| R-8 | The doc-assertion suite (D-1 to D-22) breaks on innocent rewording of the surfaces it greps | Medium | Low | Each case asserts a short stable phrase or a structural fact (a value list, a byte-for-byte block comparison), never a whole sentence. Implementation Order step 8 requires proving each case can fail before the suite is accepted, so a case that has silently stopped asserting anything is caught at authoring time rather than months later. |
| R-9 | The change is reverted after operators retired their machine-local override on its advice, and the override file cannot be restored by any revert | Low | Medium | Retirement guidance says move the file aside rather than delete it, so a second `mv` restores it; the override is two keys and `.ai-dev-workflow.local.example.yaml` carries the shape. See **Reversal and Rollback** (c) — this is mitigated, not eliminated. |
| R-10 | The resolver is implemented correctly and the gate ignores its verdict — dispatching on a block, or skipping dispatch on a proceed | Medium | High | This is the feature's most likely failure and no resolver test can see it. D-12 and D-19 assert the protocol instructs the exit-code mapping; runbook Steps 13 and 14 observe a runner honouring it, while Step 16 verifies its bounded entry path. The runbook's Troubleshooting table names a mismatch as a blocking implementation failure. The coverage map marks all twenty-eight gate-level criteria so no reviewer has to rediscover the distinction. |

---

## Code Samples

The illustrative Bash 3.2 array-reading snippet under **Contracts** demonstrates lossless entry
transport. It is not production implementation; the implementer supplies the temporary paths and
verifies it with T-44. Other contracts use tables and command signatures.

---

## Implementation Order

> Ordered steps. Later steps may depend on earlier ones.

Every step declares its source. **Spec-derived** steps name the acceptance-criterion groups or use
cases they exist to satisfy. **Repository process** steps are not derived from the spec at all; they
are obligations this repository places on every change of this kind, and each says which document
imposes it and why it applies here. No step is left untraced.

1. *(Spec-derived — AC group* **Configuration inputs that are absent, empty, malformed, or unsupported***; the absent / empty / malformed / unreadable distinction the gate needs, plus the verbatim entry values Decision 10 requires.)* **`workflow-config-resolver.py`**: add `typed_value_from_path`, `resolve_review_effective`,
   `cmd_review_effective`, and the `review-effective` subparser per **Contracts**, including the
   opt-in `preserve_empty_values` parser mode specified under **Shared Packages / Libraries**. Do not change
   `list_override_from_path`, `resolve_review_overrides`, or `cmd_review_overrides`.
   *Verify*: run
   `python3 scripts/development-workflow/workflow-config-resolver.py review-effective --repo-root "$(pwd -P)"`
   and confirm the output is a single JSON object carrying every field in the contract table, that
   `effective_runner_state` is `defined`, and that `effective_runner` matches what
   `.ai-dev-workflow.yaml` (or the local override, if one is in effect) actually contains. Pipe it
   through `jq .` and confirm it parses.

2. *(Spec-derived — evidence for the same group, plus the parser-risk unit-test mapping this repository's plan protocol requires for a change that alters structured-text interpretation.)* **Extend `tests/test-workflow-config-resolver.sh`** with cases T-27 to T-30 and `review-effective E-1`
   through `review-effective E-31`.
   *Verify*: `bash scripts/development-workflow/tests/test-workflow-config-resolver.sh` — read the
   output and confirm every new case reports PASS and no pre-existing case regressed.

3. *(Spec-derived — AC groups* **Reachability follows capability***,* **The operator can tell why***,* **Policy behavior is preserved***; Use Cases 1, 2, and 4.)* **Write `scripts/development-workflow/resolve-reviewer-availability.sh`** implementing the
   evaluation order, the probe table, the budget constants, the output block, and the three exit
   codes. Source `workflow-lib.sh`. `chmod +x`.
   *Verify*: `shellcheck --severity=warning scripts/development-workflow/resolve-reviewer-availability.sh`
   reports nothing; then run it against this repository with
   `--runner-kind claude` and confirm the printed `OUTCOME`, `REACHABLE`, and `UNREACHABLE` values
   match what is actually installed on the machine.

4. *(Spec-derived — the resolver-layer evidence named in the acceptance-criterion coverage map.)* **Write `tests/test-resolve-reviewer-availability.sh`** with the `# covers:` header and cases T-1
   to T-26 and T-31 to T-48, using the hermetic-`PATH` pattern from `test-local-ai-reviewer.sh`.
   *Verify*: `bash scripts/development-workflow/tests/test-resolve-reviewer-availability.sh` — confirm
   every case reports PASS. Then run
   `bash scripts/development-workflow/select-test-suites.sh` against the change set and confirm the
   new suite appears in the selection, so no CI workflow edit is needed.

5. *(Spec-derived — every AC group; this is the canonical surface, and it carries all twenty-eight gate-level criteria.)* **Rewrite Protocol 91 Step 7a** (all seven regions listed under **Backend / Protocol surfaces**, including moving the draft-state pre-check's `gh pr ready` conversion to after policy application per Decision 9).
   *Verify*: `grep -n "runner identity is a sufficient proxy\|Reachability classification table\|default behavior: \`claude\`" docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`
   returns nothing; and read the Step 7a text end to end confirming the only `gh pr ready` before the
   dispatch map is the draft-state conversion, and that it now sits after the policy-application
   step rather than at the top of the section.

6. *(Spec-derived — AC group* **The shipped default never traps***; Use Case 3.)* **Change `.ai-dev-workflow.yaml`**: the default list, the supported-values comment, the deleted
   Runner-context constraint block and its replacement, and the policy comment.
   *Verify*: re-run the step-1 command and confirm `effective_runner` reports the new default
   when no local override is in effect; and
   `grep -n "expected behaviour" .ai-dev-workflow.yaml` returns nothing.

7. *(Spec-derived — AC group* **Surfaces agree***.)* **Update the remaining surfaces**, all ten: `README.md`, `integrations/coderabbit.md`,
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

8. *(Spec-derived — the gate-doc-assertion evidence named in the coverage map, covering* **Surfaces agree** *and the protocol-instruction half of every gate-level criterion.)* **Write `tests/test-step7a-surface-consistency.sh`** with the `# covers:` headers and cases D-1 to
   D-22. Write it **after** steps 5 to 7, because D-1 to D-11 target text those steps produce on the
   surrounding surfaces and D-12 to D-19 target the Step 7a gate instructions written in step 5.
   *Verify*: `bash scripts/development-workflow/tests/test-step7a-surface-consistency.sh` — confirm
   every case reports PASS. Then work the **plant table** under *Planted-violation proofs* row by row:
   apply the listed one-line mutation, re-run, confirm **that** case reports FAIL and that no other
   case changed answer, revert, and re-run to confirm PASS. Record both runs per case in the pull
   request, citing the file and line the plant went in at. `REVIEW.md` line 325 requires this for each
   check and line 400 requires the plant to be able to change that check's answer, so a single
   representative plant does not satisfy it. Also record the `T-` fail-and-pass pairs named in that
   section as the availability resolver's own planted-violation proof.

   Where two cases read nearby text and one plant moves both, the plant is too coarse: narrow it until
   exactly one case flips, and record the narrowed mutation rather than the one from the table.

9. *(Repository process — `02-generate-implementation-plan-protocol.md` requires a sweep or pattern-completeness plan to name a residual verification strategy and produce its evidence before `ready-for-human-review`. It applies here because the* **Surfaces agree** *group is a pattern-completeness claim over a live file set that can grow between plan time and implementation time.)* **Re-run the residual verification** (VL-2 and VL-4) at the implementation head and record both
   outputs in the pull request, per **Residual verification strategy**.

10. *(Both — `02-generate-implementation-plan-protocol.md` Step 4 requires a smoke runbook for every plan, and here it is also the only evidence for the twenty-eight gate-level criteria, which no automated suite can observe.)* **Execute the smoke test runbook**
   `docs/testing/workflow/1495-step-7a-capability-based-reachability.smoke-test.md` end to end and
   record the assertion results in the pull request.

11. *(Repository process — `02-generate-implementation-plan-protocol.md` requires the plan to list the project docs the developer must update after implementation, and the developer to execute that list.)* **Update project docs** per the **Documentation Updates** section above.

12. *(Repository process, not spec-derived — `CLAUDE.md` requires feature, fix, and refactor pull requests merged into `develop` to add a release-note fragment under `changelog.d/`, and forbids editing `CHANGELOG.md` directly. It applies because this ships as a fix in a **released template**: downstream consumers learn that the gate now decides reachability from capability, and that the shipped default reviewer list changed, only from the release notes. Spec-only and plan-only pull requests are exempt, which is why this plan's own pull request carries no fragment; the implementation pull request is not exempt.)* **Add the changelog fragment** `changelog.d/1495.fixed.step-7a-capability-based-reachability.md`
    with exactly this body:

    ```markdown
    - **Step 7a decides reviewer reachability from capability, not runner identity** (#1495): the internal review gate used to consult a fixed table that called the Codex reviewer unreachable whenever a different runner was driving the gate, even on a machine where the Codex command was installed and about to be used successfully by the next gate in the same pipeline — and since the shipped configuration named Codex as the only internal reviewer, the gate found nothing to dispatch and blocked. The gate now probes each configured reviewer against the environment it is actually running in, under a fixed ten-second ceiling, and reports each one as Reachable, Unreachable with one of four named reasons and a remedy, or Excluded by override. The shipped default reviewer list changed so that whichever supported runner drives the gate, that runner's own reviewer is reachable by construction, and the Codex GitHub App review is supported as a hosted-service reviewer whose availability uses a bounded repository-activity proxy, with its limitations and dispatch-time failure handling documented.
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
