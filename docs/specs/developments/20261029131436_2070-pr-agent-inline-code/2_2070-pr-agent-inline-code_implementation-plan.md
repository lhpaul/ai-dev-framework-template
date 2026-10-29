# PR-Agent Classifiable Inline Code — Implementation Plan

**Spec**: [Approved spec](1_2070-pr-agent-inline-code_specs.md)
**Smoke test runbook**: [Synthetic publication regression](../../../testing/workflow/2070-pr-agent-inline-code.smoke-test.md)

## Summary

**Approach**: Normalize supported inline-code literals in structured finding text before the existing producer renderer embeds that text into its HTML card. Reuse the runtime-hook boundary, preserving the consumer parser and publication checks. The decisions below define the scope; later sections reference those decisions rather than introducing alternate paths.

**Estimated complexity**: M — source-text scanning, pinned renderer integration, and composed publication regressions need coordinated verification.

**Dependencies**: Spec PR #2071 was squash-merged to develop as `4eb013cffc89bc945d3a4a2c7c36a504c6571b37`. No sibling item is a prerequisite; #2064 and PR #2069 remain outside this invocation.

**Template fit**: Pass — this changes shipped workflow tooling and is independent of downstream application stacks.

## Verification Log

Repository evidence below was gathered at `4eb013cffc89bc945d3a4a2c7c36a504c6571b37`, 2026-10-29 UTC. Commands run from the repository root unless stated otherwise. V identifiers are the canonical evidence references for later sections.

| ID | Command / query | Observed result and scope |
| --- | --- | --- |
| V1 | `git rev-parse HEAD`; `gh pr view 2071 --json state,mergeCommit,baseRefName` | Recorded revision above; MERGED into develop. |
| V2 | `rg -n 'def install_hooks|def fit_review|def bind_review_record|def publish_review_record|def mask_review_code' scripts/development-workflow/pr-agent-runtime.py` | Existing runtime boundaries at lines 545, 438, 498, 531 and 73 respectively. |
| V3 | `rg -n 'fit_review\(|bind_review_record\(|publish_review_record\(' --glob '*.py' --glob '*.sh' scripts .github` | Runtime limiter and bound-publication fitting; fresh, edit and persistent publication consumers; fitting unit-test calls in `test_pr_agent_runtime.py`. These are the composed paths in the consumer table below. |
| V4 | `rg -n 'mask_review_code|def visible_review|def structurally_valid|def focus_labels' scripts/development-workflow/apply-readiness-labels.sh`; `rg -n 'def test_publication_consumers|def test_real_renderer_reduction|def test_incompatible_hook_before_install|def tearDownClass' scripts/development-workflow/tests/test_pr_agent_runtime.py` | Consumer imports the runtime masking guard, validates HTML before classifying fields; existing image tests expose publication, renderer, compatibility and hook teardown boundaries. |
| V5 | `python3 scripts/development-workflow/pr-agent-runtime.py --image`; `docker image inspect pragent/pr-agent@sha256:31b9aac6ab067bada9a0c1b001d30ebc500ea4487e00a93c18c59b9ef5fa66db --format '{{.Id}}'` | Launcher and available local image agree on the digest. This image is the external source snapshot for V6–V8, not a mutable upstream branch. |
| V6 | In V5 image, with `--network none --entrypoint python`: `import inspect; import pr_agent.algo.utils as u; print(inspect.signature(u.convert_to_markdown_v2)); print(inspect.getsource(u.convert_to_markdown_v2))` | Parameters are `output_data, gfm_supported, incremental_review, git_provider, files`. GFM finding cards interpolate structured `review.key_issues_to_review[*].issue_content` into HTML; this is D1's source boundary. |
| V7 | In V5 image: `from pathlib import Path; print('\n'.join(str(p)+':'+str(n)+':'+line.strip() for p in Path('/app/pr_agent').rglob('*.py') for n,line in enumerate(p.read_text().splitlines(),1) if 'convert_to_markdown_v2' in line))` | Renderer definition: `/app/pr_agent/algo/utils.py:116`; reviewer import alias: `/app/pr_agent/tools/pr_reviewer.py:59`; normal reviewer call: line 1184. No other producer references found in the searched package. |
| V8 | In V5 image: `import inspect; import pr_agent.tools.pr_reviewer as r; print(inspect.getsource(r))` | Reviewer renders before appending review state. Changing a copied rendering input at D1 need not rewrite the original finding-state data. |
| V9 | `rg -n 'pr-agent-runtime|# covers:|--image-smoke' scripts/development-workflow/tests/test-pr-agent-runtime.sh sync-manifest.yaml .github/workflows/pr-agent.yml`; `rg -n 'Self-declaration|Naming convention' scripts/development-workflow/select-test-suites.sh` | Runtime already ships via sync manifest and is invoked from the trusted PR base. Suite selection discovers test shell wrappers through `# covers:` headers; no workflow edit is needed for the new suite. |
| V10 | `rg -n '^HTML_INLINE_REVIEWS|^PR_1986_INLINE_REVIEW|^# Complete producer|^# Captured read-only' scripts/development-workflow/tests/test_pr_agent_runtime.py` | Archived producer-output sampling locators for the Rule 1 record below. These historical records are inspection evidence, not inputs for new regression tests. |

### Plan-time synthetic feasibility evidence

Using V5's actual `convert_to_markdown_v2`, a fabricated review with `security_concerns=No` and a Possible Issue finding containing the reported expression was rendered, then passed to the unchanged host classifier entrypoint `bash scripts/development-workflow/apply-readiness-labels.sh --classify-pr-agent`. Original single-backtick expression: `escalate`; the same expression as escaped HTML code: `clean`; ordinary single-backtick `helper()` control: `clean`. `HTMLParser(convert_charrefs=True)` extracted the HTML code's text equal to the original expression. This experiment used a read-only repository mount and `--network none`; it is feasibility evidence, not a substitute for T2's publication/readback test.

Reproduce with an in-memory dictionary whose finding text is the E1 input below, call the renderer once with the original text and once with `<code>` + `html.escape(expression)` + `</code>`, and feed each entire generated review to the stated classifier. No real review payload is needed.

## Factual Claim Evidence

### Rule 1: external output sampling and tolerance

**Producer/population/window**: PR-Agent free-text findings in the archived real review comments captured in the repository during October 14–16, 2026; inspected October 29. This is an open, heterogeneous population, not a fixed output set or a complete historical census.

**Sample**: Three archived comment occurrences examined, yielding three relevant inline-text shapes:

| Occurrence locator at the recorded repository revision | Relevant captured text / shape |
| --- | --- |
| `scripts/development-workflow/tests/test_pr_agent_runtime.py`, `HTML_INLINE_REVIEWS['1966']`, first finding summary | `--release-head`, `$child_binding`, `$SESSION_CHILD`: ordinary shell identifiers and arguments in inline code. |
| Same file, `HTML_INLINE_REVIEWS['1974']`, first finding summary | `scripts/*release*.sh`, `.github/workflows/*release*`: path/glob expressions in inline code. |
| Same file, `PR_1986_INLINE_REVIEW`; source comment identifies issuecomment 6217136440 | `source.startswith("<!--", index)`: a mixed expression containing HTML-comment syntax. |

Reproduce membership and excerpts by parsing that versioned Python file with `ast.parse`, selecting assignments named `HTML_INLINE_REVIEWS` and `PR_1986_INLINE_REVIEW`, and applying `ast.literal_eval`; select dictionary keys `1966` and `1974` and the named standalone constant. This inspects committed source literals, without running historical-payload tests or querying any sibling PR.

**Saturation**: Not established; the reported closing-tag expression in issue #2070 is an additional known input class. **Adequacy**: The sample shows plain and markup-looking code embedded in finding prose, while V6 establishes the structured insertion boundary. D1–D3 rely on source delimiters and typed finding placement, not on a vocabulary of observed phrases, tag names or verdicts. Fenced/malformed spans and unsupported producer layouts are explicitly outside normalization; existing fail-closed handling governs them. Sampling does not claim coverage of every generative output, security section, or historical layout. New tests fabricate representatives for each relevant class.

### Scoped obligations

Every D1–D4 obligation applies to newly generated review data on the pinned renderer path, and is discharged at the named T tests and consumer sites. The unchanged consumer guard remains authoritative for already composed raw comments, including ambiguous negatives. Unsupported hook identity/signature applies at `install_hooks` before any patch is installed; T4 discharges it. Current-head/provenance obligations apply at bound publication before create and during independent readback; T2/T3 discharge them. These are not claims that a code literal can retroactively make malformed raw HTML trustworthy.

## Cross-Cutting Operational Assumption Check

| Assumption surface | Recorded value | Authoritative source | Verified at | Bounded cross-check scope | Result |
| --- | --- | --- | --- | --- | --- |
| Artifact ownership and base | Current single repository, develop | `.ai-dev-workflow.yaml` mode default; V1; Luis's invocation | 2026-10-29 UTC, recorded revision | Current invocation `[2070]`; merged spec #2071 on this surface. No other item is being advanced or mutated. | Verified |
| Trusted runtime and producer identity | V5 image, with launcher executed from the PR base | V5–V9; `.github/workflows/pr-agent.yml` and PR-Agent integration doc | Same evidence snapshot | Current item and its runtime surface; no provider, image, model or workflow configuration change proposed. Separate-session #2064/#2069 are excluded, not assumed compatible or consumed as dependencies. | Verified |

Before implementation edits, recheck these sources against the then-approved base and inspect bounded same-surface drift. Record `Still valid` to continue; changed, conflicting or unverifiable source means `Stale or conflicting`, returned to the runner before edits. No repository-wide open-PR scan is required.

## Design Decisions and Layer Changes

### D1: source boundary and representation — AC1, AC2, AC4

Add a pure normalization helper in the existing runtime module. In GFM rendering only, operate on string `issue_content` fields of dictionary findings under `review.key_issues_to_review`. Use copied rendering data; do not mutate caller input, finding-state objects, issue headers, severity labels, paths, links, security/compliance sections, or resolved history. Non-GFM data and unrecognized/malformed field shapes retain the producer's existing behavior.

For supported single-backtick code spans containing a literal closing-tag-like sequence, replace the complete Markdown code span with an HTML `<code>` element whose entire original payload is HTML-escaped, including ampersands. Rendering the element's text must reproduce the original code characters. Ordinary inline spans remain byte-identical. Do not merely encode angle brackets inside Markdown backticks: entity text there can display differently from the intended code.

### D2: bounded scanner and unsafe inputs — AC1–AC3

Recognize complete single-line, single-backtick spans in source finding prose, with the existing guard's delimiter restrictions as the supported subset. Track fenced blocks and escaped/doubled/unmatched delimiters so they cannot become normalization targets. Inspect closing-tag-like syntax generically, not a tag allowlist or the ticket's exact expression. Leave unsupported spans unchanged; do not retry them through a broader replacement.

This scanner never receives the completed HTML review as its formatting input. Renderer-generated table/details/summary boundaries therefore cannot be mistaken for code literals. Arbitrary raw HTML reviews and genuine structural-boundary negative controls are fed unchanged to the existing consumer in T3. No consumer guard, exemption, suppression directive, or classification rule changes.

### D3: renderer hook and composed consumers — AC4, AC6

Extend `install_hooks` to validate the V6 renderer signature and V7 alias identity before installing any wrapper. Patch both the utils reference and reviewer import alias to the same wrapper; delegate all original arguments to the captured renderer with D1's copied data. Follow the existing idempotence boundary. Runtime incompatibility raises before running the action; do not silently proceed with an unpatched producer. Existing image-test teardown must restore the additional aliases so repeated hook tests remain isolated.

| Consumer site / ordered path | Expected behavior after D1–D3 |
| --- | --- |
| `pr_reviewer.convert_to_markdown_v2` at V7 → state append → fresh publication | Normalized visible finding reaches the existing bound publisher; the untouched state still refers to original finding content. |
| Direct `utils.convert_to_markdown_v2`, including `ImagePublicationTests.test_real_renderer_reduction` | Uses the same wrapper; unsupported/non-GFM inputs delegate, and existing fitting behavior remains available after rendering. |
| Runtime fresh, edit-review, persistent-review wrappers → `publish_review_record` → `bind_review_record` → `fit_review` | Operate on the producer's formatted result; current-head validation precedes one create and independent exact-ID/body readback. No previously published record is edited or replayed. |
| Runtime publication limiter → `fit_review` | Already-rendered output is fitted without a second formatter pass; expanded HTML counts toward the publication limit. Oversized protected content retains existing diagnostic behavior. |
| `apply-readiness-labels.sh` visible-review classifier → masking → HTML validation → severity/security/verification evaluation | Classifies the actual readback, with the unchanged guard and blocker precedence. Unsupported raw HTML still escalates. |

V3/V4/V7 enumerate the consumers. No earlier guard branch is removed or narrowed; a new representation reaches existing branches.

### D4: regression delivery and documentation — AC1–AC6

Add a dedicated synthetic test module and shell wrapper rather than adding incident payloads. The shell uses explicit Bash launchers and the `# covers:` convention in V9. Default mode runs the standard-library unit tests; `--image-smoke` runs synthetic integration cases in V5's image with networking disabled, mocked GitHub create/readback, and a read-only checkout. Emit a fabricated publication record for the host to run the real classifier, focus-label and verification-only predicates plus the existing D15 predicate; do not replace those consumers with test doubles.

Documentation targets are listed below; the developer must also reconcile any earlier normative claim that all within-limit comments remain byte-identical: ordinary code remains unchanged, but affected newly rendered code is intentionally formatted before fitting. No edits to the earlier spec or unrelated historical plans are needed.

**Classifications**: Parser-risk applies to D2's source-text scanner. Concurrent-event-source does not apply: no listeners, async queues or shared runtime state across reviews are introduced; hook setup remains startup-scoped. Cross-cutting checklist does not apply: no repository-wide review or planning category changes. Complex workflow decision-gate change does not apply: existing classification and authority gates are preserved. There is no database, API, application UI, dependency upgrade or workflow-permission change.

## Parser Edge Cases and Unit-Test Mapping

These are indicative coverage classes, not a frozen fixture count. In new `scripts/development-workflow/tests/test_pr_agent_inline_code.py`, map each row to the named automated test family and include parameterized variants where useful.

| ID | Concrete input / boundary | Test family and required assertion |
| --- | --- | --- |
| E1 | Prose containing single-backtick `re.split(r"</td>\|^### ", section)` | `test_mixed_closing_tag`: equivalent code text, source input untouched, rendered card classifiable. The backslash before the pipe is table escaping only. |
| E2 | Ordinary `helper()`; already entity-looking literal `&lt;/td&gt;`; non-code prose | `test_ordinary_unchanged`: no formatting delta. |
| E3 | Closing tags with mixed case, whitespace after slash, attributes-looking text; ampersands and quotes inside the same span | `test_boundary_variants`: generic matching, HTML escaping once, exact decoded code text. |
| E4 | Two affected spans on one line, interleaved ordinary spans; Unicode prose | `test_multiple_spans`: preserve order, spacing and all non-target text. |
| E5 | Escaped backtick; double-backtick delimiter; unmatched opener; multiline span; trailing backslash | `test_unsupported_delimiters`: do not normalize the unsupported construct or pair through it; consumer retains existing rejection where applicable. |
| E6 | Backtick and tilde fenced examples, closing fence at least as long as opener, code literal adjacent to a fence | `test_fence_boundaries`: fenced text untouched, adjacent eligible prose handled, no accidental span across fences. |
| E7 | Literal nested HTML in code versus raw `<details><summary>Example ` followed by a real closing summary, then the closing backtick outside that container | `test_structural_boundaries`: escape source literal; unchanged composed-HTML negative must still fail the original guard. Include malformed/nested wrappers and declaration/processing-instruction negatives. |
| E8 | Empty/missing/wrong-typed review/findings/content; unsupported producer field and non-GFM rendering | `test_input_shapes`: preserve upstream delegation and source immutability, never infer a clean verdict. |

## Testing Strategy

**T1 — Unit/source scanning**: Execute E1–E8 in the dedicated module with synthetic input only. Assert decoded HTML code text, ordinary byte equality, idempotence on already formatted output, unchanged non-target fields, and unchanged original input objects. No historical captured comment is imported as test data.

**T2 — Actual producer and publication**: In image mode, enter via the installed reviewer renderer alias, append actual producer review state, then exercise fresh `publish_comment`, review `edit_comment`, and persistent-review publication with synthetic provider context. Assert one create and exact readback per call, no old-comment edit, unchanged semantic state and severity. On the host, classify the independently retrieved body: Possible Issue-only affected and ordinary controls are `clean`, with verification-only false; visible D15 matches only the fabricated reviewed head. This is the composed proof for AC1, AC2, AC4 and AC6.

**T3 — Independent blockers and rejected evidence**: Each of security findings, verification-required evidence, and a hard focus-label blocker is introduced independently alongside E1 and reaches its existing non-clean classification on the host. Add missing/wrong/stale head, mismatched state head, malformed/duplicate state, live-head drift, readback mismatch, and genuinely ambiguous raw HTML controls. Identity failures that are rejected before publication assert zero creates instead of inventing a readback. Unknown or missing state keeps the existing policy; do not add a new provenance requirement. Test below-limit, exact-limit and expansion-over-limit cases with outcomes assessed after fitting, without treating a diagnostic/omission as the positive E1 result. Covers AC3–AC6.

**T4 — Compatibility and hook isolation**: Plant incompatible renderer signatures and a mismatched imported alias; startup must fail before partial installation/publication. Restore the compatible source and demonstrate success. Verify repeated hook installation, captured aliases restored during test teardown, and non-review provider delegation. Record concrete test file/line plus failing/passing output in implementation PR evidence for materially extended compatibility checks.

**Regression commands after implementation**:

<!-- workflow-shell-contract: bash-zsh -->
```bash
bash scripts/development-workflow/tests/test-pr-agent-inline-code.sh
bash scripts/development-workflow/tests/test-pr-agent-inline-code.sh --image-smoke
python3 scripts/lint/workflow-shell-guard-lint.py --base-ref origin/develop
python3 scripts/lint/workflow-shell-snippet-lint.py --base-ref origin/develop
```

Use ShellCheck on the added shell wrapper as well. The new suite must be selected by the existing diff-driven selector for runtime and new test-file changes. The proposed wrapper contains no shell word-splitting loop; preserve Bash 3.2 compatibility. No new executable guidance illustrates portable splitting, so dual-shell splitting evidence is not applicable.

**Proportionality/Gate B**: A small formatter sits between ambiguous source and irreversible publication; synthetic coverage must therefore address scanning plus renderer binding, publication identity and blocker preservation. Extend existing harness conventions; do not build a new generic Markdown parser, bespoke document validator, browser framework or production service. No fixed assertion/test count is required.

## Seed Data

Fabricate findings with `src/example.py`, repository `synthetic/repo`, commit `a` repeated 40 times, and comment IDs allocated by an in-memory fake. Keep all fixtures in the dedicated synthetic test module. Use E1–E8 and T2–T4 classes for construction, with actual producer state serialization in image mode. No live GitHub writes, credentials, private configuration, model calls, or copied incident comment bodies are test inputs. No design assets were supplied.

## Files to Modify

| File | Purpose / design reference |
| --- | --- |
| `scripts/development-workflow/pr-agent-runtime.py` | D1–D3 pure helper and renderer hook; existing consumer guard remains unchanged. |
| `scripts/development-workflow/tests/test_pr_agent_inline_code.py` (new) | T1–T4, synthetic unit and pinned-image integration coverage. |
| `scripts/development-workflow/tests/test-pr-agent-inline-code.sh` (new) | D4 test entrypoint and host-consumer bridge. |
| `scripts/development-workflow/tests/test_pr_agent_runtime.py` | Restore newly patched renderer references in existing image-harness setup/teardown; no incident fixture additions. |
| `docs/workflow/development-workflow/integrations/pr-agent.md` | Document D1/D2 boundary, unchanged consumer gates and targeted synthetic commands. |
| `scripts/development-workflow/README.md` | Update the runtime publication summary for D1's pre-render formatting. |
| `docs/testing/workflow/2070-pr-agent-inline-code.smoke-test.md` | Record implementation evidence for the plan-stage runbook. |
| `changelog.d/2070.fixed.pr-agent-inline-code.md` (new) | One release fragment for this producer correction. |

Project architecture/domain/database docs and AGENTS.md need no change: their placeholder project descriptions do not specify this producer format. V9 supports keeping workflows, provider/model configuration and sync runtime ownership unchanged; test suites are framework-internal artifacts. This is not a sweep or pattern-completeness migration; a residual sweep gate is not applicable.

## Risks and Mitigations

| Risk | Mitigation / verification |
| --- | --- |
| Formatting a completed review hides a real container boundary | D1 source-only boundary; E7/T3. |
| Entity encoding changes visible code or double-escapes a literal | D1 text equivalence; E2/E3 and T2 decoded code assertion. |
| Render-time mutation changes finding state or severity | Copy-on-render in D1; original-object and state comparisons in T1/T2. |
| Hook installation misses the reviewer alias or becomes incompatible | V7 enumeration and D3/T4. |
| Encoding expansion or an earlier check changes the composed verdict | Consumer table and T2/T3, including limit and independent blocker cases. |
| New runtime is not active on its own implementation PR | V9 trusted-base behavior; prove the new path offline in the pinned image. Do not promote trusted-base code or edit older bot evidence to make the PR green. |

## Implementation Order

1. Revalidate the operational assumptions above, read the approved spec, and inspect actual source at implementation start. Stop on conflicting architecture or risk above medium; do not modify #2064/#2069.
2. Add the synthetic E1 regression, prove it fails on the unmodified producer path, then implement D1/D2 and the functional D3 renderer binding needed to prove T1 plus the positive T2 path. Commit this coherent, verified source-formatting increment.
3. Complete T2–T4 composed-path coverage and D3 compatibility/isolation verification, including planted-violation evidence. Commit after the synthetic host/image commands pass; never checkpoint failing or partial code.
4. Update the documentation targets and record smoke evidence. Add the fragment using the repository's `- **Classifiable PR-Agent inline code** (#2070): ...` format. Run applicable lint, suite-selection checks, review and CI gates.
5. Stop with the implementation PR ready for Luis's technical review and separate merge OK. The plan PR itself also requires a separate explicit OK before its merge; this plan does not grant either merge authority.
