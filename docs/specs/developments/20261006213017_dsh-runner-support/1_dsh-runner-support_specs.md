# First-class DSH Runner Support — Spec

---

## Overview

The staged AI development workflow treats Claude Code, Cursor, and Codex as first-class local runners for command matrices, the internal draft review gate, reviewer dispatch, model-tier guidance, and provider failover. DeepSeek Harness (DSH) already consumes the framework’s shared instruction and skill surfaces and is becoming the primary interactive runner for this template, but today it is only reachable through the generic “any other tool” protocol-following path: no draft-runner value, no availability probe, no dispatch-map rows, no integration guide, and no model-tier or failover row.

This feature elevates DSH to first-class local-runtime parity with the three existing runners. Operators can opt DSH into the draft-stage review gate via a local override, run cross-runner headless reviews under a dedicated read-only permission preset, and follow published setup and dispatch guidance without inventing contracts mid-run. The shipped draft-runner default remains Claude-only so repositories that do not install DSH keep today’s behavior; availability degradation stays warn-and-continue.

---

## Confirmed Product Decisions

Recorded at alignment (issue #1891 open design decisions; human-confirmed in the bounded prelude):

1. **Runner value name**: `dsh` — matches the local binary name.
2. **Shipped draft-runner default**: keep the shipped list as Claude only (`[claude]`). DSH is a local opt-in through the repository-local workflow override file. The warn availability policy already degrades gracefully when a configured runner is absent. The README prose sentence that states the shipped list is `` `[claude]` `` must remain parseable by the Step 7a surface-consistency test.
3. **Read-only enforcement for cross-runner headless DSH review**: a dedicated read-only permission preset composed into the headless invocation (analogous to Codex’s read-only sandbox), not prompt-level instructions alone.
4. **DSH dispatch contract**: parent-orchestrated by default. Document that contract as a section inside the new DSH integration guide; do not create a separate dispatch-profile document.

---

## Brief Objective List

Derived from issue #1891 Outcome (and the confirmed open design decisions above):

- **BO-1**: DSH is a supported draft-stage local-runtime reviewer value (`dsh`), with argument validation and a local binary availability probe (`dsh --version` style), on par with Claude / Cursor / Codex.
- **BO-2**: Protocol 91 Step 7a surfaces (supported values, remedy tables, draft-restriction mapping) and the workflow YAML comment blocks name `dsh` alongside the existing runners.
- **BO-3**: The reviewer dispatch map includes DSH rows per branch prefix that dispatch the shared workflow reviewer skills (spec / plan / code) against the canonical review contract.
- **BO-4**: Cross-runner headless CLI review for DSH is documented: one-shot headless profile invocation that prints the final answer and exits success/failure, with read-only enforcement via a dedicated permission preset composed into the invocation (not prompt-only).
- **BO-5**: Operator-facing docs add a DSH column to the primary command matrices, a new DSH integration guide (install, profiles, provider routes, subagent model selection, headless mode, and the parent-orchestrated dispatch section), DSH tier mapping and dispatch-time pinning guidance in the agent model-config document, and a DSH row in the provider-contingency runner-failover guide.
- **BO-6**: Consistency and availability tests cover the expanded supported runner set and probe behavior; the README shipped-list prose remains parseable as Claude-only; sync-manifest entries cover every touched framework file; a changelog fragment records the feature for the eventual implementation PR path.
- **BO-7**: Shipped default draft-runner list stays Claude-only; DSH is local opt-in.

---

## Use Cases

### Use Case 1: Opt DSH into the draft-stage internal review gate

**Actor**: Repository operator configuring the local workflow for a machine that has DSH installed.
**Preconditions**: The repository ships the default Claude-only draft-runner list. DSH is installed locally and responds to a version probe.

**Steps**:

1. The operator adds `dsh` to the draft-stage runner list in the repository-local workflow override (not by changing the shipped template default).
2. A work-item run reaches the internal draft review gate (Step 7a).
3. The availability resolver accepts `dsh` as a supported runner value and probes the local DSH binary.
4. When the probe succeeds, the gate treats DSH as an available local-runtime reviewer for that draft stage.

**Postconditions**: DSH participates in the draft-stage internal review path for that machine/override without changing the shipped default for other clones.

**Information shown**:

- Availability classification for the DSH draft-runner entry (reachable / absent / unsupported, using the same categories the gate already exposes for Claude, Cursor, and Codex).
- When unavailable under the warn policy, a clear remedy pointing at installing DSH or removing it from the local override.

**Actions available**:

- Keep DSH in the local override and proceed when the probe succeeds.
- Remove DSH from the local override if the machine should not use it.
- Leave the shipped default unchanged for consumers who never install DSH.

**Considerations**:

- An unsupported or misspelled value must fail validation the same way other runner values do — it must not be silently dropped.
- Under the shipped warn availability policy, a configured-but-absent DSH binary degrades gracefully rather than hard-blocking the whole item solely for that absence (existing policy behavior; this feature does not invent a new policy).

---

### Use Case 2: Dispatch a stage review through DSH

**Actor**: Work Item Runner (or parent-orchestrated driving session) performing an internal draft review.
**Preconditions**: DSH is configured and available as a draft-stage runner. The pull request branch prefix identifies the review stage (spec, plan, or implementation).

**Steps**:

1. The run consults the reviewer dispatch map for the active branch prefix and the DSH runner.
2. The map routes the review to the corresponding shared workflow reviewer skill (spec, plan, or code) from the shared skills tree.
3. The review is evaluated against the canonical review contract (`REVIEW.md`).
4. The gate records the verdict for the commit under review using the same Step 7a outcome rules as other runners.

**Postconditions**: A DSH-backed review produces a stage-appropriate verdict against the same contract other first-class runners use; DSH does not invent a parallel review standard.

**Information shown**:

- Which reviewer skill was selected for the branch prefix.
- The review verdict bound to the reviewed commit.

**Actions available**:

- Fix findings and re-run the gate on the new commit when the verdict requires it.
- Proceed when the gate approves for that commit.

**Considerations**:

- DSH reuses the shared skill surface Codex already uses; it does not require a separate in-repo per-role agent file tree for dispatch (DSH has no Claude-/Cursor-style per-role agent files in-repo).
- Dispatch under DSH is parent-orchestrated by default: the driving session absorbs item orchestration and hands stage review work to the reviewer skill rather than relying on a separate two-hop native handoff profile document.

---

### Use Case 3: Run a cross-runner headless DSH review

**Actor**: Operator or orchestrating agent invoking a one-shot headless review from another runner or automation context.
**Preconditions**: DSH is installed. The operator needs a non-interactive review equivalent to Claude print mode, Cursor agent print mode, or Codex read-only exec.

**Steps**:

1. The operator (or automation) invokes DSH in its headless profile with the review prompt.
2. The invocation composes a dedicated read-only permission preset so the review cannot mutate the working tree or open mutating side channels — enforcement is not limited to prompt wording.
3. DSH prints the final answer and exits with success or failure.

**Postconditions**: The caller receives a one-shot review result suitable for cross-runner supervision, under read-only enforcement comparable in intent to Codex’s read-only sandbox.

**Information shown**:

- The printed final review answer.
- Process exit success/failure for automation.

**Actions available**:

- Parse or display the printed answer.
- Treat a non-zero exit as review failure for the calling loop.

**Considerations**:

- Prompt-only “please do not write files” instructions are not sufficient for this feature’s read-only story.
- Exact flag spelling and preset composition land in the implementation plan; the product requirement is the composed read-only preset plus headless one-shot behavior.

---

### Use Case 4: Discover and operate DSH from published docs alone

**Actor**: Operator adopting DSH as their interactive runner for this template.
**Preconditions**: The operator can install the DSH binary and open the repository docs.

**Steps**:

1. The operator finds DSH in the primary command matrices next to Claude, Cursor, and Codex.
2. The operator opens the DSH integration guide for install, profiles, provider routes, subagent model selection, headless mode, and the parent-orchestrated dispatch contract.
3. The operator applies model-tier mapping and dispatch-time pinning guidance from the agent model-config document (per-agent provider/model overrides at dispatch time, because DSH has no in-repo per-role agent files).
4. If the primary provider path fails, the operator follows the DSH row in the provider-contingency runner-failover guide.

**Postconditions**: The operator can configure, dispatch, and fail over DSH using published documentation without inventing contracts.

**Information shown**:

- Matrix entry points for DSH-equivalent commands/skills.
- Setup and dispatch guidance in the integration guide.
- Tier-to-provider mapping and failover steps.

**Actions available**:

- Install and configure DSH locally.
- Opt into draft-stage review via local override.
- Switch to an alternate runner using the contingency guide when DSH cannot run.

---

## Business Rules

- **BR-1 First-class parity**: Wherever the framework enumerates supported local-runtime draft reviewers as Claude, Cursor, and Codex, DSH (`dsh`) is included as a fourth supported value with the same validation and probe pattern family.
- **BR-2 Shipped default unchanged**: The template-shipped draft-stage runner list remains Claude-only. Enabling DSH for Step 7a is a local override concern, not a change to the shipped default.
- **BR-3 README shipped-list parse contract**: Operator-facing README prose that states the shipped list is `` `[claude]` `` must keep a form the Step 7a surface-consistency test can parse; wording that breaks that parse is a regression even if humans still understand it.
- **BR-4 Warn degradation**: With the shipped warn availability policy, a locally configured DSH that fails its binary probe is reported with a remedy and does not invent a harder failure mode than other local runners under the same policy.
- **BR-5 Shared review contract**: DSH-dispatched reviews use the shared workflow reviewer skills and `REVIEW.md`; DSH must not define a divergent review standard for the same stage.
- **BR-6 Read-only headless reviews**: Cross-runner headless DSH review must compose a dedicated read-only permission preset into the invocation. Prompt-level read-only guidance alone does not satisfy this rule.
- **BR-7 Parent-orchestrated dispatch default**: DSH’s documented default dispatch arrangement is parent-orchestrated. That contract lives as a section of the DSH integration guide; a separate dispatch-profile document is out of scope for this feature.
- **BR-8 No in-repo per-role agent files required**: Model-tier and pinning guidance for DSH must work without Claude-/Cursor-style per-role agent files; dispatch-time provider/model overrides are the supported pinning path.
- **BR-9 Template plumbing**: Every framework file this feature changes is reflected in the sync manifest, and the implementation path includes a changelog fragment (spec PRs remain changelog-exempt; the fragment belongs to the later implementation PR).

---

## Statuses / Enum Values

Draft-stage local-runtime reviewer values relevant to this feature:

| Code value | Display label | Description |
| ---------- | ------------- | ----------- |
| `claude` | Claude Code | Existing first-class local runner (shipped default). |
| `cursor` | Cursor | Existing first-class local runner. |
| `codex` | Codex | Existing first-class local runner. |
| `dsh` | DeepSeek Harness (DSH) | New first-class local runner; local opt-in for draft-stage review. |

**Valid transitions**: not applicable — these are configuration enumerations, not lifecycle states.

Availability outcomes for a configured draft runner continue to use the existing gate classifications (reachable / runtime-absent / value-not-supported and related remedy rows). This feature extends those tables to cover `dsh`; it does not redefine the classification vocabulary.

---

## Operational Visibility

- **Logs / gate output**: When `dsh` is configured, Step 7a availability output names the runner kind, probe result, and remedy text using the same key-value style as other local runners.
- **Docs**: Operators learn configuration and failover from the DSH integration guide, command matrices, model-config tier mapping, and provider-contingency row.
- **Notifications**: none beyond existing PR/review gate comments.
- **Audit trail**: Review verdicts remain bound to the reviewed commit via the existing Step 7a / readiness machinery; this feature does not add a separate audit channel.

---

## Acceptance Criteria

- [ ] **AC-1**: Configuring `dsh` as a draft-stage local-runtime reviewer is accepted by the availability resolver; an unknown runner value is still rejected.
- [ ] **AC-2**: When DSH is installed, the availability probe that checks the local DSH binary reports the runner reachable; when the binary is missing, the probe reports runtime-absent (or the equivalent existing absent classification) with a remedy that mentions installing DSH or removing it from the local override.
- [ ] **AC-3**: Protocol 91 Step 7a supported-values, remedy, and draft-restriction surfaces name `dsh` alongside Claude, Cursor, and Codex.
- [ ] **AC-4**: Workflow manifest comment blocks that enumerate supported draft runners include `dsh`.
- [ ] **AC-5**: The reviewer dispatch map includes DSH rows for spec, plan, and implementation branch prefixes that dispatch the shared workflow reviewer skills against `REVIEW.md`.
- [ ] **AC-6**: Published cross-runner headless guidance documents a DSH headless one-shot invocation that prints the final answer and exits success/failure, and states that read-only enforcement uses a dedicated permission preset composed into that invocation (not prompt-only).
- [ ] **AC-7**: The primary AGENTS.md and development-workflow README command matrices include a DSH column (or equivalent first-class cell) for the staged workflow commands.
- [ ] **AC-8**: A new DSH integration guide exists under the workflow integrations docs, covering install, profiles, provider routes, subagent model selection, headless mode, and a parent-orchestrated dispatch section (no separate dispatch-profile doc).
- [ ] **AC-9**: The agent model-config document includes DSH tier mapping and dispatch-time pinning guidance appropriate for a runner without in-repo per-role agent files.
- [ ] **AC-10**: The provider-contingency runner-failover guide includes a DSH row.
- [ ] **AC-11**: The shipped draft-runner default remains Claude-only, and the README prose stating that the shipped list is `` `[claude]` `` still satisfies the Step 7a surface-consistency parse.
- [ ] **AC-12**: Consistency and availability tests cover the expanded supported set and DSH probe cases; they still pass for the Claude-only shipped default.
- [ ] **AC-13**: Sync-manifest entries cover every framework file this feature changes.
- [ ] **AC-14**: The implementation delivers a changelog fragment under `changelog.d/` describing first-class DSH runner support (not on the spec PR).

---

## Out of Scope (MVP)

- Changing the shipped default draft-runner list to include DSH (local opt-in only) — **Deferral Note** for BO-7 alternative rejected at alignment.
- A separate DSH dispatch-profile document analogous to Cursor’s dispatch-profiles guide — dispatch guidance is a section of the DSH integration guide only (**BO / decision 4**).
- Prompt-only read-only enforcement for headless review as the sole control (**decision 3** rejects this).
- Shipping in-repo per-role DSH agent files mirroring `.claude/agents/` or `.cursor/agents/`.
- Making DSH a GitHub-hosted review platform under `review.on_draft.github` / `review.on_ready.github` (this feature is local-runtime only).
- Changing the warn availability policy itself, or inventing a DSH-specific harder failure mode.
- Packaging or distributing the DSH binary inside this template repository.
- Provider-specific commercial setup beyond documenting how routes and dispatch-time pins are applied (concrete vendor credentials stay outside the vault/repo).
- Implementation-plan-level flag spelling, script diffs, and exact test assertions (belong in the plan / implementation stages).

### Deferral Notes

| Deferred objective / alternative | Rationale | Human confirmation |
| -------------------------------- | --------- | ------------------ |
| Ship `[dsh]` (or `[claude, dsh]`) as the template default draft-runner list | Confirmed decision: keep `[claude]`; DSH is local opt-in so clones without DSH keep current behavior | Confirmed in prelude — no further confirmation requested |
| Separate `dsh-dispatch-profiles.md` (or similar) document | Confirmed decision: parent-orchestrated default is documented inside `integrations/dsh.md` | Confirmed in prelude — no further confirmation requested |
| Prompt-only read-only headless reviews | Confirmed decision: require a dedicated read-only permission preset composed into the headless invocation | Confirmed in prelude — no further confirmation requested |

---

## Coverage Matrix

| Brief objective | Mapped to | Notes |
| --------------- | --------- | ----- |
| BO-1 Supported `dsh` value + binary probe | AC-1, AC-2, BR-1 | |
| BO-2 Protocol 91 Step 7a + YAML comment blocks | AC-3, AC-4 | |
| BO-3 Reviewer dispatch map rows for DSH | AC-5, BR-5, UC-2 | |
| BO-4 Headless CLI review + read-only preset | AC-6, BR-6, UC-3 | |
| BO-5 Docs matrices, integration guide, model-config, failover | AC-7, AC-8, AC-9, AC-10, UC-4, BR-7, BR-8 | |
| BO-6 Tests, sync-manifest, changelog fragment | AC-12, AC-13, AC-14, BR-9 | Changelog fragment is implementation-path; spec PR remains changelog-exempt |
| BO-7 Shipped default stays Claude-only; DSH local opt-in | AC-11, BR-2, BR-3, BR-4, UC-1; Out of Scope + Deferral Notes | |

---

## Complex workflow decision-gate matrix

Not applicable — this feature extends an existing supported-runner enumeration and documentation/dispatch surfaces; it does not add or modify a multi-input workflow decision gate with new outcome classes, next-action branches, or mirrored gate status labels beyond naming `dsh` in the existing Step 7a tables.
