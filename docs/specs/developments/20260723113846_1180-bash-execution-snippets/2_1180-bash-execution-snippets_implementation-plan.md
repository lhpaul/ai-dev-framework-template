# Explicit Bash Execution for Workflow-Owned Snippets - Implementation Plan

**Spec**: [1_1180-bash-execution-snippets_specs.md](1_1180-bash-execution-snippets_specs.md)

**Smoke test runbook**: [1180-bash-execution-snippets.smoke-test.md](../../../testing/workflow/1180-bash-execution-snippets.smoke-test.md)

---

## Summary

**Approach**: Introduce a diff-aware linter for executable shell guidance on
repository-owned workflow surfaces. Each new or changed executable snippet must
declare `bash` or `bash-zsh` through a stable adjacent contract marker.
Bash-contract snippets must launch Bash at the copy/paste boundary (or be a
complete script with a Bash shebang); portable snippets are rejected when they
contain the known implicit-splitting constructs. Add real Bash/zsh regression
fixtures that assert processed values and argument groups, integrate the linter
into shell CI, and update the author/reviewer guidance that creates workflow
commands.

**Estimated complexity**: M

**Rationale**: Existing ShellCheck and `workflow-shell-guard-lint.py` protect
stored `.sh` code, but they do not understand executable fenced blocks,
generated commands, or prompt/command Markdown. A focused, added-diff linter
avoids turning historical documentation into immediate debt while preventing
new ambiguous boundaries.

**Dependencies**: Python 3 for linting, Bash and zsh for behavioral fixtures,
and the existing ShellCheck/shell CI workflow. macOS already provides both
shells; CI must install zsh when its runner image lacks it.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `21f23e3` |
| Template-fit check | Read `.ai-dev-workflow.yaml`, issue #1180, and the approved spec | Framework-owned execution guidance is template-generic; downstream application scripts stay out of scope |
| Existing shell lint | Read `scripts/lint/workflow-shell-guard-lint.py` and its test harness | Added-line rules cover workflow `.sh` files only; no fenced-snippet shell contract is parsed |
| Existing Bash 3.2 rule | `rg -n "SH005|Bash 3.2|bash 3.2" scripts/lint docs/workflow` | SH005 rejects associative arrays and Protocol 03 already requires Bash 3.2 compatibility |
| CI insertion point | `rg -n "workflow-shell-guard|scripts/lint" .github/workflows/shellcheck.yml` | Shell CI already runs linter unit tests and the diff-aware workflow shell guard |
| Author guidance | `rg -l "Shell Script Quality|workflow shell guard|workflow-shell-guard" REVIEW.md docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md docs/workflow/development-workflow/protocols/03-implement-development-protocol.md .claude/agents .cursor/agents .codex/skills` | Protocol 03, REVIEW, developer agents, and implementer skill currently own shell quality; planning surfaces need explicit executable-snippet guidance |
| Framework-owned prose surfaces | `rg -l '```(bash|sh|zsh|shell)' docs/workflow .agents/skills .codex/skills .claude/commands .claude/agents .cursor/commands .cursor/agents AGENTS.md | wc -l` | The repository has a broad executable-guidance surface, so the first release must be diff-aware |

---

## Shell Contract

Every newly added or modified executable fenced block on a framework-owned
surface uses one adjacent marker:

```text
<!-- workflow-shell-contract: bash -->
<!-- workflow-shell-contract: bash-zsh -->
```

- `bash` means the executable boundary must visibly launch Bash with
  `bash <script>`, `bash -lc`, or a `bash <<'BASH'` heredoc. A complete generated
  script may instead begin with `#!/usr/bin/env bash` and its invocation must
  execute that script rather than source it in the caller's default shell.
- `bash-zsh` means the block is intended to run unchanged in both shells and
  may not rely on implicit word splitting or shell-specific positional
  argument expansion.
- A fence label such as `bash` is syntax highlighting, not by itself an
  execution boundary.
- Non-executable examples, output blocks, and pseudocode do not need a shell
  contract but must not be represented as copy/paste executable commands.

---

## Layer-by-Layer Changes

### Workflow Shell Snippet Linter

- [ ] Add `scripts/lint/workflow-shell-snippet-lint.py`.
- [ ] Default to added/modified fenced blocks from
      `git diff <base>...HEAD`; support `--input <diff-file>` for unit tests and
      `--all` for explicit repository audits.
- [ ] Limit checked files to framework-owned workflow guidance:
      `AGENTS.md`, `docs/workflow/**`, `docs/best-practices/**`,
      `.agents/skills/**`, `.codex/skills/**`, `.claude/commands/**`,
      `.claude/agents/**`, `.cursor/commands/**`, `.cursor/agents/**`, and
      workflow-owned template/prompt files under `scripts/development-workflow/`.
- [ ] Ignore arbitrary downstream application directories and scripts outside
      the framework-owned paths.
- [ ] Parse CommonMark fenced blocks across diff hunks by loading the changed
      file and mapping added line numbers into their complete containing fence.
      This prevents a changed middle line from losing its opener/contract
      context.
- [ ] Treat `bash`, `sh`, `shell`, `zsh`, and unlabeled blocks containing shell
      command signals as candidates. Do not classify JSON, YAML, output, or
      pseudocode fences as executable without shell signals.
- [ ] Require the nearest non-blank preceding line to carry exactly one
      `workflow-shell-contract` marker for each new/changed executable block.
- [ ] Add rule `WS001` for a missing or invalid contract marker. Report source
      path, fence start, and correction choices.
- [ ] Add rule `WS002` when a `bash` contract does not visibly launch Bash at
      the execution boundary and is not a complete Bash-shebang script.
- [ ] Add rule `WS003` for `bash-zsh` blocks containing unquoted
      `for <name> in $<scalar>` or equivalent implicit-splitting loops.
- [ ] Add rule `WS004` for `bash-zsh` blocks containing
      `set -- $<scalar>` or equivalent implicit positional extraction.
- [ ] Add rule `WS005` when a declared portable snippet uses Bash-only features
      such as `BASH_SOURCE`, process substitution, Bash arrays, `[[ ... ]]`,
      indirect expansion, or `readarray`/`mapfile`.
- [ ] Add rule `WS006` when a Bash-contract snippet introduces Bash 4+ syntax
      such as associative arrays or `mapfile`/`readarray`, preserving the
      repository's Bash 3.2 support.
- [ ] Keep findings deterministic and actionable:
      file/line, rule ID, observed construct, declared contract, and “launch
      Bash” versus “rewrite portable” guidance.
- [ ] Do not add a general suppression in the first implementation. False
      positives should be corrected by marking non-executable fences accurately
      or restructuring the example.

### Behavioral Regression Fixtures

- [ ] Add `scripts/lint/tests/test-workflow-shell-snippet-lint.sh` for parser and
      finding behavior.
- [ ] Add fixture snippets for the exact incident patterns:
      whitespace loop iteration and `set -- $pair` positional extraction.
- [ ] Execute the corrected Bash-contract versions from both a Bash parent and
      a zsh parent; both parents must invoke Bash and produce the same expected
      list of processed items/arguments.
- [ ] Execute the portable alternatives unchanged under Bash and zsh and assert
      identical output records.
- [ ] Assert item count, item values, and extracted argument groups. A zero exit
      without expected records fails.
- [ ] Run Bash-contract fixtures through the repository's Bash 3.2 static rules
      (`workflow-shell-guard-lint.py`, ShellCheck dialect, and WS006). On macOS,
      also record the available `/bin/bash` version and execute the fixture.
- [ ] If zsh is unavailable, the behavioral test must fail with a clear missing
      dependency message rather than silently skip cross-shell evidence.

### CI and Developer Commands

- [ ] Update `.github/workflows/shellcheck.yml` path filters for the new linter,
      tests, and framework-owned guidance surfaces.
- [ ] Install or verify zsh before behavioral tests on the CI runner.
- [ ] Run the new linter unit harness before the live diff-aware linter.
- [ ] Invoke
      `python3 scripts/lint/workflow-shell-snippet-lint.py --base-ref
      "origin/$GITHUB_BASE_REF"` for pull requests.
- [ ] Update `scripts/lint/README.md` with scope, rules, contract markers,
      examples, and commands.
- [ ] Add the focused command to `AGENTS.md` Common Commands so maintainers can
      reproduce CI locally.

### Planning, Implementation, and Review Guidance

- [ ] Update
      `docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md`
      to require plans that add executable workflow snippets to declare the
      intended shell contract and list the linter/behavioral evidence.
- [ ] Update
      `docs/workflow/development-workflow/protocols/03-implement-development-protocol.md`
      Shell Script Quality Checklist to require contract markers, explicit Bash
      launchers, and value/count assertions for iteration-sensitive examples.
- [ ] Update `REVIEW.md` documentation and shell-review checks so ambiguous
      executable boundaries, unsafe portable splitting, missing behavioral
      assertions, or Bash 4+ examples are important/blocking as appropriate.
- [ ] Update `docs/best-practices/1-general.md` Shell Scripting guidance with
      the framework-owned scope and canonical Bash/Bash-zsh patterns.
- [ ] Update creator guidance that can add plans, implementation code, or
      executable workflow prose:
      - `.claude/agents/tech-lead.md`
      - `.cursor/agents/tech-lead.md`
      - `.claude/agents/developer.md`
      - `.cursor/agents/developer.md`
      - `.codex/skills/workflow-plan-writer/SKILL.md`
      - `.codex/skills/workflow-implementer/SKILL.md`
- [ ] Reviewer skills need no duplicated rules when they already read
      `REVIEW.md`; verify with a residual query and update only a surface that
      independently restates shell-snippet rules.

### Database / Data Layer

- [ ] Not applicable. No schema, migration, seed, or product data.

### Backend / API

- [ ] Not applicable. No service or API change.

### Shared Packages / Libraries

- [ ] Not applicable. The new shared tooling is a repository Python linter.

### Frontend / UI

- [ ] Not applicable. Diagnostics are CLI/CI output.

### Infrastructure / Configuration

- [ ] Shell CI gains a zsh runtime dependency and path filters.
- [ ] No secrets, deployment resources, or external services.

---

## Files to Modify

### Required Implementation Files

- [ ] `scripts/lint/workflow-shell-snippet-lint.py` - new diff-aware fenced
      snippet linter.
- [ ] `scripts/lint/tests/test-workflow-shell-snippet-lint.sh` - parser,
      contract, and behavioral regression harness.
- [ ] `.github/workflows/shellcheck.yml` - path filters, zsh availability,
      harness, and live lint.
- [ ] `scripts/lint/README.md` - rules and usage.
- [ ] `docs/best-practices/1-general.md` - canonical shell-contract guidance.
- [ ] `docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md`
      - planning requirement for executable guidance.
- [ ] `docs/workflow/development-workflow/protocols/03-implement-development-protocol.md`
      - pre-submission contract and behavioral validation.
- [ ] `REVIEW.md` - plan/code/documentation review requirements.
- [ ] `.claude/agents/tech-lead.md` and `.cursor/agents/tech-lead.md` - plan
      author guidance.
- [ ] `.claude/agents/developer.md` and `.cursor/agents/developer.md` -
      implementation author guidance.
- [ ] `.codex/skills/workflow-plan-writer/SKILL.md` and
      `.codex/skills/workflow-implementer/SKILL.md` - Codex creator guidance.
- [ ] `AGENTS.md` - local validation command.

### Explicitly Not Required

- [ ] Existing historical snippets are not bulk-rewritten. Diff-aware
      enforcement applies when a block is added or modified.
- [ ] Arbitrary downstream application scripts and documentation are outside
      the checked path allowlist.
- [ ] Stage orchestration protocols that merely call stored Bash scripts need
      no change unless their executable block is edited by this implementation.
- [ ] `CHANGELOG.md` is exempt from this plan PR. The implementation PR adds the
      literal in **Implementation Order**.

---

## Shell-Contract Decision Matrix

| Surface / snippet | Declared contract | Allowed form | Required verification | Mirror surfaces | Example |
| --- | --- | --- | --- | --- | --- |
| Copy/paste block depends on Bash splitting or syntax | `bash` | `bash -lc`, `bash <<'BASH'`, or `bash <script>` | Same expected records when launched from Bash and zsh parents | Protocols 02/03, REVIEW, agents/skills, CI | zsh parent invokes Bash heredoc containing a Bash loop |
| Complete generated script | `bash` | Bash shebang plus explicit script execution | Bash syntax, ShellCheck, Bash 3.2 rules, expected records | Same | Generated temp script starts `#!/usr/bin/env bash` and is run with `bash` |
| Snippet advertised for Bash and zsh | `bash-zsh` | No unsafe implicit splitting or Bash-only constructs | Execute unchanged under both shells; compare records | Same | Newline-based `while IFS= read -r` processing |
| Fenced output or pseudocode | Not applicable | Explicit non-executable fence/label | Linter confirms it is not classified as executable | Linter docs/tests | `text` output block |
| Executable block with no contract | Invalid | None | WS001 blocks until contract is declared | CI and REVIEW | A new `sh` fence with commands but no marker |
| `bash-zsh` block with `for item in $LIST` | Invalid | Rewrite data handling or change to explicit Bash launcher | WS003 plus behavioral fixture | CI and REVIEW | Incident loop that silently ran once under zsh |
| `bash-zsh` block with `set -- $pair` | Invalid | Portable explicit parsing or Bash launcher | WS004 plus argument-group assertion | CI and REVIEW | Incident positional extraction |
| Bash-contract block using Bash 4+ feature | Invalid | Rewrite for Bash 3.2 | WS006, existing SH005, ShellCheck | CI and implementation guidance | Associative array in generated command |

---

## Cross-Cutting Checklist Coverage

This plan adds a conditional safety/quality category for executable
framework-owned shell guidance, so cross-cutting checklist requirements apply.

- [ ] Planning protocol: Protocol 02 requires shell contract and verification
      planning when executable guidance changes.
- [ ] Implementation protocol: Protocol 03 owns enforcement and validation.
- [ ] Review contract: `REVIEW.md` classifies ambiguous/unsafe boundaries.
- [ ] Tech-lead mirrors: Claude, Cursor, and Codex plan writers carry the
      requirement.
- [ ] Developer mirrors: Claude, Cursor, and Codex implementers carry the
      requirement.
- [ ] CI enforcement: the linter and behavioral harness prevent guidance-only
      compliance.
- [ ] Best-practice guidance: one canonical document explains patterns rather
      than duplicating full examples in every agent surface.

---

## Parser-Risk Addendum

The new linter parses diffs, CommonMark fences, adjacent contract markers, and
shell-like text.

### Edge-Case Enumeration

1. Fence syntax:
   - backtick and tilde fences
   - opening fence longer than closing minimum
   - indented fences
   - changed line in the middle of an existing block
   - embedded backticks shorter than the opener
2. Contract placement:
   - marker immediately before fence
   - blank line between marker and fence
   - duplicate/conflicting markers
   - marker after the fence
3. Executable classification:
   - `bash`, `sh`, `shell`, `zsh`, and unlabeled command block
   - `text`, `json`, `yaml`, and explicit output/pseudocode
4. Bash boundaries:
   - `bash script.sh`
   - `bash -lc '...'`
   - `bash <<'BASH'`
   - full Bash-shebang script
   - `bash` fence with no launcher
5. Implicit splitting:
   - `for item in $LIST`
   - `for item in "$LIST"` (one item by design, not implicit splitting)
   - `set -- $pair`
   - comments/quoted prose containing the same text
6. Portable/Bash-only constructs:
   - `BASH_SOURCE`, arrays, process substitution, `[[ ]]`, indirect expansion
   - POSIX-style `case`, quoted variables, and `while IFS= read -r`
7. Bash version:
   - `declare -A`, `local -A`, `mapfile`, and `readarray`
   - indexed arrays allowed only in Bash-contract snippets
8. Scope:
   - framework-owned docs/skills/commands
   - downstream `src/` or product documentation ignored
9. Diff behavior:
   - new fence
   - modified unsafe middle line
   - untouched historical block
   - deleted block

### Unit Test Mapping

Create `scripts/lint/tests/test-workflow-shell-snippet-lint.sh` with:

1. `commonmark_fence_boundaries` and `changed_middle_line_maps_to_fence` for
   Edge case 1.
2. `valid_adjacent_contract`, `blank_gap_rejected`, and
   `conflicting_markers_rejected` for Edge case 2.
3. `shell_fences_classified` and `output_fences_ignored` for Edge case 3.
4. `bash_launchers_accepted` and `bash_fence_without_launcher_ws002` for Edge
   case 4.
5. `implicit_loop_ws003`, `positional_split_ws004`, and
   `quoted_or_comment_lookalikes_ignored` for Edge case 5.
6. `portable_bash_feature_ws005` and `portable_patterns_accepted` for Edge case
   6.
7. `bash4_features_ws006` and `bash3_indexed_array_accepted` for Edge case 7.
8. `owned_paths_checked` and `downstream_paths_ignored` for Edge case 8.
9. `added_and_modified_blocks_checked`,
   `historical_untouched_ignored`, and `deleted_block_ignored` for Edge case 9.

### Suppression Semantics

No inline suppression ships in the MVP. Authors choose an accurate contract,
make the block non-executable, launch Bash explicitly, or rewrite the snippet
to be genuinely portable.

---

## Concurrency Safety

No concurrent event sources are introduced.

- **Shared mutable state guards**: Not applicable; linting is read-only.
- **Re-entrancy / in-flight tracking**: Repeated lint over the same diff is
  deterministic.
- **Event deduplication**: Findings use stable rule/path/fence-start identity.
- **Listener and resource cleanup**: Behavioral fixtures use a temporary
  directory removed by a trap.
- **Race conditions at initialization**: Test dependencies are checked before
  fixtures run.
- **Race conditions at teardown**: No background processes; temp scripts are
  removed after both shell runs.
- **Error propagation across async boundaries**: Not applicable; all shell
  executions are synchronous and their output/status are asserted.

---

## Testing Strategy

**Test types**: Diff/fence parser harness, real Bash/zsh behavioral fixtures,
existing workflow shell guard regression, ShellCheck, CI integration, Markdown
lint, and smoke runbook.

**Key scenarios to test**:

1. Bash-dependent copied commands visibly launch Bash from either parent shell.
   Maps to AC1 and AC2.
2. Portable snippets process identical items and arguments under both shells.
   Maps to AC3, AC6, and AC9.
3. Unsafe new implicit loop/positional splitting is rejected with path/reason.
   Maps to AC4 and AC5.
4. The linter checks only framework-owned guidance. Maps to AC8.
5. Bash-contract examples stay within Bash 3.2 syntax. Maps to AC7.
6. Behavioral tests assert records/counts rather than only exit status. Maps to
   AC2, AC3, AC6, and AC9.

**Regression suite**:

- `bash scripts/lint/tests/test-workflow-shell-snippet-lint.sh`
- `python3 scripts/lint/workflow-shell-snippet-lint.py --base-ref origin/develop`
- `bash scripts/lint/tests/test-workflow-shell-guard-lint.sh`
- `python3 scripts/lint/workflow-shell-guard-lint.py --base-ref origin/develop`
- ShellCheck on changed `.sh` files

**Smoke test runbook**:
`docs/testing/workflow/1180-bash-execution-snippets.smoke-test.md`

---

## Seed Data

No database seed data is required.

| Entity | Values / Scenario | File |
| --- | --- | --- |
| Synthetic diffs | Valid/invalid contracts, fences, paths, and split constructs | Generated in `test-workflow-shell-snippet-lint.sh` |
| Behavioral records | Whitespace item list and slash-delimited owner/repo/number pairs | Generated in the same harness |

---

## Documentation Updates

- [ ] `docs/best-practices/1-general.md` - framework-owned shell contracts and
      canonical execution patterns.
- [ ] `docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md`
      and `03-implement-development-protocol.md` - plan and implementation gates.
- [ ] `REVIEW.md` - review expectations.
- [ ] Creator agent/skill mirrors listed in **Files to Modify** - concise
      pointer to canonical guidance.
- [ ] `scripts/lint/README.md` - rule reference and commands.
- [ ] `AGENTS.md` - local validation command.
- [ ] Project domain/architecture/database docs need no update; this is
      workflow authoring and validation behavior.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Linter flags non-executable examples | Medium | Medium | Parse fence labels/signals and support explicit output/pseudocode classification |
| Bash fence is mistaken for enforced execution | High | High | Require launcher/shebang mechanism; syntax highlighting alone is insufficient |
| Historical debt blocks unrelated PRs | High | Medium | Check only added/modified blocks by default |
| Portable scanner misses quoted/comment context | Medium | Medium | Token-aware line classification and negative lookalike tests |
| CI environment lacks zsh | Medium | Medium | Explicit dependency setup and fail visibly when unavailable |
| New examples use Bash 4+ features | Medium | High | WS006 plus existing SH005 and Bash 3.2 guidance |
| Cross-cutting guidance drifts | Medium | Medium | Canonical best-practice section with concise mirrored pointers and residual query |

---

## Code Samples

No implementation code samples are included. The Shell Contract section defines
the required public marker and enforcement mechanisms.

---

## Implementation Order

1. Implement diff/fence/contract parsing and WS001/WS002 in
   `workflow-shell-snippet-lint.py`.
2. Add CommonMark, scope, and Bash-boundary parser tests.
3. Add WS003-WS006 with quoted/comment negatives and Bash 3.2 rules.
4. Add behavioral Bash/zsh fixtures for loop iteration and positional
   extraction; assert exact records and counts.
5. Integrate the harness and live linter into `shellcheck.yml`.
6. Update `scripts/lint/README.md` and
   `docs/best-practices/1-general.md`.
7. Update Protocols 02/03, `REVIEW.md`, and all creator agent/skill mirrors
   listed in **Files to Modify**.
8. Add the implementation changelog entry under `[Unreleased]` using this exact
   format:
   `- **Make Workflow Shell Contracts Explicit** (#1180): Lint executable workflow snippets for explicit Bash launchers or verified Bash/zsh portability.`
9. Add the local linter command to `AGENTS.md`.
10. Run the new linter tests, behavioral fixtures, existing shell guard tests,
    ShellCheck, workflow guard lint, and Markdown lint.
11. Execute
    `docs/testing/workflow/1180-bash-execution-snippets.smoke-test.md` and record
    the implementation evidence in the PR.
