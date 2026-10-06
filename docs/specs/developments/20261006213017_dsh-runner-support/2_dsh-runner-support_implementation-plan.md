# First-class DSH Runner Support — Implementation Plan

**Spec**: [`1_dsh-runner-support_specs.md`](./1_dsh-runner-support_specs.md)
**Smoke test runbook**: [`docs/testing/workflow/1891-dsh-runner-support.smoke-test.md`](../../../testing/workflow/1891-dsh-runner-support.smoke-test.md)

---

## Summary

**Approach**: Extend the existing Step 7a local-runtime reviewer family with `dsh` — availability validation and `dsh --version` probe, Protocol 91 surfaces (supported values, draft-restriction Never, dispatch-map rows to shared reviewer skills), cross-runner headless invocation under the shipped DSH `read-only` permission preset, and operator docs (command matrices, new `integrations/dsh.md` with parent-orchestrated dispatch, model-config tier/pinning, failover row). Keep the shipped `review.on_draft.runner` list Claude-only; DSH remains local opt-in.

**Estimated complexity**: M

**Rationale**: Touch surface spans resolver + preflight + Protocol 91 + surface-consistency tests + several docs, but each edit follows an established Claude/Cursor/Codex pattern with no new gate, parser, or policy invention.

**Dependencies**: None — spec is merged on `develop`.

---

## Decisions (assert once)

| ID | Decision | Maps to |
| -- | -------- | ------- |
| D1 | Runner / driving-session kind value is the literal `dsh` (matches the local binary). | Spec decision 1; AC-1, AC-1a |
| D2 | Shipped `review.on_draft.runner` stays `[claude]`. Operators opt DSH in via `.ai-dev-workflow.local.yaml`. README prose `The shipped list is \`[claude]\`` is preserved for `test-step7a-surface-consistency.sh` D-9. | Spec decision 2; AC-11, BR-2, BR-3 |
| D3 | Cross-runner headless DSH review uses `DSH_PERMISSION_MODE=read-only dsh --profile headless "<prompt>"`. That env composition selects the shipped base-bundle `read-only` permission preset (`sandbox: read-only`) — not prompt-only instructions. Protocol 91’s cross-runner CLI paragraph and D-6 must name this exact command form beside the Claude / Cursor / Codex forms. | Spec decision 3; AC-6, BR-6 |
| D4 | Default DSH dispatch is parent-orchestrated. Document it as a section inside `docs/workflow/development-workflow/integrations/dsh.md`; do not add a separate dispatch-profile document. | Spec decision 4; AC-8, BR-7 |
| D5 | Dispatch-map rows for `dsh` route to the same shared workflow reviewer skills Codex uses (`workflow-spec-reviewer` / `workflow-plan-reviewer` / `workflow-code-reviewer` against `REVIEW.md`), because DSH has no in-repo per-role agent tree. | AC-5, BR-5, BR-8 |
| D6 | Binary probe uses `dsh --version` via the existing `probe_local` path (binary name equals entry; no `cursor`→`cursor-agent` alias needed). | AC-2, BR-1 |

---

## Verification Log

| Check | Command / query | Result |
| ----- | --------------- | ------ |
| Repo revision | `git rev-parse --short HEAD` | `bf8afa50` (branch base = `origin/develop`) |
| Spec present | `test -f docs/specs/developments/20261006213017_dsh-runner-support/1_dsh-runner-support_specs.md` | present |
| `integrations/dsh.md` absent | `test ! -f docs/workflow/development-workflow/integrations/dsh.md` | absent (new file) |
| Shipped runner list | `rg -n "The shipped list is" docs/workflow/development-workflow/README.md` | line 563: `The shipped list is \`[claude]\`` |
| Shared YAML runner list | `rg -n "^\s+- claude$" .ai-dev-workflow.yaml` under `on_draft.runner` | shipped list is Claude-only (D2) |
| Resolver runner-kind allow-list | `rg -n 'case "\$runner_kind"' scripts/development-workflow/resolve-reviewer-availability.sh` | line 38: `claude\|cursor\|codex\|unknown` only |
| Resolver local-runtime probe case | `rg -n 'claude\|cursor\|codex\)' scripts/development-workflow/resolve-reviewer-availability.sh` | line 423: triad only (add `dsh`) |
| Preflight `SUPPORTED_RUNNER` | `rg -n 'SUPPORTED_RUNNER' scripts/development-workflow/reviewer_preflight.py` | line 39: `claude`, `cursor`, `codex`, `coderabbit`, `codex-github` |
| Surface-consistency supported set | `rg -n "^supported =" scripts/development-workflow/tests/test-step7a-surface-consistency.sh` | line 22: triad + hosted pair (add `dsh`) |
| D-1 prose needle | Protocol 91 “Supported reviewer values are …” | names triad as local-runtime; must gain `dsh` |
| Draft-restriction table | Protocol 91 “Reviewer-to-draft-restriction mapping” | has `claude` / `codex` Never; **no** `dsh` row yet (add Never) |
| Dispatch map `codex` rows | `rg -c '^\| \`codex\`' docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` | 4 (3 branch-prefix rows + draft-restriction row) — add 3 `dsh` dispatch rows + 1 draft-restriction row |
| Cross-runner CLI forms (D-6) | Protocol 91 Reviewer dispatch map prose | `claude -p --output-format text`, `cursor-agent --print --output-format text`, `codex exec --sandbox read-only` — add D3 form |
| DSH CLI contract (D3 evidence) | `dsh --version`; `dsh --profile headless --help` | `0.2.0-rc.2`; headless one-shot profile prints answer to stdout |
| DSH `read-only` preset contract (D3) | `rg -n "read-only:|DSH_PERMISSION_MODE" /Users/lhpaul/Git/DevStack/deepseek-harness/packages/bundle/base/cordis.patch.yml` | base bundle ships `permission.presets.read-only` and wires `sandbox-policy.mode` / approval from `DSH_PERMISSION_MODE` |
| Sync-manifest coverage for new guide | `rg -n "path: docs/workflow/" sync-manifest.yaml` | `docs/workflow/` glob `**/*` already covers a new `integrations/dsh.md` |
| AGENTS / GEMINI matrices | `ls -la AGENTS.md CLAUDE.md GEMINI.md` | `CLAUDE.md` and `GEMINI.md` symlink to `AGENTS.md` — edit AGENTS once |
| Open PRs for #1891 | `gh pr list --search "1891" --state open` | `[]` |
| Design assets | issue body + `<dev-folder>/assets/` | none |
| Rule 5 consumer search (local-runtime allow-lists) | `rg -n "claude\|cursor\|codex|SUPPORTED_RUNNER|supported = \{'claude'" scripts/development-workflow/ docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md .ai-dev-workflow.yaml` (excl. specs/CHANGELOG) | consumers listed under Factual claim evidence |

---

## Factual claim evidence

**Rule 1 — D3 headless / permission-preset design**: Producer contract cited (not free-text sampling): DeepSeek Harness base bundle `packages/bundle/base/cordis.patch.yml` ships `@deepseek-ai/dsh-permission-presets` with a `read-only` preset (`sandbox: read-only`, `approval: ask`) and sets `sandbox-policy` / approval process fallbacks from `DSH_PERMISSION_MODE`. Local CLI evidence at plan time: `dsh --version` → `0.2.0-rc.2`; `dsh --profile headless --help` documents one-shot stdout answer. Design binds to that fixed preset name and env composition; if a future DSH release removes the preset or env wiring, implementation must update D3’s command form and docs rather than fall back to prompt-only read-only.

**Rule 5 — consumers of the local-runtime supported-value unit** (search at `bf8afa50`):

| Consumer | Path / site | Outcome after adding `dsh` |
| -------- | ----------- | -------------------------- |
| Availability resolver allow-list + probe case | `resolve-reviewer-availability.sh` lines 29, 38, 423 | Accept `--runner-kind dsh`; treat configured `dsh` as local-runtime (native when driver matches; else `probe_local` → `dsh --version`) |
| Reviewer preflight bucket list | `reviewer_preflight.py` `SUPPORTED_RUNNER` | `dsh` accepted in `on_draft.runner`; still rejected in GitHub buckets |
| Protocol 91 supported-values sentence | Step 7a “Determining which reviewers to run” | Prose lists `dsh` among local-runtime values |
| Protocol 91 draft-restriction + dispatch map + cross-runner CLI | Step 7a tables / paragraph | New Never row; three skill-dispatch rows; D3 command in cross-runner list |
| Surface-consistency D-1 / D-6 | `test-step7a-surface-consistency.sh` | Expand `supported` set; require D3 string in D-6 |
| Availability unit tests | `test-resolve-reviewer-availability.sh` | Add DSH probe / kind cases; extend local-entry enumerations that currently hard-code the triad |
| Manifest comments | `.ai-dev-workflow.yaml` `on_draft.runner` comment block | Document `dsh` as local-runtime value (list body stays `[claude]` per D2) |
| Preflight / availability tests that only fixture the triad | `test-resolve-reviewer-availability.sh` loops over `('claude','cursor','codex')` | Extend where the loop defines “all local-runtime kinds”; leave hosted-only cases unchanged |

**Rule 6 — scoped obligations**:

| Obligation | Scope | Discharge |
| ---------- | ----- | --------- |
| Do not change shipped default list | `.ai-dev-workflow.yaml` `review.on_draft.runner` body | Implementation Order step that edits comments only; D-9 / AC-11 verification |
| Preserve README shipped-list parse | Exact prose `The shipped list is \`[claude]\`` | No edit to that sentence (or equivalent rewording that preserves the parse) |
| No separate dispatch-profile doc | New files under `integrations/` | Only `dsh.md`; parent-orchestrated section inside it |
| Hosted-service values remain | Resolver / preflight / Protocol 91 supported sets | Add `dsh` without removing `coderabbit` / `codex-github` |

---

## Cross-Cutting Operational Assumption Check

### Applicable

| Assumption surface | Recorded value | Authoritative source | Verified at | Bounded cross-check scope | Result |
| --- | --- | --- | --- | --- | --- |
| Artifact / plan PR base branch | `develop` | Parent handoff + `git rev-parse origin/develop` = `bf8afa50635d0264ec32df7b4b752a9392797039` | 2026-10-06T21:51:34Z @ `bf8afa50` | Current invocation items `[1891]` only; `gh pr list --search "1891" --state open` → `[]` | `Verified` |
| Repository mode / plan ownership | `single_repo` (current repo owns plan) | `.ai-dev-workflow.yaml` (no `mode:` override; protocol default) | same | Item `[1891]` only | `Verified` |
| Shipped draft-runner default | `[claude]` | `.ai-dev-workflow.yaml` + README shipped-list prose (D-9 source) | same | Item `[1891]` only; no open PR changing that list for this item | `Verified` |
| Headless read-only mechanism | `DSH_PERMISSION_MODE=read-only` + shipped `read-only` permission preset | Spec decision 3 + DSH base-bundle contract cited in Verification Log | same | Item `[1891]` only | `Verified` |

---

## Layer-by-Layer Changes

### Database / Data Layer

Not applicable — workflow tooling only.

### Backend / API

Not applicable.

### Shared Packages / Libraries

Not applicable.

### Frontend / UI

Not applicable — no design assets.

### Infrastructure / Configuration / Scripts

- [ ] **`scripts/development-workflow/resolve-reviewer-availability.sh`** (AC-1, AC-1a, AC-2): Add `dsh` to `--runner-kind` help + allow-list (`claude|cursor|codex|dsh|unknown`) and to the local-runtime `case` arm beside `claude|cursor|codex`. Rely on existing `probe_local` (binary name = entry → `dsh --version`). Native-driving short-circuit (`entry == runner_kind`) applies unchanged.
- [ ] **`scripts/development-workflow/reviewer_preflight.py`** (AC-1): Add `"dsh"` to `SUPPORTED_RUNNER` only (not to `SUPPORTED_GITHUB`). Update the adjacent comment that currently says “three local-runtime driving-session values” so it stays accurate after the addition.
- [ ] **`.ai-dev-workflow.yaml`** (AC-4, AC-11 / D2): Extend the `on_draft.runner` comment block with `dsh — local-runtime reviewer.` Do **not** add `dsh` to the shipped list body.
- [ ] **`.ai-dev-workflow.local.example.yaml`** (operator discoverability): Optional comment or example note that `dsh` is a valid local-runtime runner value for opt-in; do not force `dsh` into the example’s active list if that would imply a new machine requirement — prefer a comment. Keep all listed values ⊆ expanded supported set (D-4).

### Workflow protocols & review surfaces

- [ ] **`docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`** (AC-3, AC-3a, AC-5, AC-6):
  - Driving-session kind prose: include `dsh` with `claude`, `cursor`, `codex`, `unknown`.
  - Supported reviewer values sentence: local-runtime set becomes `claude`, `cursor`, `codex`, `dsh`.
  - Draft-restriction mapping: add `| dsh | Never — … |` (same class as Claude/Codex).
  - Reviewer dispatch map: three rows per D5 (spec / plan / implementation prefixes → shared skills against `REVIEW.md`).
  - Cross-runner CLI paragraph: append D3’s `DSH_PERMISSION_MODE=read-only dsh --profile headless` form; keep “never add permission-bypass flags” and parent-owned fixes language.

### Operator documentation

- [ ] **`docs/workflow/development-workflow/integrations/dsh.md`** (**new**, AC-8, D4): Cover install (`dsh` on PATH), profiles (`web` / `headless`), provider routes, subagent model selection, headless mode (D3), and a **Parent-orchestrated dispatch** section (default contract; no separate dispatch-profile doc). Link `REVIEW.md`, Protocol 91 Step 7a, and shared skill names from D5.
- [ ] **`AGENTS.md`** (AC-7): Add a DSH column (or equivalent first-class cell) to the primary Commands By Stage matrix. `CLAUDE.md` / `GEMINI.md` are symlinks — do not duplicate.
- [ ] **`docs/workflow/development-workflow/README.md`** (AC-7, AC-11): Add DSH column to Commands By Stage; add `integrations/dsh.md` to the Integration Guides list. **Do not** alter the shipped-list sentence `The shipped list is \`[claude]\``.
- [ ] **`docs/workflow/development-workflow/agent-model-config.md`** (AC-9, BR-8): Add DSH runner notes — tier mapping + dispatch-time provider/model pinning (no in-repo per-role agent files).
- [ ] **`docs/workflow/development-workflow/provider-contingency-runner-failover.md`** (AC-10): Add a DSH row / mention under Failure mode 3 (symptoms + migrate-to-alternate entrypoint via shared skills / protocol path).
- [ ] **`docs/workflow/development-workflow/integrations/claude-code-action.md`** (consistency): Update the stale “only accepts `claude`, `cursor`, `codex`, and `coderabbit`” note if it still claims an incomplete runner set after this change — include `dsh` and keep hosted values accurate to current inventory (do not invent removals).

### Tests

See Testing Strategy.

### Sync-manifest / changelog

- [ ] **`sync-manifest.yaml`** (AC-13): Confirm `docs/workflow/` glob covers `integrations/dsh.md`. Add or adjust explicit entries only if implementation touches files outside existing globs (resolver / preflight / AGENTS / YAML already covered). Run `check-sync-manifest-coverage.py` before readiness if implementation changes synced test inputs.
- [ ] **`changelog.d/1891.added.dsh-runner-support.md`** (AC-14) — implementation PR only (not this plan PR). Literal body in Implementation Order.

### Classifier results (protocol 02)

| Classifier | Applies? | Rationale |
| ---------- | -------- | --------- |
| Parser-risk | No | Extends allow-lists / case arms; no new lint/parser/scanner module |
| Concurrent-event-source | No | No new concurrent listeners or shared mutable async state |
| Cross-cutting checklist | No | Does not add/rename a checklist category in REVIEW.md or planning protocols |

---

## Testing Strategy

**Test types**: Unit (shell/python workflow tests) + Smoke (manual runbook)

**Coverage intent**: Prove (1) `dsh` is a first-class local-runtime / driving-session kind, (2) probe reachable vs runtime-absent, (3) unknown values still `value-not-supported`, (4) hosted values unchanged, (5) shipped Claude-only default + README parse still pass surface-consistency, (6) D-1/D-6 text contracts include `dsh` and the D3 headless form. Volume stays proportional: extend existing suites rather than invent a DSH parser.

**Key scenarios** (indicative; coverage-equivalent substitutions allowed unless marked binding):

1. Configured `dsh` + fake/real `dsh --version` success → `reachable` (AC-1, AC-2).
2. Configured `dsh` + binary absent (hermetic PATH, not the machine PATH) → `runtime-absent` with the existing shared local-runtime remedy (“Install the reviewer's runtime … or remove … from … `.ai-dev-workflow.local.yaml`”) — AC-2’s “installing DSH” intent is satisfied by that generic install-or-remove pattern; do not invent a DSH-named remedy string (AC-2, BR-4).
3. `--runner-kind dsh` accepted; unknown kind still fails closed (AC-1a).
4. Unknown reviewer token still `value-not-supported`; `coderabbit` / `codex-github` still accepted (AC-1).
5. **Shipped Claude-only default (binding)** — Hermetic shipped `[claude]` config + absent Claude on PATH: driving with native `claude` still **proceeds** (`reachable` via entry == `runner_kind` short-circuit; T-33/T-44). Driving with a non-native kind such as `dsh` blocks `zero-reachable` with configured local entries reporting `runtime-absent`; the resolver does **not** substitute another local runtime when the configured list is present and non-empty. Preserves AC-11 / AC-12 without changing the native short-circuit.
6. **Absent/empty configured list fallback (separate)** — When the effective runner list is absent or empty (local override `[]` / T-45-style fallback), driving-session fallback may proceed under each kind including `dsh`; extend availability tests for that path only — not under the shipped `[claude]` hermetic fixture.
7. `test-step7a-surface-consistency.sh` green after D-1/D-6 expectation updates — expand the `supported` set **and** the D-1 `contains(...)` prose needle so Protocol 91’s “Supported reviewer values are …” sentence includes `` `dsh` `` (AC-3, AC-6, AC-12).
8. Preflight accepts `dsh` in `on_draft.runner` and rejects it in GitHub buckets; update the “three local-runtime” comment beside `SUPPORTED_RUNNER` when the set grows (AC-1).

**Files to extend** (indicative):

- `scripts/development-workflow/tests/test-resolve-reviewer-availability.sh`
- `scripts/development-workflow/tests/test-step7a-surface-consistency.sh` — **Binding enumeration** for D-1 local-runtime token set after change: `claude`, `cursor`, `codex`, `dsh` (plus hosted `coderabbit`, `codex-github`). D-6 must require the D3 command substring.
- `scripts/development-workflow/tests/test-reviewer-preflight.sh` (only if existing assertions hard-code the pre-DSH `SUPPORTED_RUNNER` membership)

**Smoke test runbook**: `docs/testing/workflow/1891-dsh-runner-support.smoke-test.md`

**Regression suite**: N/A as a separate app suite — workflow shell tests above are the automated regression surface.

**Gate B self-check**: Scaffolding extends existing tests; no custom parser for a docs-only deliverable. Proportionate.

**Residual verification (before implementation `ready-for-human-review`)**: `test-step7a-surface-consistency.sh` pass + availability/preflight tests pass + smoke checklist complete + sync-manifest coverage clean for touched paths.

---

## Seed Data

None — no database. Smoke fixtures are ephemeral local YAML overrides and PATH stubs, restored by the runbook trap (same pattern as #1495 smoke).

---

## Documentation Updates

Listed for the **implementation** agent (not performed on this plan branch except the plan/runbook themselves):

- [ ] `docs/workflow/development-workflow/integrations/dsh.md` — create (AC-8)
- [ ] `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` — Step 7a surfaces (AC-3, AC-3a, AC-5, AC-6)
- [ ] `docs/workflow/development-workflow/README.md` — matrix column + integrations list; preserve shipped-list prose (AC-7, AC-11)
- [ ] `docs/workflow/development-workflow/agent-model-config.md` — DSH tier + pinning (AC-9)
- [ ] `docs/workflow/development-workflow/provider-contingency-runner-failover.md` — DSH failover (AC-10)
- [ ] `docs/workflow/development-workflow/integrations/claude-code-action.md` — supported-runner note if stale
- [ ] `AGENTS.md` — Commands By Stage DSH column (AC-7); symlinked `CLAUDE.md` / `GEMINI.md` follow
- [ ] `.ai-dev-workflow.yaml` / `.ai-dev-workflow.local.example.yaml` — comments / example opt-in notes (AC-4)
- [ ] `sync-manifest.yaml` — only if a touched path falls outside existing entries (AC-13)
- [ ] `changelog.d/1891.added.dsh-runner-support.md` — on implementation PR (AC-14)

Project domain docs under `docs/project/` / `docs/best-practices/`: **None** — this feature does not change product domain or stack conventions.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| ---- | ---------- | ------ | ---------- |
| D-1/D-6 surface-consistency plants fail if prose wording drifts | Med | Med | Edit Protocol 91 and the test expectations in the same commit; run `test-step7a-surface-consistency.sh` before push |
| DSH env/preset wiring changes across CLI versions | Low | Med | D3 cites base-bundle contract; integration guide notes minimum verified CLI (`0.2.0-rc.2` at plan time) and requires re-verify on major DSH bumps |
| Accidentally shipping `dsh` in default runner list | Low | High | D2 + D-9 parse; smoke step asserts shared YAML list remains `[claude]` |
| Over-scoping Cursor draft-restriction gap | Low | Low | Out of scope — do not add a `cursor` draft-restriction row unless required by a failing consistency check (none today) |

---

## Code Samples

Illustrative — adapt during implementation.

```bash
# Illustrative — cross-runner headless DSH review (D3)
DSH_PERMISSION_MODE=read-only dsh --profile headless \
  "Read-only review against REVIEW.md for <stage>. Emit exactly one line: VERDICT: APPROVED or VERDICT: NEEDS REVISION."
```

```yaml
# Illustrative — local opt-in (D2); do not commit this as the shipped default
review:
  on_draft:
    runner:
      - claude
      - dsh
```

---

## Reversal / rollback

If first-class DSH support must be undone after resolver, Protocol 91, YAML comment, or operator-doc changes ship:

1. **Code/docs revert** — Revert the implementation merge (or a single revert commit) that added `dsh` to resolver/preflight allow-lists, Protocol 91 Step 7a surfaces, integration guide, and command matrices. Shipped `review.on_draft.runner` body must remain `[claude]` throughout.
2. **Local overrides** — Operators who opted in via `.ai-dev-workflow.local.yaml` (`runner: […, dsh]`) must remove `dsh` manually after revert. Once allow-lists no longer recognize `dsh`, a lingering token is `value-not-supported` and Step 7a hard-fails until the override is corrected — document this in the integration guide removal note during revert.
3. **Tests** — Restore pre-DSH expectations in availability, surface-consistency, and preflight suites as part of the same revert; do not leave tests asserting `dsh` reachable while production code rejects it.

Reversal is unavailable only if downstream repos already depend on `dsh` in committed (non-local) workflow YAML; that case requires a human release note and coordinated config cleanup, not a silent partial revert.

---

## Implementation Order

1. **Resolver + preflight allow-lists** — Update `resolve-reviewer-availability.sh` and `reviewer_preflight.py` per Layer-by-Layer (D1, D6). Verify with a hermetic PATH run: configured `dsh` absent → `runtime-absent`; with a stub `dsh --version` exiting 0 → `reachable`; `--runner-kind dsh` accepted.
2. **Protocol 91 Step 7a surfaces** — Supported values, driving-session kind, draft-restriction Never, three dispatch rows (D5), cross-runner CLI D3 form.
3. **YAML comment blocks** — `.ai-dev-workflow.yaml` (+ example file notes). Confirm shipped list body still `[claude]` (D2).
4. **Operator docs** — Create `integrations/dsh.md` (D4 section included); update AGENTS.md, workflow README (matrix + integrations list; preserve shipped-list prose), `agent-model-config.md`, `provider-contingency-runner-failover.md`, and the claude-code-action note if needed.
5. **Tests** — Extend availability, surface-consistency (D-1/D-6), and preflight tests per Testing Strategy. Run the three suites; fix until green.
6. **Sync-manifest check** — Confirm coverage; adjust only if required (AC-13).
7. **Smoke runbook execution** — Walk `docs/testing/workflow/1891-dsh-runner-support.smoke-test.md` on the implementation branch.
8. **Documentation Updates** — Already inlined in steps 2–4; re-read Documentation Updates checklist for omissions.
9. **Changelog fragment** (implementation PR only):

   ```markdown
   ### Added

   - **First-class DSH runner support** (#1891): Add `dsh` as a local-runtime draft reviewer and driving-session kind, with availability probing, Protocol 91 dispatch/draft-restriction surfaces, headless read-only review guidance, and operator docs (integration guide, command matrices, model-config, failover).
   ```

---

## Reused Step 7a contracts (plan pointer)

This plan does **not** define a new multi-input decision gate. Stateful availability, aggregate policy, draft-restriction, and commit-bound progression for `dsh` are specified in the approved spec section **Reused Step 7a stateful contracts (DSH extension)** and are implemented by extending Protocol 91 / resolver behavior above — do not fork a parallel DSH-only lifecycle.
