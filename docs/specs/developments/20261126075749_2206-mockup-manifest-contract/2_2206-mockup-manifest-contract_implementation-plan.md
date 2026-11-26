# Mockup framework: manifest contract and verify script — Implementation Plan

**Spec**: [1_2206-mockup-manifest-contract_specs.md](1_2206-mockup-manifest-contract_specs.md)
**Smoke test runbook**: [2206-mockup-manifest-contract.smoke-test.md](../../../testing/workflow/2206-mockup-manifest-contract.smoke-test.md)

---

## Summary

**Approach**: Add one verify tool to the always-synced workflow scripts. It
has a small Bash entry point and a standard-library Python module. Its four
subcommands cover the spec's three tables:

- `manifest` verifies one manifest;
- `tree` verifies every manifest of an opted-in design tree, using #2211's
  `workflow_design_opt_in`;
- `inventory` lists the screen and state ids a spec may cite;
- `resolve` answers whether one citation resolves.

The manifest is read as data with a strict scanner and Python's JSON decoder;
nothing in it is ever executed. Token mirroring is checked by a small static
reader of HTML `<style>` blocks, linked in-repository stylesheets and the root
element's `style` attribute.

A new test suite exercises the tool against committed fixture manifests and
mutated copies in throwaway directories. The framework reference gains the
Manifest section and loses its #2206 "forthcoming" line. The implementation
PR carries the vault replacement text, and the template owner applies it.

**Estimated complexity**: L

**Rationale**: no existing file changes behaviour. The parsing surface is real,
though: a manifest file-form scanner, an HTML reader and a CSS reader with
nesting, at-rules and `!important`. Add a tree walk with fail-closed folder
handling and a test suite that covers every AC6 case. No workflow, reviewer
configuration, checkpoint policy or `.ai-dev-workflow.yaml` change.

**Dependencies**: #2211 (merged in #2228, provides `workflow_design_opt_in`;
V5). The spec is merged on `develop` (V1).

**Template-Fit Check (Protocol 02 Step 0)**: re-run at plan time and passed.
The tool reads plain files with Bash and Python 3, which the workflow helpers
already require. It is opt-in and inert unless called, and it is not tied to
any consumer stack.

**Repository mode**: `mode` is absent from `.ai-dev-workflow.yaml`, so the mode
is `single_repo` and this repository owns the plan (V2).

---

## Plan decisions

Each decision is stated here once; every other section refers to it by label.

- **P1 — Placement and distribution.** Two new files in
  `scripts/development-workflow/`:
  - `mockup-manifest-verify.sh`, the Bash entry point;
  - `mockup-manifest-verify.py`, the logic, standard library only, Python 3.9
    or later.

  Both ship through the existing `scripts/development-workflow/` always_sync
  `hub_only` glob, so `single_repo` and `workflow_hub` consumers receive them
  with the next sync (V3). They are not added to the `product_repo_injection`
  list, so `sync-manifest.yaml` does not change. A hub stage can verify a
  product checkout by path with `--repo-root`. Delivering the tool into
  product repositories belongs with the cross-repository home decision that
  #1470 leaves to #2214 (decision 3).
- **P2 — Interface.** Invocation is
  `bash scripts/development-workflow/mockup-manifest-verify.sh <subcommand> …`:

  | Subcommand | Arguments | Spec table |
  | --- | --- | --- |
  | `manifest` | `<manifest-path> [--repo-root <dir>]` | Manifest verification table |
  | `tree` | `[--repo-root <dir>]` (default: the current Git toplevel) | Tree verification table |
  | `inventory` | `<manifest-path> [--repo-root <dir>]` | BR16, AC13 |
  | `resolve` | `<manifest-path> --screen <id> [--state <id>] [--repo-root <dir>]` | Citation table |

  Output is `KEY=value` lines on stdout, one value per line (P3). Exit
  codes:
  - `0`: a non-failing outcome (Conforms, Not opted in, No mockups found, an
    inventory listed, Resolves).
  - `1`: a failing outcome (Does not conform, Invalid configuration, Cannot
    check, Does not resolve).
  - `2`: a caller or environment error. The cause is a usage error, a
    `--repo-root` that is not a directory, a missing `python3`, or a manifest
    path that is a directory in `inventory` or `resolve`. The message goes to
    stderr and nothing goes to stdout.

  Callers treat every non-zero exit as failing.

  Keys per subcommand (the code values are the spec's outcomes in snake case;
  each `_LABEL` key carries the spec's display label):

  | Subcommand | Keys, in order |
  | --- | --- |
  | `manifest` | `MANIFEST_RESULT` (`conforms` / `does_not_conform`), `MANIFEST_RESULT_LABEL`, `MANIFEST_PATH`, `MANIFEST_KIND` (the `$kind` value, or empty), `PROBLEM_COUNT`, `PROBLEM` (repeated) |
  | `tree` | `TREE_RESULT` (`not_opted_in` / `invalid_configuration` / `no_mockups_found` / `conforms` / `does_not_conform`), `TREE_RESULT_LABEL`, then for an invalid opt-in the `DESIGN_PROBLEM_COUNT` and `DESIGN_PROBLEM` lines passed through unchanged; when opted in, `DESIGN_ROOT`, `MOCKUPS_FOLDER`, `UNREADABLE_FOLDER_COUNT`, `UNREADABLE_FOLDER` (repeated), `MANIFEST_COUNT`, and per manifest `n` (1-based, sorted by path) `MANIFEST_<n>_PATH`, `MANIFEST_<n>_RESULT`, `MANIFEST_<n>_PROBLEM_COUNT`, `MANIFEST_<n>_PROBLEM` (repeated) |
  | `inventory` | `INVENTORY_RESULT` (`listed` / `cannot_check`), `INVENTORY_RESULT_LABEL` (`Listed` / `Cannot check`), then for `cannot_check` the `manifest` keys; for `listed`, `SCREEN_COUNT`, per screen `n` in manifest order `SCREEN_<n>_ID`, `SCREEN_<n>_LINK`, `SCREEN_<n>_STATE_COUNT`, and per state `m` `SCREEN_<n>_STATE_<m>_ID`, `SCREEN_<n>_STATE_<m>_INITIAL` (`true` / `false`), `SCREEN_<n>_STATE_<m>_LINK` |
  | `resolve` | `CITATION_RESULT` (`resolves` / `does_not_resolve` / `cannot_check`), `CITATION_RESULT_LABEL`, `CITATION_REASON` (`none` / `unknown_screen` / `unknown_state` / `manifest_does_not_conform`), `CITATION_LINK` (only for `resolves`), then for `cannot_check` the `manifest` keys |

  Links use BR9: `#screen=<screen_id>` for a screen and
  `#screen=<screen_id>&state=<state_id>` for a state.
- **P3 — Problem lines and escaping.** Each problem is one line,
  `PROBLEM=<rule> <place>: <detail>`.
  - `<rule>` is the spec rule id (`BR1` … `BR19`).
  - `<place>` is one of: `manifest`, `screen <id>` (or
    `screens[<index>]` when the id is unusable), `screen <id> state <id>`,
    `navigation <path>` (for example `navigation[0].items[2]`),
    `viewport <id>`, or `token <path>`.
  - `<detail>` names the field, then the value found (`found <value>`) or
    `absent`, then `expected <accepted values>` (UX rules, AC8).

  Values are printed on one line using #2211's escaping. Backslash, CR, LF,
  tab and other control characters become `\\`, `\r`, `\n`, `\t`, `\xNN` and
  `\uNNNN`. A found string longer than 80 characters is cut to 80 plus `…`,
  and a list or mapping is described by its type only. A file-level problem
  says why the file is not data and never echoes file content (UX rules).
  Paths are printed relative to the repository root when they are inside it.
- **P4 — Reading the manifest file (BR1, verification rows 1 to 3).**
  1. Open and read the file in binary mode. A missing file, a directory or a
     read error gives row 1.
  2. Decode as strict UTF-8 and drop one leading BOM. A decode error gives
     row 2 ("not UTF-8 text").
  3. Scan from the start. Skip ASCII whitespace, `//` comments (to the next
     line break) and `/* … */` comments; an unterminated block comment gives
     row 2. Require the exact text `window.__MOCKUP_MANIFEST__`, with no
     whitespace or comment inside it. Then skip whitespace and comments and
     require `=`, which the next character must not extend into `==`.
  4. Skip whitespace and comments, then decode one JSON value with
     `json.JSONDecoder.raw_decode`, using two hooks. `parse_constant` rejects
     `NaN` and `Infinity`. `object_pairs_hook` rejects a duplicate key at any
     depth. Either rejection, or any decode error, gives row 2.
  5. After the value, skip whitespace and comments, accept one optional `;`,
     skip again and require end of file. Anything else, such as a second
     statement or a trailing call, gives row 2.
  6. A decoded value that is not a JSON object gives row 3.

  Each row ends verification with its single problem. The module never
  imports, evaluates or spawns anything for a manifest (D3, AC10, AC16).
- **P5 — Field checks (row 4, BR2 to BR8, BR12, BR19).** Checks run in a fixed
  order so output is deterministic:
  1. Top-level fields in BR2's table order.
  2. Screens in list order. For each screen, its fields in BR3's table order,
     then its states in list order with BR4 fields and BR5 forbidden fields.
  3. Navigation, depth first.
  4. Viewports.
  5. Mirroring (P6).

  Rules that need a known screen set use the set of string `screen_id`s
  collected from screen objects in pass 2. Those rules are `default_screen`,
  `nav_screen` and navigation references.

  The rules:
  - **Slug (BR6).** `^[a-z][a-z0-9]*(-[a-z0-9]+)*$`.
  - **Duplicates.** A duplicate `screen_id` is reported at its second and
    later occurrences, and so is a duplicate `state_id` within one screen or
    a duplicate viewport `id`.
  - **Booleans.** `initial` must be a JSON boolean when present.
  - **Whole numbers.** `width` and `height` must be JSON integers above zero,
    so `1440.0`, `1e3` and booleans are problems.
  - **Text fields (BR19).** These must be non-empty strings when present.
  - **Traversal.** Iterative, with no recursion, so a deeply nested
    navigation tree cannot exhaust the interpreter stack.
  - **Unknown fields (BR12).** Never reported, except the BR5 fields on a
    state.
  - **`$status` (BR2).** Changes nothing.
  - **Mirroring trigger.** P6 runs only when `$kind` is exactly
    `design-intent`. With any other `$kind` value only the BR2 `$kind`
    problem is reported, because the kind is unknown.
- **P6 — Token mirroring (BR10, BR11).**
  - **Locating files.**
    - The page is `index.html` in the manifest's folder.
    - The token file is `tokens.json` in the parent of the nearest ancestor
      folder named exactly `mockups`. No such ancestor is a BR11 problem.
    - Each problem names the file:
      - a missing or unreadable page or token file;
      - a token file that is not UTF-8, not valid JSON (duplicate keys
        rejected as in P4) or not an object.
    - When the page cannot be read, the token file is still checked, but no
      token can be compared.
  - **Tokens.**
    - Walk the token object in file order and skip every key starting with
      `$` together with everything under it.
    - A string value is a token named `--` + the path joined by `-`.
    - Any other non-object value (number, boolean, null, list) is a BR10
      problem naming the token path.
  - **Sources, in document order.** The page is read with `html.parser`.
    - Every `<style>` element's text.
    - Every `<link>` whose `rel` tokens include `stylesheet` (ASCII case
      insensitive) and whose `href` is non-empty.
    - The `style` attribute of the first `<html>` start tag.
  - **Link resolution.**
    - Strip any `?…` or `#…` and percent-decode.
    - These hrefs are not read, which is the BR10 stated limitation:
      - one with a URL scheme, or starting with `//` or `/`;
      - one whose real path resolves outside the repository root.
    - An in-repository link that is missing, unreadable or not UTF-8 is a
      BR11 problem.
    - `@import` is never followed.
  - **CSS reading (P7 lists the edge cases).** Tokenize comments, strings,
    escapes and bracket nesting, then read rules:
    - An at-rule ending in `;` is skipped.
    - An at-rule with a block has its block read as a rule list.
    - A qualified rule is a `:root` rule when its top-level comma-split
      selector list contains a selector equal to `:root` (ASCII case
      insensitive, after trimming).
    - In a `:root` rule's block:
      - declarations are split at top-level `;`;
      - a nested at-rule's block is read as more declarations of the same
        `:root` rule;
      - a nested qualified rule is not a `:root` rule.
    - Nested qualified rules inside any other rule are never `:root` rules.
    - The `style` attribute is read as one declaration list.
  - **Declarations.**
    - The name is the text before the first top-level `:`, trimmed. Only
      names starting with `--` count, and they are case sensitive.
    - The value is the rest, with comments removed and surrounding ASCII
      whitespace trimmed.
    - A trailing top-level `!` + optional whitespace + `important` (ASCII
      case insensitive) is removed and flags the declaration.
  - **Comparison.** For each token:
    - no declaration of its property is a "not declared" problem;
    - each declaration whose value differs from the trimmed token value is a
      problem naming the source and line;
    - each flagged declaration is an `!important` problem.

    Values compare exactly after trimming. Internal whitespace is not
    collapsed.
  - **Sources in problems.** A source is named `index.html <style> #k`,
    `<relative stylesheet path>` or `index.html <html style>`, with the
    1-based line of the declaration.
- **P7 — Parser edge cases (normative for the implementation and tests).**
  See the Parser-risk addendum in Testing Strategy, where each case maps to
  a test.
- **P8 — Tree walk (BR17, tree rows 1 to 6).**
  - **Opt-in.** The Bash entry point sources `workflow-lib.sh`, runs
    `workflow_design_opt_in "$repo_root"` and pipes its output into the Python
    module's `tree` subcommand, with no temporary file.
    - `not_opted_in` gives row 1.
    - `invalid` gives row 2, with the `DESIGN_PROBLEM` lines passed through.
    - Otherwise the mockups folder is
      `<repo_root>/<DESIGN_ROOT>/mockups`.
  - **The mockups folder.** It is examined with `os.lstat`.
    - `FileNotFoundError` or `NotADirectoryError` on any component means the
      folder is confirmed missing: row 4 when nothing else applies.
    - Any other `OSError` means its existence cannot be determined, and
      leads to row 3.
    - A mockups path that is a regular file or a symlink is a folder that
      cannot be searched: row 3.
  - **Walking.** Use iterative `os.scandir`, sorted by name.
    - Skip only the direct child `shared` of the mockups folder, of any type.
    - Descend real directories.
    - A symlinked directory, or a folder whose listing raises `OSError`, is
      recorded as an unreadable folder (row 3), and the walk continues.
    - Every entry named exactly `mockup-manifest.js` that is a regular file,
      or a symlink to one, is verified with P4 to P6.
  - **Outcome.** Apply rows 3 to 6 in order. Every manifest found is listed
    with its result.
- **P9 — Inventory and citations (BR16, citation rows 1 to 4).**
  - Both subcommands first verify the manifest with P4 to P6. A manifest that
    does not conform yields `cannot_check`, which includes the manifest
    outcome and its problems.
  - `resolve`:
    - an unknown `--screen` is `unknown_screen`;
    - a `--state` that the named screen does not have, including a screen
      with no states, is `unknown_state`;
    - an empty `--screen` or `--state` value is a caller error (exit 2).
- **P10 — Repository root.**
  - `--repo-root` when given, else `git -C <manifest folder> rev-parse
    --show-toplevel`.
  - When neither gives a directory, the folder that contains the design root
    is used. That is the parent of the token file's folder, or, failing that,
    the manifest's own folder.
  - The root decides only whether a linked stylesheet is "inside the
    repository" and how paths are printed.
- **P11 — Read-only and fresh (BR14, AC15).**
  - Python runs as `python3 -I -B`, so no bytecode cache is written and no
    user site is imported. Every file is opened read-only.
  - Nothing is cached between runs, and no network module is imported.
  - The Bash entry point creates no file. It runs Git only for P10's
    `rev-parse` and for the `tree` default root.
- **P12 — Fixtures and tests.**
  - **Committed fixtures.**
    `scripts/development-workflow/tests/fixtures/mockup-manifest-verify/` (the
    suite's own fixture folder, V9) holds a small, complete example tree:
    - `design/tokens.json`, with a `$description` key and nested groups;
    - `design/mockups/intent-app/mockup-manifest.js`, `index.html` and
      `styles/tokens.css`: Design intent, valid, satisfying AC4 and AC7;
    - `design/mockups/repro-app/mockup-manifest.js` and `index.html`:
      Reproduction, valid, no mirroring (AC5);
    - `design/mockups/shared/mockup-manifest.js`: deliberately invalid, to
      prove exclusion (AC11);
    - `invalid-examples/`:
      - `function-wrapper.js`;
      - `object-literal.js`;
      - `executes-on-load.js` (AC10);
      - `several-problems.js` (AC8).

    These double as the worked examples AC2 links to.
  - **Generated cases.** The remaining AC6 cases are mutations of the
    intent-app fixture, written into a fresh `mktemp -d` copy by a small
    inline `python3 -I -B -c` JSON edit in the suite. Some cases edit the
    page or the token file instead of the manifest.
- **P13 — Documentation.**
  - The framework reference gets a new "Manifest" section, placed before
    "Forthcoming" (AC1, AC2).
  - The #2206 forthcoming bullet is removed (AC3).
  - `scripts/development-workflow/README.md` gets a section for the tool.
  - There is one changelog fragment.
- **P14 — Vault hand-off (AC19, D4).** The implementation PR description
  carries, verbatim, the two replacement texts in L5. The description states
  that the template owner applies them in the vault. The implementing role
  never opens the vault for writing.

### Acceptance criteria coverage

| AC | Implementation | Test / smoke |
| --- | --- | --- |
| AC1, AC2, AC3 | L3 (P13) | smoke Steps 1-2 |
| AC4, AC5, AC7, AC9 | L1, L2 (P4-P6), fixtures (P12) | T-intent-valid, T-repro-valid, T-shared-state-id, T-unknown-fields |
| AC6 | L1, L2 (P4-P6) | T-ac6-* (one per case, Testing Strategy) |
| AC8 | P3, P5 | T-several-problems |
| AC10, AC16 | P4, P11 | T-no-execution (node stub on `PATH`) |
| AC11, AC12 | L1, L2 (P8) | T-tree-*, T-template |
| AC13, AC14 | L2 (P9) | T-inventory, T-resolve-* |
| AC15 | P11 | every case snapshots the case directory before and after |
| AC17 | additive only (L6) | selected suites green; `git diff --numstat` shows no changed existing script |
| AC18 | L6 (no manifest change) | coverage check clean; smoke Step 7 |
| AC19 | L5 (P14) | smoke Step 8 |

---

## Verification Log

All repository searches ran at `bc0c80a0` (V0) unless the row says otherwise.

| ID | Check | Command / query | Result |
| --- | --- | --- | --- |
| V0 | Repo revision | `git rev-parse --short HEAD` on `implementation-plan/2206-mockup-manifest-contract` at creation | `bc0c80a0` (= `origin/develop`) |
| V1 | Spec merged | `git ls-tree origin/develop docs/specs/developments/20261126075749_2206-mockup-manifest-contract/` | lists `1_2206-mockup-manifest-contract_specs.md`; spec PR #2230 squash-merged as `bc0c80a0` |
| V2 | Repository mode | `grep -n '^mode:' .ai-dev-workflow.yaml` | no output |
| V3 | Sync classification | `python3 -B scripts/development-workflow/select-sync-manifest-entries.py --manifest sync-manifest.yaml --role <role>` for `single_repo`, `workflow_hub`, `product_repo` | `scripts/development-workflow/` and `docs/workflow/` are always_sync `hub_only` glob `**/*` for `single_repo` and `workflow_hub`; `product_repo` receives only the explicit `product_repo_injection` / `shared` entries, none of which is a new file of this plan |
| V4 | No existing manifest reader or verifier | S-V4 below | no output; searched every script, workflow, workflow doc and template directory, where a reader could live |
| V5 | Opt-in helper present | `git grep -c -E 'workflow_design_opt_in' bc0c80a0 -- scripts/development-workflow/workflow-lib.sh` (also the control for S-V4's search form) | `2` |
| V6 | No existing CSS reader | S-V6 below | the only `html.parser` users are `apply-readiness-labels.sh`, `graduation-closeout-lib.sh` and `pr-agent-runtime.py` (review-text extraction); no `:root` or CSS rule reading anywhere under `scripts/` |
| V7 | Python baseline | `/usr/bin/python3 --version`; `python3 --version` (2026-11-26) | `3.9.6` (macOS system) and `3.14.8`; the module must run on 3.9 |
| V8 | Python invocation pattern | `grep -n 'python3 -I -B' scripts/development-workflow/workflow-lib.sh` | `workflow_design_opt_in` already runs `python3 -I -B -c` |
| V9 | Suite discovery and fixture folder | `sed -n 11,31p scripts/development-workflow/select-test-suites.sh` | a suite `test-<name>.sh` covers `<name>.sh`, `<name>.py`, its own file and its own fixture directory; `# covers:` adds paths |
| V10 | Harness CI path filter | `sed -n '/^on:/,/^jobs:/p' .github/workflows/workflow-tests.yml` | `pull_request` paths `scripts/development-workflow/**` and the workflow file, so the new suite runs on the implementation PR |
| V11 | Coverage checker and fixtures | `grep -n fixtures scripts/development-workflow/check-sync-manifest-coverage.py` | test discovery excludes paths containing `/fixtures/` |
| V12 | Consumer-safe test rule | `sed -n 134,168p scripts/development-workflow/README.md` | template-only assertions must be gated by `workflow_template_is_template` with a printed `SKIP:` line |
| V13 | Forthcoming list | `grep -n -A8 '^## Forthcoming' docs/workflow/development-workflow/mockup-framework.md` | four bullets; the first is "Manifest contract and verify script — #2206." |
| V14 | Same-surface open PRs | `gh pr list --state open --limit 100 --json number,headRefName,files`, filtered to paths matching `mockup`, `design-scaffold`, `workflow-lib.sh`, `sync-manifest.yaml`, `scripts/development-workflow/README.md` (2026-11-26) | none |
| V15 | Shell snippet lint scope | `sed -n 1,60p scripts/lint/workflow-shell-snippet-lint.py` | `docs/workflow/` is in scope, so the reference's new snippet needs a `workflow-shell-contract` marker |

### Search commands

Searches with alternation are recorded here, outside the table, so no Markdown
escaping alters them. Run from the repository root.

```bash
# S-V4 (rev bc0c80a0)
git grep -n -i -E '__MOCKUP_MANIFEST__|mockup-manifest|mockup_manifest|verify-manifest' bc0c80a0 -- scripts/ .github/ docs/workflow/ template/
# S-V6 (rev bc0c80a0)
git grep -n -E 'HTMLParser|html\.parser|:root' bc0c80a0 -- scripts/
```

---

## Factual claim evidence

**Rule 6 — scoped obligations.** Each conditional obligation in this plan,
with its governed scope and discharge point:

| ID | Obligation | Governed scope | Discharged at |
| --- | --- | --- | --- |
| S1 | The template-repository tree assertion (AC12) runs only when `workflow_template_is_template` returns `true` | the single T-template case in the new suite, which reads this repository's own configuration | L4 T-template; prints `SKIP: T-template - not the template repository` in consumers |
| S2 | A permission-denied folder or file is tested only when the suite does not run as root | T-tree-unreadable and T-ac6-unreadable-page | L4, skipped with a printed reason when `id -u` is 0 |
| S3 | Mirroring runs only when `$kind` is exactly `design-intent` | every manifest P6 sees, in `manifest`, `tree`, `inventory` and `resolve` | P5's last check; T-repro-valid and T-ac6-kind-unknown |
| S4 | A linked stylesheet is read only when its href is relative and its real path is inside the repository root (P10) | every `<link rel=stylesheet>` in a Design intent page | P6 link resolution; T-css-link-outside, T-css-link-absolute |
| S5 | When the implementation-start re-run of V3 or V14 differs from this log, implementation stops before file edits | Implementation Order step 1 only | Implementation Order step 1 |
| S6 | The AC17 evidence is taken at the final implementation PR head; a commit pushed after it needs a new run | every implementation-branch commit after the recorded run | Implementation Order step 11, before `ready-for-human-review` |

---

## Cross-Cutting Operational Assumption Check

### Applicable

| Assumption surface | Recorded value | Authoritative source | Verified at | Bounded cross-check scope | Result |
| --- | --- | --- | --- | --- | --- |
| Artifact owner and approved base | this repository, `develop` | `.ai-dev-workflow.yaml` (no `mode`, V2), `AGENTS.md` Git & Branching | 2026-11-26, `bc0c80a0` | this invocation (#2206 only) and same-surface open PRs (V14: none) | `Verified` |
| Sync classification of every new path | V3 | `sync-manifest.yaml` via `select-sync-manifest-entries.py` | 2026-11-26, `bc0c80a0` | same as above | `Verified` |
| Opt-in helper output contract | `DESIGN_OPT_IN=` first line; `DESIGN_ROOT=` when opted in; `DESIGN_PROBLEM_COUNT=` / `DESIGN_PROBLEM=` when invalid; exit 0 for every outcome, 2 for caller errors | `docs/workflow/development-workflow/mockup-framework.md` "Reading the outcome from a stage" (#2211) | 2026-11-26, `bc0c80a0` | same as above | `Verified` |

At implementation start, re-run V3 and V14 (S5).

---

## Layer-by-Layer Changes

### L1 — Entry point (`scripts/development-workflow/mockup-manifest-verify.sh`, new) (P1, P2, P8, P11)

- Shell contract `bash`. Starts with `set -euo pipefail` and is compatible
  with Bash 3.2: no associative arrays, `mapfile` or `readarray`.
- It resolves its own directory and the sibling `.py` file, then validates
  the subcommand and `--repo-root`. Usage errors exit `2` with stderr only.
- It requires `python3` and exits `2` with a stderr message when it is
  missing.
- `manifest`, `inventory` and `resolve` run
  `python3 -I -B "$py" <subcommand> "$@"`.
- `tree` resolves the repository root: `--repo-root`, else
  `git rev-parse --show-toplevel`, else exit `2`. It sources
  `workflow-lib.sh` from its own directory and runs
  `workflow_design_opt_in "$root" | python3 -I -B "$py" tree --repo-root "$root"`.
  A non-zero `workflow_design_opt_in` exit is an environment error (exit `2`).
- `shellcheck --severity=warning` clean.

### L2 — Logic (`scripts/development-workflow/mockup-manifest-verify.py`, new) (P2-P10)

- Standard library only (`json`, `os`, `re`, `sys`, `html.parser`,
  `urllib.parse`, `subprocess` for P10's `git rev-parse` only), and it runs on
  Python 3.9.
- It is organized as small functions:
  - `read_manifest` (P4);
  - `check_fields` (P5);
  - `check_mirroring` (P6), with helpers `read_tokens`, `collect_sources`,
    `parse_css_rules` and `parse_declarations`;
  - `walk_tree` (P8);
  - `inventory` and `resolve` (P9);
  - `emit` (P3).
- `main()` dispatches the subcommands.
- A module docstring names the spec and the contract section of the
  framework reference.

### L3 — Framework reference (`docs/workflow/development-workflow/mockup-framework.md`) (AC1-AC3)

- Add a `## Manifest` section after "Starting from the scaffold" and before
  "Forthcoming", with these sub-sections:
  - **File form**: BR1 with a minimal example.
  - **Top-level fields**, **Screen fields** and **State fields**: the BR2 to
    BR4 tables, including BR19 value types.
  - **Rules**: BR5 (the full forbidden set), BR6 slugs, BR7 navigation shape,
    BR8 viewports, BR12 unknown fields, BR15 language.
  - **Links**: the BR9 link format.
  - **Token mirroring**: BR10 and BR11, including the stated limitation.
  - **Checklist and verify script**: the five checklist items, a statement
    that the verify script performs them, the four subcommands, the outcome
    and citation code values with display labels, and a link to the fixture
    folder as examples.
- The usage snippet carries `<!-- workflow-shell-contract: bash -->` (V15):

  ```bash
  bash scripts/development-workflow/mockup-manifest-verify.sh manifest design/mockups/<app>/mockup-manifest.js
  ```

- Link the fixtures relatively
  (`../../../scripts/development-workflow/tests/fixtures/mockup-manifest-verify/`).
  `docs/workflow/` and `scripts/development-workflow/` reach the same roles
  (V3), so the link resolves wherever the page is synced.
- In "Forthcoming", remove the #2206 bullet. Keep #2207, #2208 and #2214.
- In "Status and ownership", add the manifest contract to the list of what
  this page is canonical for.

### L4 — Test suite (`scripts/development-workflow/tests/test-mockup-manifest-verify.sh`, new)

- The header comment names the spec. Add
  `# covers: scripts/development-workflow/workflow-lib.sh` and
  `# covers: scripts/development-workflow/workflow-config-resolver.py`,
  because tree mode depends on them. Add a `# duration:` line measured
  locally. The suite's own `.sh`, `.py` and fixture folder are covered by
  naming (V9).
- Each case copies the fixture tree, or writes its input, into a fresh
  `mktemp -d` directory. It runs the entry point and compares stdout lines
  and the exit status.
- Each case snapshots the case directory before and after the run (a sorted
  `find` listing with file sizes and `cksum` output) and asserts the two are
  equal (AC15).
- Cases run under the invoking `bash` and `/bin/bash`.
- No real `.ai-dev-workflow.local.*` file is read or written. Tree cases
  write a fabricated versioned `.ai-dev-workflow.yaml` into the disposable
  repository.
- Cases are listed in Testing Strategy.

### L5 — Vault hand-off text (implementation PR description, P14) (AC19)

The implementation PR description carries, under a heading **Vault
replacement text (applied by the template owner)**, these two texts verbatim,
plus the note: "The template owner replaces these sections in
`40 - Conocimiento/Estándares/HTML Mockup Framework.md`; this PR does not edit
the vault."

Replacement for the vault's whole Manifest section (heading
`Manifest (mockup-manifest.js)`), including its sub-sections:

```markdown
## Manifest (`mockup-manifest.js`)

Contract: see *Manifest* in the [template reference](https://github.com/lhpaul/ai-dev-framework-template/blob/develop/docs/workflow/development-workflow/mockup-framework.md) (#2206): the data-only file form, every top-level, screen and state field, the rule that a state never carries screen-level fields, the navigation shape, the `#screen=<screen_id>&state=<state_id>` link format, token mirroring, and the verify script that performs the checklist. What follows is the rationale.

The manifest is the contract between mockup content, the viewer and any tooling, which is why it is data and not code: a checker can then read it without running it, and a reviewer can trust the check rather than re-reading ids by hand. A visual variant stays a state of its screen because a second `screen_id` for an error or an empty form breaks every link and inventory that counts destinations.

**Reproduction** manifests may still be generated from per-state sources, one file per state per viewport (Brokers Portal: 155 states across 14 screens and two viewports). That is sanctioned for reproductions only, because the output is a single manifest that CI can rebuild and compare; a hand-edited manifest at that size is unverifiable.
```

Replacement for the `### Optional: verify + smoke (code repos)` sub-section
of the Tooling section:

```markdown
### Verify

The manifest checks ship in the template as `scripts/development-workflow/mockup-manifest-verify.sh` (#2206): one manifest, a whole opted-in design tree, the id inventory a spec may cite, and whether a citation resolves. See *Manifest* in the [template reference](https://github.com/lhpaul/ai-dev-framework-template/blob/develop/docs/workflow/development-workflow/mockup-framework.md). Playwright viewer smoke and image crop tooling stay optional per repository.
```

### L6 — Supporting surfaces

- `scripts/development-workflow/README.md`: add a
  `### mockup-manifest-verify.sh` section next to the other helper sections,
  with the subcommands, exit codes and a link to the framework reference.
- `changelog.d/2206.added.mockup-manifest-verify.md` (Implementation Order
  step 9).
- Sync manifest: no change (P1). Classification of every new or changed
  path, from V3:

  | Path | Category and scope | Effect on a consumer without a design block |
  | --- | --- | --- |
  | `scripts/development-workflow/mockup-manifest-verify.sh` and `.py` | always_sync, `hub_only` (directory glob) | additive; runs only when called; `tree` reports Not opted in |
  | `scripts/development-workflow/tests/test-mockup-manifest-verify.sh` | always_sync, `hub_only` | new suite; its template-only assertion is gated (S1) |
  | `scripts/development-workflow/tests/fixtures/mockup-manifest-verify/**` | always_sync, `hub_only` | test data inside the scripts tree; never at a design root, so no design tree is created (D2) |
  | `docs/workflow/development-workflow/mockup-framework.md` | always_sync, `hub_only` | documentation only |
  | `scripts/development-workflow/README.md` | always_sync, `hub_only` | documentation only |
  | `changelog.d/2206.added.mockup-manifest-verify.md` | release fragment | assembled at release |
  | `docs/testing/workflow/2206-mockup-manifest-contract.smoke-test.md` | not in the manifest | not synced, like most per-item runbooks |

- No existing script, workflow, `.ai-dev-workflow.yaml`, reviewer
  configuration or checkpoint policy changes (AC17).

---

## Testing Strategy

The suite is `scripts/development-workflow/tests/test-mockup-manifest-verify.sh`
(L4). The case list below expresses coverage intent; it is indicative except
where marked.

**Valid fixtures (AC4, AC5, AC7, AC9).**

- T-intent-valid checks the intent-app fixture: Conforms, exit 0,
  `PROBLEM_COUNT=0`. The fixture has:
  - several screens, one with states and one initial state;
  - a navigation tree three levels deep;
  - two viewports and one image screen;
  - tokens mirrored in an inline `<style>` and in a linked
    `styles/tokens.css`;
  - one property declared twice with the same value;
  - a `$description` token key.
- T-repro-valid: the repro-app fixture conforms without mirroring.
- T-shared-state-id: `empty` under two screens conforms (in the fixture).
- T-unknown-fields: a mutation adds unknown fields at the top level, on a
  screen and on a state. The result still conforms.

**AC6 — Binding enumeration** (each spec case is its own named test; the
mutation may vary, the case set may not):

The file-form cases:

- T-ac6-missing-file
- T-ac6-function-wrapper
- T-ac6-object-literal
- T-ac6-not-object

The top-level field cases:

- T-ac6-kind-missing
- T-ac6-kind-unknown (`design intent` with a space)
- T-ac6-status-missing
- T-ac6-status-unknown
- T-ac6-frame-unknown
- T-ac6-default-screen-unknown
- T-ac6-screens-empty

The screen and state cases:

- T-ac6-screen-id-duplicate
- T-ac6-screen-id-not-slug
- T-ac6-screen-kind-missing
- T-ac6-screen-kind-unknown
- T-ac6-image-without-export
- T-ac6-title-not-string
- T-ac6-states-empty
- T-ac6-state-without-id
- T-ac6-state-id-duplicate
- T-ac6-no-initial
- T-ac6-two-initial
- T-ac6-state-route
- T-ac6-state-export
- T-ac6-state-nested-states

The navigation and viewport cases:

- T-ac6-navigation-not-list
- T-ac6-group-without-label
- T-ac6-group-without-items
- T-ac6-entry-without-screen-id
- T-ac6-nested-unknown-screen
- T-ac6-nav-screen-unknown
- T-ac6-viewport-id-duplicate
- T-ac6-viewport-width-not-positive

The mirroring cases:

- T-ac6-token-missing
- T-ac6-token-different
- T-ac6-token-earlier-different
- T-ac6-token-important
- T-ac6-link-missing
- T-ac6-token-not-string
- T-ac6-tokens-missing
- T-ac6-tokens-invalid-json
- T-ac6-tokens-not-object
- T-ac6-no-index-html
- T-ac6-not-in-mockups

Each case asserts:

- `MANIFEST_RESULT=does_not_conform`;
- exit 1;
- a `PROBLEM=` line carrying the expected rule id and field;
- for file-form cases, `PROBLEM_COUNT=1`.

**Problems, safety and runtime (AC8, AC10, AC15, AC16).**

- T-several-problems: `invalid-examples/several-problems.js` reports all of
  its problems in one result (at least one from each of BR3, BR5 and BR7).
  Each line has a place, a rule, `found …` or `absent`, and `expected …`.
- T-no-execution:
  - Put a stub `node` (and `deno`, `bun`) first on `PATH`; if invoked, each
    writes a marker file.
  - Run `executes-on-load.js`, whose body would write a file if executed.
  - Assert row 2 (`not readable as data`), no marker file, and no file
    created.
- AC15 is asserted by every case's before and after snapshot (L4).

**Tree (AC11, AC12).** Each case runs in a disposable Git repository with a
fabricated `.ai-dev-workflow.yaml`.

- T-tree-not-opted-in: no `design` block gives `not_opted_in`, exit 0.
- T-tree-invalid: `design: {home: x}` gives `invalid_configuration`, exit 1,
  with `DESIGN_PROBLEM` lines.
- T-tree-no-mockups: opted in with no `mockups` folder gives
  `no_mockups_found`, exit 0.
- T-tree-all-conform: the two valid apps give `conforms`, exit 0,
  `MANIFEST_COUNT=2`. The invalid `shared/` manifest is not listed.
- T-tree-one-fails: a third, invalid app gives `does_not_conform`, and only
  that manifest's result is `does_not_conform`.
- T-tree-unreadable: a `chmod 000` subfolder beside the valid apps gives
  `does_not_conform`, with `UNREADABLE_FOLDER=` naming it and both valid
  manifests still listed (S2).
- T-tree-symlinked-folder: a symlinked subfolder is listed as unreadable.
- T-tree-custom-root: `root: ui/` finds `ui/mockups`.
- T-template: run in this repository, the result is `not_opted_in` (S1).

**Inventory and citations (AC13, AC14).**

- T-inventory: the intent-app fixture lists every screen, the state ids,
  `INITIAL=true` exactly once per stated screen, and BR9 links.
- T-inventory-cannot-check: a non-conforming manifest gives `cannot_check`,
  exit 1, and no `SCREEN_` keys.
- T-resolve-screen and T-resolve-state: an existing screen, and an existing
  screen and state pair, give `resolves` with a `CITATION_LINK`.
- T-resolve-unknown-screen: gives `unknown_screen`.
- T-resolve-other-screens-state: a state that exists only under another
  screen gives `unknown_state`.
- T-resolve-cannot-check: gives `manifest_does_not_conform`.
- T-usage: an unknown subcommand, a missing argument, or an empty `--screen`
  gives exit 2 with empty stdout.

**AC17.** The change is additive.
`git diff --numstat origin/develop -- scripts/development-workflow ':!scripts/development-workflow/mockup-manifest-verify.*' ':!scripts/development-workflow/tests/test-mockup-manifest-verify.sh' ':!scripts/development-workflow/tests/fixtures/mockup-manifest-verify'`
lists only `README.md`. So no existing helper's code changes, and no existing
helper output can change. The suites that `select-test-suites.sh` selects for
the PR diff run green locally and in CI (V10). The new suite's `# covers:`
lines make it run whenever `workflow-lib.sh` or the resolver changes.

**AC18.** `python3 -B scripts/development-workflow/check-sync-manifest-coverage.py`
prints `RESULT=clean`. Smoke Step 7 applies L6's classification to a
disposable consumer copy and confirms that no design tree and no configuration
value appears.

### Parser-risk addendum (Step 3 classifier applies)

The plan is parser-risk: it adds a scanner for the manifest file form, an HTML
reader and a CSS reader. Each edge case below is normative (P7) and has an
automated unit case, run in the same suite through the `manifest` subcommand
on a minimal input. A test id that also appears in the AC6 list or the valid
fixture cases is one case that covers both.

**Manifest file form (P4):**

| Edge case | Input | Expected | Test |
| --- | --- | --- | --- |
| Comments before and after | `/* a */ // b` + assignment + `// c` | data form accepted | T-form-comments |
| No trailing semicolon | assignment with no `;` | accepted | T-form-no-semicolon |
| Two semicolons | `…};;` | row 2 | T-form-double-semicolon |
| UTF-8 BOM | BOM + assignment | accepted | T-form-bom |
| Not UTF-8 | Latin-1 byte `0xE9` in a string | row 2 "not UTF-8 text" | T-form-not-utf8 |
| Unterminated block comment | `/* …` with no end | row 2 | T-form-unterminated-comment |
| Comment inside the name | `window./*x*/__MOCKUP_MANIFEST__ = {}` | row 2 | T-form-name-comment |
| Similar names | `window.__MOCKUP_MANIFEST = {}`, `globalThis.__MOCKUP_MANIFEST__ = {}`, `window["__MOCKUP_MANIFEST__"] = {}` | row 2 for each | T-form-similar-names |
| Comparison instead of assignment | `window.__MOCKUP_MANIFEST__ == {}` | row 2 | T-form-double-equals |
| Second statement | assignment + `; console.log(1)` | row 2 | T-form-second-statement |
| Two assignments | two assignment statements | row 2 | T-form-two-assignments |
| JSON with comments inside | `{"a": 1 /* x */}` | row 2 | T-form-comment-in-json |
| JSON5 features | trailing comma; single quotes; unquoted key | row 2 for each | T-form-json5 |
| Non-finite numbers | `{"a": NaN}`, `Infinity` | row 2 | T-form-nonfinite |
| Duplicate key | `{"a": 1, "a": 2}` at depth 3 | row 2 naming the key | T-form-duplicate-key |
| Value not an object | `[]`, `"x"`, `null` | row 3 | T-ac6-not-object |
| Comment marker inside a JSON string | `{"$note": "see // and /* here"}` | accepted; the string is data | T-form-markers-in-string |
| Empty file | zero bytes | row 2 | T-form-empty |

**CSS and HTML reading (P6):**

| Edge case | Input | Expected | Test |
| --- | --- | --- | --- |
| Selector list | `:root, .x { --a: v }` | a `:root` rule | T-css-selector-list |
| Non-plain root selectors | `:root.dark {…}`, `html {…}`, `:is(:root) {…}`, `html:root {…}` | not read (stated limitation); token reported not declared | T-css-not-plain-root |
| Case of the pseudo-class | `:ROOT { --a: v }` | a `:root` rule | T-css-root-case |
| Property name case | `--A: v` for token `a` | not the same property; token not declared | T-css-name-case |
| `:root` inside a string or comment | `.x[data-a=":root"] {…}`, `/* :root { --a: v } */` | not a `:root` rule | T-css-root-in-string |
| Media query nesting | `@media (min-width: 1px) { :root { --a: other } }` with a matching top-level declaration | problem for the nested differing declaration | T-css-media |
| Statement at-rules | `@import "x.css"; @charset "utf-8";` | skipped; `x.css` never read | T-css-import |
| Nested at-rule in a root rule | `:root { @media (x) { --a: other } }` | counts as a `:root` declaration; problem | T-css-nested-at-rule |
| Nested qualified rule in a root rule | `:root { --a: v; .x & { --a: other } }` | only the outer declaration counts; conforms | T-css-nested-rule |
| Semicolon in a string value | `--f: "a;b"` | one declaration, value `"a;b"` | T-css-string-semicolon |
| Comment inside a value | `--a: v /* note */` | value `v` | T-css-value-comment |
| `!important` spellings | `--a: v !important`, `--a: v!IMPORTANT`, `--a: v ! important` | flagged for each | T-ac6-token-important |
| `!important` inside a string | `--f: "x !important"` | not flagged | T-css-important-in-string |
| Two declarations in one rule | `:root { --a: v; --a: v }` | both checked; conforms | T-intent-valid |
| Internal whitespace | token `16px` and `--a:   16px  ` | equal after trimming | T-css-trim |
| Value whitespace inside | token `a b` and `--a: a  b` | different; problem | T-css-inner-whitespace |
| Unterminated string | `--a: "v` at end of line | read up to the line break; no crash | T-css-unterminated-string |
| Unbalanced braces | missing final `}` | read to end of input; no crash | T-css-unbalanced |
| Root `style` attribute | `<html style="--a: v">` | a `:root` declaration | T-html-style-attr |
| `<style>` in an HTML comment | `<!-- <style>:root{--a:v}</style> -->` | not read | T-html-commented-style |
| `rel` variants | `rel="Stylesheet preload"`, `rel="alternate stylesheet"`, `rel="icon"` | first two read, third not | T-html-rel |
| Absolute, scheme and root-relative hrefs | `https://x/y.css`, `//x/y.css`, `/y.css` | not read; no problem | T-css-link-absolute |
| Link outside the repository | `../../../../outside.css` resolving above `--repo-root` | not read; no problem | T-css-link-outside |
| Query and fragment | `styles/tokens.css?v=2#x` | reads `styles/tokens.css` | T-html-href-query |
| Percent-encoded href | `styles/my%20tokens.css` | reads `styles/my tokens.css` | T-html-href-encoded |

**Suppression semantics**: not applicable; the tool has no inline directives.

---

## Seed Data

None. The fixtures in P12 are the test data, written in L4's cases into
disposable directories.

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/mockup-framework.md`: L3.
- [ ] `scripts/development-workflow/README.md`: L6.
- `AGENTS.md`, `README.md`, `docs/README.md`, `docs/project/*`,
  `docs/best-practices/*`, `REVIEW.md`: none. Wiring the review gate and the
  other stages is #2209, #2212 and #2213. The workflow index already links the
  framework reference (#2211).

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| The CSS reader misreads a real stylesheet and reports a false problem | Medium | Medium | P6 reads only `:root` rule declarations; the parser-risk table covers comments, strings, nesting and at-rules; problems name source and line so a maintainer can verify |
| A false Conforms on mirroring | Low | Medium | every declaration must match and `!important` fails (BR10); the stated limits are documented, not silent |
| Python 3.9 incompatibility | Low | High | no `match`, no `X \| Y` annotations; the suite runs under the system `/usr/bin/python3` on macOS when present |
| A deep or cyclic tree hangs the walk | Low | Medium | iterative walk; symlinked folders are not followed (P8) |
| A consumer's suite fails on a template-only assertion | Low | Medium | S1 gate with a printed `SKIP:` line (V12) |
| Existing consumer manifests do not conform (RADAR, Leasity) | Certain | Low | expected per D3; migration is #2214 or the pilot; nothing calls the tool yet |

### Reversal

Every change is additive. No stage calls the tool until #2212, #2214 or #2215
land, and no configuration, sync state or consumer file depends on it.
Reverting the implementation PR's squash commit restores the previous state.
The vault text is applied by its owner (D4). If the PR is reverted after that,
the owner restores the vault's previous Manifest section from the vault's own
history.

---

## Code Samples

```python
# Illustrative — adapt during implementation. Shape of the P4 reader only.
NAME = "window.__MOCKUP_MANIFEST__"

def read_manifest(path):
    try:
        raw = open(path, "rb").read()
    except OSError:
        return None, ("BR1", "manifest", "manifest file not found or unreadable")
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        return None, ("BR1", "manifest", "not readable as data: not UTF-8 text")
    text = text[1:] if text.startswith("﻿") else text
    i = skip_space_and_comments(text, 0)          # raises NotData on /* unterminated
    if not text.startswith(NAME, i):
        return None, ("BR1", "manifest", "not readable as data: expected window.__MOCKUP_MANIFEST__ =")
    # … "=" (not "=="), raw_decode with parse_constant / object_pairs_hook,
    # optional ";", then end of input; anything else is row 2.
```

```bash
# Illustrative — the tree subcommand in the entry point.
# shellcheck source=scripts/development-workflow/workflow-lib.sh
source "$script_dir/workflow-lib.sh"
workflow_design_opt_in "$root" | python3 -I -B "$script_dir/mockup-manifest-verify.py" tree --repo-root "$root"
```

---

## Implementation Order

Commit after each numbered step that leaves the tree coherent.

1. Re-run V3 and V14 (S5); stop on a change.
2. Fixtures (P12), then L2 `read_manifest` and `check_fields` with the
   `manifest` subcommand and `emit`.
3. L1 entry point for `manifest`. Run `bash -n` and
   `shellcheck --severity=warning`.
4. L4 suite: valid fixtures, file-form and AC6 field cases, run under both
   Bash versions and under `/usr/bin/python3` when present.
5. L2 `check_mirroring` with the CSS/HTML reader; add the mirroring AC6 cases
   and the parser-risk table cases.
6. L2 `walk_tree`, then L1 `tree`; add the tree cases and T-template.
7. L2 `inventory` and `resolve`, then L1; add those cases and T-usage. Record
   the suite's `# duration:`.
8. L3 reference section and L6 README section. Run
   `npx markdownlint-cli2` and `python3 scripts/lint/markdown-heuristic-lint.py`
   on the changed Markdown, and
   `python3 scripts/lint/workflow-shell-snippet-lint.py --base-ref origin/develop`.
9. Changelog fragment `changelog.d/2206.added.mockup-manifest-verify.md`:

   ```markdown
   - **Mockup manifest contract and verify script** (#2206): the framework reference now documents the `mockup-manifest.js` contract (data-only file form, top-level, screen and state fields, navigation shape, `#screen=&state=` links, token mirroring), and `scripts/development-workflow/mockup-manifest-verify.sh` checks one manifest or an opted-in design tree without executing it, lists the screen and state ids a spec may cite, and reports whether a citation resolves.
   ```

10. Run the selected suites locally and
    `python3 -B scripts/development-workflow/check-sync-manifest-coverage.py`
    (`RESULT=clean`). Open the implementation PR with L5's vault text in the
    description (AC19).
11. With every implementation commit pushed, record the AC17 evidence at the
    final PR head (S6) and run the smoke runbook.
