# Mockup framework: design layout, tokens, README sections and the design opt-in key — Implementation Plan

**Spec**: [1_2211-mockup-framework-layout_specs.md](1_2211-mockup-framework-layout_specs.md)
**Smoke test runbook**: [2211-mockup-framework-layout.smoke-test.md](../../../testing/workflow/2211-mockup-framework-layout.smoke-test.md)

---

## Summary

**Approach**: Add one canonical reference page for the framework contract under
the workflow docs tree, a starter design tree under `template/design-scaffold/`
that sync never ships, a commented design block in the template-owned header of
`.ai-dev-workflow.yaml`, and one additive read helper in `workflow-lib.sh` that
returns exactly one opt-in outcome by reusing the configuration resolver's
existing strict YAML reader. A new test suite covers the helper; the vault
standard is edited in its own repository as a separate step.

**Estimated complexity**: M

**Rationale**: One reference page, a few small scaffold files, a comment block,
two pointer edits, one helper of moderate size and its test suite, plus an
out-of-repository edit. No existing function, workflow, reviewer
configuration or checkpoint policy changes.

**Dependencies**: None. The spec is merged on `develop` (V1).

**Template-Fit Check (Protocol 02 Step 0)**: re-run at plan time and passed.
The spec is stack-agnostic (plain HTML mockups, a JSON token file and a
configuration flag), opt-in, and inert for a project without UI.

**Repository mode**: `mode` is absent from `.ai-dev-workflow.yaml`, so the mode
is `single_repo` and this repository owns the plan (V2).

---

## Plan decisions

Each decision is stated here once; every other section refers to it by label.

- **P1 — Scaffold location and distribution.** The scaffold lives at
  `template/design-scaffold/design/`. It is not registered in
  `sync-manifest.yaml`, so template sync never ships it, and it is never a live
  `design/` tree at the template root (BR13, AC7). Rationale: #1470 decision 2
  says the opt-in scaffold must not be pushed into every consumer by sync. A
  project created from the template receives the folder with the template's
  files, so setup (#2208) can copy from it; adoption (#2214) copies from the
  upstream template checkout that template sync already prepares (V12). If
  #2214 later needs the scaffold delivered by sync, #2214 adds the manifest
  entry; nothing here forecloses that.
- **P2 — Helper name and implementation.** The helper is
  `workflow_design_opt_in [repo_root]` in
  `scripts/development-workflow/workflow-lib.sh`. It runs
  `python3 -I -B -c "$program"`, where `program` is a single-quoted local
  string (so the Python text itself uses no single quotes), following the library's existing `python3 -c` pattern; a
  here-document inside `$( … )` is avoided because Bash 3.2 mis-parses quotes
  and parentheses there. The program loads `workflow-config-resolver.py` by
  file path and calls its existing `capture_config_text` and
  `validate_selected_yaml` (the strict, dependency-free framework reader).
  `-B` stops Python from writing a bytecode cache next to the resolver (AC14).
  The resolver file itself is not edited.
- **P3 — Output contract** (binding; downstream items #2209, #2212, #2213 and
  #2210 consume it). Every outcome prints `KEY=value` lines to stdout and
  exits 0:

  | Line | Not opted in | Opted in | Invalid configuration |
  | --- | --- | --- | --- |
  | `DESIGN_OPT_IN=` | `not_opted_in` | `opted_in` | `invalid` |
  | `DESIGN_OPT_IN_LABEL=` | `Not opted in` | `Opted in` | `Invalid configuration` |
  | `DESIGN_ROOT=` | — | configured string, or `design/` | — |
  | `DESIGN_ROOT_SOURCE=` | — | `configured` or `default` | — |
  | `DESIGN_HOME=` / `DESIGN_HOME_LABEL=` | — | code value / display label | — |
  | `DESIGN_KIND=` / `DESIGN_KIND_LABEL=` | — | code value / display label | — |
  | `DESIGN_PROBLEM_COUNT=` | — | — | number of problem lines |
  | `DESIGN_PROBLEM=` (repeated) | — | — | `<field>: <detail>` |

  Code values and display labels are the spec's (Statuses / Enum Values).
  `<field>` is one of `configuration` (row 2), `design` (row 4),
  `design.home` (row 5), `design.kind` (row 6), `design.root` (row 7); rows 5
  to 7 are emitted in that order. Each `<detail>` names the value found or
  says it is absent, and lists the accepted values (UX rules); the
  `configuration` detail never echoes file content. Every value is printed on
  one physical line with the same escapes `print_kv_escaped` uses (backslash,
  CR, LF, tab, other C0/DEL and C1 controls). Inside a `DESIGN_PROBLEM`
  detail only, a found string longer than 80 characters is cut to its first
  80 characters plus `…` before escaping (truncate the decoded value, then
  escape), and a list or mapping is described by its type, never by its
  content; `DESIGN_ROOT`, `DESIGN_HOME` and `DESIGN_KIND` are never truncated.
  Output is written as UTF-8 regardless of the locale (bytes to
  `sys.stdout.buffer`, unencodable characters replaced), so a valid non-ASCII
  root never fails the program. Exit status 2 with no stdout is reserved for caller
  or environment errors, not outcomes: a supplied `repo_root` argument that is
  empty or not a directory, or, with no argument, a failure of
  `workflow_repo_root` to resolve the checkout.
- **P4 — Configuration source.** The helper reads only
  `<repo_root>/.ai-dev-workflow.yaml`, where `repo_root` defaults to
  `workflow_repo_root`. It never reads `.ai-dev-workflow.local.yaml`, and it
  ignores `AI_DEV_WORKFLOW_CONFIG_FILE` and `WORKFLOW_LOCAL_REVIEW_OVERRIDE_ROOT`
  (BR18). It reads the file on every call and keeps no cache (BR16).
- **P5 — Resolution mapping onto the reader.** Applied in the spec's table
  order:
  - Row 1: no filesystem entry at the path (`os.path.lexists` false).
  - Row 2: any other failure to capture, decode (strict UTF-8) or parse the
    file, including a directory, a dangling symlink, a FIFO, an unreadable
    file, a duplicate key, and a top level that is not a mapping.
  - Row 3: the parsed top-level mapping (including an empty file) has no
    `design` key.
  - Row 4: `design` is null, empty, an empty mapping, a list or a scalar.
  - Rows 5 and 6: the key is absent or its value is not exactly one of the
    accepted strings (non-string values included).
  - Row 7: `root` is present and is not a string, is the empty string
    (exactly as BR6 says; a whitespace-only string is non-empty and is
    judged by the remaining checks), is absolute (starts with `/` or `\`, or
    with a drive letter and colon), or normalises lexically (backslashes read as `/`) to `..` or a
    path starting with `../`. The check is lexical only; no file is inspected
    (BR15). A root that normalises to `.` is inside the repository.
  - Unknown keys in the block are ignored (BR7).
- **P6 — Fail-closed fallback.** If `python3` is unavailable or the inline
  program exits non-zero or prints no `DESIGN_OPT_IN=` first line, the helper
  prints the row 1 result when no filesystem entry exists at the path and the
  row 2 outcome otherwise. That row 2 problem line says the check itself could
  not run (`python3` or the configuration reader failed) and that the file may
  be valid, so a maintainer is not sent to debug a good configuration; it is
  distinct from the ordinary row 2 wording that the file could not be read.
  The helper never prints partial output: it captures the program's stdout
  and prints it only after the check above.
- **P7 — Reference page.** The contract page is
  `docs/workflow/development-workflow/mockup-framework.md`. It links to the
  scaffold with an absolute URL to the upstream template,
  `https://github.com/lhpaul/ai-dev-framework-template/tree/develop/template/design-scaffold/design`,
  and also names the in-repository path `template/design-scaffold/design/` as
  a code span. It never uses a relative link: consumers sync the docs tree but
  not the scaffold (P1), so a relative link would be dead in a consumer and
  break its link lint, while the absolute link resolves everywhere once the
  implementation PR is merged (UC1 "follow a link to the scaffold").
- **P8 — Commented example placement.** The inactive design block example sits
  inside the existing `# <!-- TEMPLATE-OWNED-START -->` / `END` header of
  `.ai-dev-workflow.yaml` (V6), so template sync offers it to consumers as
  comment text only (AC11, AC16).
- **P9 — Vault edit.** The vault standard is edited and committed in its own
  repository by L8; that commit is not part of the template PR diff (AC18).

### Acceptance criteria coverage

| AC | Implemented by | Verified by |
| --- | --- | --- |
| AC1 to AC6 | L1, L6 | smoke Steps 1 to 3 |
| AC7 to AC10 | L2 | smoke Step 4 |
| AC11 | L3 | T-template; smoke Step 5 |
| AC12 | L4 | T1 to T17; smoke Step 6 |
| AC13 | L4 (P3) | T-multi; smoke Step 6 |
| AC14 | L4 (P2) | T-unchanged |
| AC15 | L4 (additive) | Testing Strategy "AC15 evidence"; smoke Step 7 (Part A at Implementation Order step 13, Part B at step 14) |
| AC16 | L7 | smoke Step 8 |
| AC17, AC18 | L8 | smoke Step 9 |

---

## Verification Log

All repository searches ran at `d8b9f005` (V0) unless the row says otherwise.

| ID | Check | Command / query | Result |
| --- | --- | --- | --- |
| V0 | Repo revision | `git rev-parse --short HEAD` on `implementation-plan/2211-mockup-framework-layout` at creation | `d8b9f005` (= `origin/develop`) |
| V1 | Spec merged | `git ls-tree --name-only HEAD docs/specs/developments/20261125124423_2211-mockup-framework-layout/` | lists `1_2211-mockup-framework-layout_specs.md`; spec PR #2226 is squash-merged as `d8b9f005` |
| V2 | Repository mode | S-V2 below | no output; the only `mode:` line is `guardrails.mode` (indented) |
| V3 | No existing design-key reader | S-V3 below (with a control search proving the pattern form matches) | no match, exit 1; control prints a non-zero count for `workflow-lib.sh`. Searched every script and workflow directory, where a reader could live |
| V4 | No live design tree or scaffold | S-V4 below | `template` only; `template/` holds `product-repo-injection` and `workflow-hub` |
| V5 | No existing framework reference | `git grep -il mockup HEAD -- docs/workflow REVIEW.md AGENTS.md README.md .claude .cursor .codex .agents` | `design-assets.md` (attachments, #2210 scope), `00-add-backlog-item-protocol.md`, `02-generate-implementation-plan-protocol.md` (mentions only); no layout or opt-in contract |
| V6 | Template-owned header | `grep -n 'TEMPLATE-OWNED' .ai-dev-workflow.yaml` | `START` on line 1, `END` on line 46; no other markers |
| V7 | Sync classification of touched surfaces | `python3 -B scripts/development-workflow/select-sync-manifest-entries.py --manifest sync-manifest.yaml --role single_repo` (also `workflow_hub`, `product_repo`) | `docs/workflow/` always_sync `hub_only` glob `**/*`; `scripts/development-workflow/` always_sync `hub_only`; `scripts/development-workflow/workflow-lib.sh` and `workflow-config-resolver.py` always_sync `product_repo_injection`; `.ai-dev-workflow.yaml` project_specific, `mixed_content: true`, `html_comments`; `README.md` project_specific; `template/` has entries only for `workflow-hub/` and `product-repo-injection/` |
| V8 | Manifest coverage baseline | `python3 -B scripts/development-workflow/check-sync-manifest-coverage.py` | `RESULT=clean` |
| V9 | Coverage checker matches path tokens, not gating | `sed -n 1,40p` and `sed -n 216,256p scripts/development-workflow/check-sync-manifest-coverage.py` | a synced test that names a tracked path the manifest does not ship is `UNCOVERED`; a project-owned path is reported, not a gap |
| V10 | Strict reader behaviour | the probe in **Reader probe** below, run with `python3 -B` | `design:` and `design: null` → `None`; `root: 42` → int; `root: "42"` → str; `root: [design]` → list; `root:` (nested mapping) → dict; `root: true` → bool; `root: ''` → `''`; flow mapping → dict; unclosed flow, tab indent, duplicate key, top-level list or scalar → `ConfigError`; non-UTF-8 → `UnicodeDecodeError`; directory → `SourceIntegrityError`; dangling symlink → `ConfigError`; missing file → `None` capture; empty or comment-only file → `{}`; the template's own config parses with no `design` key |
| V11 | Validation tolerates the new key | in a scratch repo holding `schema_version: 2` plus a valid `design` block with an extra field: `python3 scripts/development-workflow/workflow-config-resolver.py validate --repo-root <scratch>` and `... mode --repo-root <scratch>` | both exit 0; no unknown-key rejection |
| V12 | Upstream template checkout exists in sync | `grep -n 'git clone' .claude/commands/sync-template.md` | line 47 clones the upstream template into a temporary directory |
| V13 | Test discovery | `sed -n 1,30p scripts/development-workflow/select-test-suites.sh` | suites declare covered paths with `# covers:` lines; no workflow edit is needed to wire a suite |
| V14 | Markdown lint CI scope | `sed -n 10,60p .github/workflows/markdown-lint.yml` | lints `docs/specs/developments`, `docs/testing/workflow`, `docs/workflow`, `changelog.d`, `CHANGELOG.md`; `template/` is not in scope |
| V15 | Shell snippet lint scope | `sed -n 1,60p scripts/lint/workflow-shell-snippet-lint.py` | in scope: `docs/workflow/`, `scripts/development-workflow/` and other agent surfaces; not `docs/specs/` or `docs/testing/` |
| V16 | Bytecode cache visibility | `grep -n pycache .gitignore` | `__pycache__/` is ignored, so a cache would not show in `git status`; P2 still uses `-B` so nothing is written |
| V17 | Same-surface open PRs | `gh pr list --state open --limit 100 --json number,headRefName,files` filtered to `.ai-dev-workflow.yaml`, `sync-manifest.yaml`, `workflow-lib.sh`, the workflow README, `README.md`, `template/`, `design/` (2026-11-25) | no open PR touches these surfaces |
| V18 | Vault target | `git -C /Users/lhpaul/Git/Cerebro/LH log --oneline -1` and `grep -n '^#' '40 - Conocimiento/Estándares/HTML Mockup Framework.md'` (2026-11-25) | repo `lhpaul/lh-cerebro`, branch `main`, head `b05bb0a`; headings listed in L8's mapping table; other vault files have uncommitted edits, the target file does not |
| V19 | Path-limited commit semantics (L8 step 4) | in a scratch repository with committed files `a` and `b`: modify both, `git add b`, then `git commit --only -m x -- a`; inspect `git show --stat HEAD` and `git diff --cached --name-only` (2026-11-25) | the commit lists only `a`; `b` remains staged and uncommitted |

### Search commands

The searches whose regular expressions contain alternation are recorded here,
outside the table, so no Markdown escaping alters them. Run from the
repository root.

```bash
# S-V2
grep -n '^mode:' .ai-dev-workflow.yaml
# S-V3 (rev d8b9f005), then the control search
git grep -n -E 'workflow_design|design_opt_in|design\.(root|home|kind)|get\(.design.\)' d8b9f005 -- scripts/ .github/ ':!*.md'
git grep -c -E 'workflow_template|is_template' d8b9f005 -- scripts/development-workflow/workflow-lib.sh
# S-V4 (rev d8b9f005)
git ls-tree --name-only d8b9f005 | grep -x -E 'design|template'
git ls-tree --name-only d8b9f005 template/
```

### Reader probe

Illustrative; re-run from any scratch directory with `python3 -B probe.py`.

```python
# Illustrative probe used for V10 — not shipped.
import importlib.util
from pathlib import Path
spec = importlib.util.spec_from_file_location(
    "wcr", "<repo>/scripts/development-workflow/workflow-config-resolver.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
for raw in ["design:\n", "design:\n  root: 42\n  home: product\n  kind: reproduction\n",
            "design:\n  home: [unclosed\n", "- a\n"]:
    try:
        print(m.validate_selected_yaml(raw, Path(".ai-dev-workflow.yaml")).get("design"))
    except Exception as exc:
        print(type(exc).__name__)
```

---

## Factual claim evidence

**Rule 1**: does not fire; see the PR's per-rule outcome record.

**Rule 6 — scoped obligations.** Each conditional obligation in this plan,
with its governed scope and discharge point:

| ID | Obligation | Governed scope | Discharged at |
| --- | --- | --- | --- |
| S1 | The template-repository assertion runs only when `workflow_template_is_template` returns `true` | the single in-repository assertion in the new suite that reads this repository's own `.ai-dev-workflow.yaml` (AC11) | L5 test T-template; skipped with a printed reason in consumers |
| S2 | The fallback prints row 1 or row 2 when the inline program cannot produce an outcome | every call of `workflow_design_opt_in` where `python3` is missing, or the program exits non-zero or prints no `DESIGN_OPT_IN=` first line | L4 helper body; L5 tests T-fallback-absent and T-fallback-present |
| S3 | A permission-denied file is tested only when the suite does not run as root | the single unreadable-file case in L5 | L5 test T-unreadable, skipped with a printed reason when `id -u` is 0 |
| S4 | If the vault target file has uncommitted changes before L8 starts, stop and ask the vault owner | the file `40 - Conocimiento/Estándares/HTML Mockup Framework.md` only; other dirty vault files are left untouched and never block | L8 step 1 |
| S5 | If the implementing role cannot write to the vault path, stop with `STAGE_ROLE_TOOL_OR_PATH_DENIED:` (Protocol 91) | L8 steps 2 to 5 | L8 step 2 |
| S6 | Two links must resolve once the implementation PR is merged | the URL in the vault header (L8) and the reference page's scaffold URL (P7) | smoke runbook Step 10 (post-merge) |
| S7 | If the implementation PR is reverted, the vault commit is reverted in the same change window | the single L8 vault commit | the revert itself (Risks & Mitigations, "Reversal") |
| S8 | Once a later item consumes the helper or a consumer writes a `design` block, reversing the contract is that later item's responsibility | reversal of the P3 contract and the `design` block after first consumption | the later item's own plan (#2209, #2212, #2213, #2210, #2208 or #2214) |
| S9 | The AC15 "after" full run must be taken at the final PR head; a commit pushed after it requires a new "after" run | every implementation-branch commit after the recorded run | Implementation Order step 14, before the implementation PR gets `ready-for-human-review` |

---

## Cross-Cutting Operational Assumption Check

### Applicable

| Assumption surface | Recorded value | Authoritative source | Verified at | Bounded cross-check scope | Result |
| --- | --- | --- | --- | --- | --- |
| Artifact owner and approved base | this repository, `develop` | `.ai-dev-workflow.yaml` (no `mode`, V2), `AGENTS.md` Git & Branching | 2026-11-25, `d8b9f005` | this invocation (#2211 only) and same-surface open PRs (V17: none) | `Verified` |
| Sync classification of every touched path | V7 | `sync-manifest.yaml` via `select-sync-manifest-entries.py` | 2026-11-25, `d8b9f005` | same as above | `Verified` |
| Template-owned comment block of the configuration file | V6 | `.ai-dev-workflow.yaml` markers | 2026-11-25, `d8b9f005` | same as above | `Verified` |
| Vault target repository and file | V18 | the vault checkout | 2026-11-25, vault `b05bb0a` | this invocation only; no PR exists for the vault | `Verified` |

At implementation start, re-run V7 and V17; a changed result is
`Stale or conflicting` and stops implementation before file edits.

---

## Layer-by-Layer Changes

### L1 — Framework reference page (`docs/workflow/development-workflow/mockup-framework.md`, new) (AC1 to AC6)

Sections, in this order. Wording is the implementer's; the facts come from the
spec rules named, not restated here.

1. **Status and ownership** — the page is the canonical contract (BR17); the
   vault standard keeps rationale and history.
2. **Design tree** — the tree with every path AC1 names, under the default
   root `design/`, and the sentence that a configured `design.root` relocates
   the whole tree (BR9).
3. **Repository types** — the BR9 table with the three display names, and the
   literal rule "choose one layout per repository; do not mix them" (AC2).
4. **Mockup kinds and tokens** — Home and Kind tables with code values and
   display labels from the spec's Statuses section; the BR10 token rule for
   each kind (AC3); kind precedence per BR8 and D4.
5. **Source-of-truth hierarchy** — BR11 in order, then the inversion for a
   reproduction (AC4).
6. **README sections** — Framework and Project sections per BR12, delimited by
   the `<!-- TEMPLATE-OWNED-START -->` / `<!-- TEMPLATE-OWNED-END -->` markers
   already used by `sync-manifest.yaml`'s `html_comments` scheme, with the
   Project section after the end marker.
7. **Opting in** — the `design` block (BR4 example, BR5, BR6, the default
   root), the opt-in resolution table and the three outcomes, BR1 (stages gate
   on the block, never on prose), BR18, and how a stage reads the outcome:
   source `workflow-lib.sh` and call `workflow_design_opt_in`, with the P3
   output lines. The usage snippet carries
   `<!-- workflow-shell-contract: bash -->` because sourcing the library needs
   Bash; it does not iterate or split arguments, so no Bash/zsh behavioural
   evidence is required.
8. **Starting from the scaffold** — the P7 link and path to the P1
   location, the copy step, keeping one layout, and that copying does not opt
   a project in (UC2).
9. **Forthcoming** — names #2206 (manifest contract and verify script), #2207
   (viewer and shell), #2208 (setup) and #2214 (adoption) as forthcoming
   without describing their content (AC6).

All repository-type names, kind names and outcome labels use the spec's
display labels (UX rules); the default root is stated wherever the root is
mentioned.

### L2 — Scaffold (`template/design-scaffold/design/`, new) (AC7 to AC10)

| File | Content |
| --- | --- |
| `README.md` | `## Framework` inside the template-owned markers (what the design root holds, one layout per repository, token rule by kind, pointer to the reference page by code-span path), then `## Project` with guidance only (product name, chosen repository type, home and kind, app list) |
| `tokens.json` | valid JSON with a top-level `"$description"` stating the values are examples to replace, plus a few example colour, font and spacing tokens |
| `mockups/README.md` | `## Framework` inside the markers (per-app folders or a single mockups folder, `shared/` reserved for viewer assets from #2207, English structure and product-language content), then `## Project` with guidance only (screen inventory placeholder) |
| `mockups/shared/.gitkeep` | empty; keeps the reserved shared folder |
| `mockups/example-app/.gitkeep` | empty; the example per-app folder |

No HTML, JavaScript, manifest or image files (AC10). Structure text is English
(UX rules). The Framework sections summarise and point to L1; they must not
contradict it.

### L3 — Commented design block in `.ai-dev-workflow.yaml` (AC11)

Insert, before line 46 (`# <!-- TEMPLATE-OWNED-END -->`), a commented block:
one sentence saying the block is the only opt-in record, absent means not
opted in, and the reference page path; then the BR4 example with every line
prefixed `#`. No uncommented key is added, so the template stays not opted in
(BR14). No other line of the file changes.

### L4 — Read helper in `scripts/development-workflow/workflow-lib.sh` (AC12 to AC15)

- Add `workflow_design_opt_in [repo_root]` with a header comment that names
  the spec, the P3 contract and the P4 source rule. Implement per P2, P4, P5
  and P6.
- Place it after `workflow_template_is_template` (the other `template`/opt-in
  style reader) so related readers stay together.
- Bash 3.2 compatible: no associative arrays, `mapfile` or `readarray`.
- Additive only: no existing line of `workflow-lib.sh` is changed or removed,
  so no existing helper changes output (AC15). The check is
  `git diff --numstat origin/develop -- scripts/development-workflow/workflow-lib.sh`
  showing 0 deleted lines.
- Sync: `workflow-lib.sh` and `workflow-config-resolver.py` already ship
  together to every role (V7), so the helper's dependency is always present
  where the helper is.

### L5 — Test suite (`scripts/development-workflow/tests/test-workflow-design-opt-in.sh`, new)

- Header: `# covers: scripts/development-workflow/workflow-lib.sh`,
  `# covers: scripts/development-workflow/workflow-config-resolver.py`, and a
  `# duration:` line measured locally (V13).
- Each case writes a fabricated `.ai-dev-workflow.yaml` into a fresh
  `mktemp -d` repository, sources `workflow-lib.sh`, calls
  `workflow_design_opt_in "$repo"`, and compares the full stdout and exit
  status. Cases are listed in **Testing Strategy**.
- The suite reads no scaffold file, so the sync coverage check stays clean
  (V9); scaffold checks live in the smoke runbook.

### L6 — Pointers

- `docs/workflow/development-workflow/README.md`: in the reference list's
  `### Design Assets` subsection, add a bullet for `mockup-framework.md`; in
  the `.ai-dev-workflow.yaml` bullet under `### Tooling And Configuration`,
  add `design` to the listed keys.
- `README.md` (repository): in the `## Repository Structure` tree, add
  `mockup-framework.md` under `development-workflow/` and a `template/` node
  listing `design-scaffold/`, `product-repo-injection/` and `workflow-hub/`.

### L7 — Sync manifest

No change (P1). Classification of every new or changed path, from V7:

| Path | Category and scope | Effect on a consumer without a design block |
| --- | --- | --- |
| `docs/workflow/development-workflow/mockup-framework.md` | always_sync, `hub_only` (directory glob) | new doc; no behaviour change |
| `docs/workflow/development-workflow/README.md` | always_sync, `hub_only` | pointer text only |
| `scripts/development-workflow/workflow-lib.sh` | always_sync, `product_repo_injection` (all roles) | additive function; nothing calls it yet |
| `scripts/development-workflow/tests/test-workflow-design-opt-in.sh` | always_sync, `hub_only` | new suite; its template-only assertion is gated (S1) |
| `.ai-dev-workflow.yaml` | project_specific, mixed content | template-owned comment text only; values untouched |
| `README.md` | project_specific | never overwritten |
| `template/design-scaffold/**` | not in the manifest | never synced; no design tree created (BR13) |
| `docs/testing/workflow/2211-mockup-framework-layout.smoke-test.md` | not in the manifest | not synced, like most per-item runbooks |

### L8 — Vault standard (`/Users/lhpaul/Git/Cerebro/LH/40 - Conocimiento/Estándares/HTML Mockup Framework.md`, other repository) (AC17, AC18)

Not part of the template PR diff. Run after L1 is committed, so the linked
page's content is final.

1. Precondition (S4): `git -C /Users/lhpaul/Git/Cerebro/LH status --porcelain -- '40 - Conocimiento/Estándares/HTML Mockup Framework.md'`
   prints nothing.
2. Access (S5): the edit needs write access to the vault path.
3. Edit, per this mapping:

   | Vault section | Treatment |
   | --- | --- |
   | Header blockquote ("Future: migrate…") | replace with: the template is canonical for the contract, and a link to `https://github.com/lhpaul/ai-dev-framework-template/blob/develop/docs/workflow/development-workflow/mockup-framework.md`; keep the reference implementations line |
   | "Copy the Framework sections…" paragraph | pointer to the template's README-sections rule |
   | Where mockups live | keep; mark as moving with #2208 / #2214 (home decision) |
   | Purpose | keep (rationale) |
   | Two kinds of mockup | keep the rationale; add a pointer for kind values and token rules |
   | Repository types, Layout | replace with a pointer (layout and repository types) |
   | Viewer frame modes, Full-bleed viewer with edge drawers and sub-sections, `viewer.js` integration | keep; mark as moving with #2207 |
   | Manifest and sub-sections | keep; mark as moving with #2206 |
   | Tokens | replace the rules with a pointer; keep the measured Leasity comparison and harvesting notes as rationale |
   | Tooling (optional) | keep; mark the verify part as moving with #2206 |
   | Source-of-truth hierarchy | replace with a pointer; keep the "the gate's whole claim" reasoning as rationale |
   | Fidelity gate and sub-sections | keep; mark as not in the template (design-intent comparison moves with #2216; reproduction gates stay out of #1470 scope) |
   | Optional extensions, Framework phases, Anti-patterns | keep |
   | Bootstrap checklist | keep; mark as moving with #2208 |
   | Framework changelog | keep; add a dated row recording the move of the contract to the template (#2211) |

   Also update the front-matter `updated:` date.
4. Commit only that file with a path-limited commit, which records only the
   named path and leaves anything else already staged in the vault's index
   staged and uncommitted:
   `git -C /Users/lhpaul/Git/Cerebro/LH commit --only -m '<message naming #2211>' -- '<file>'`
   (no `git add` and no bare `git commit`). Confirm with
   `git -C /Users/lhpaul/Git/Cerebro/LH show --stat HEAD` that the commit
   lists only that file. Do not push; pushing the vault is left to its owner,
   and the PR description records whether it was pushed.
5. Record in the implementation PR description (AC18): the file path, a
   one-paragraph summary, the vault commit SHA and its push state.

---

## Testing Strategy

**Test types**: automated shell suite (L5); manual smoke runbook; CI
(`workflow-tests` selects the suite through its `# covers:` header, markdown
lint, shell snippet lint).

**Parser-risk classification**: applies. The helper applies a rule table to
parsed configuration (P5). It adds no grammar of its own: parsing is the
existing resolver reader (P2). The edge-case enumeration below maps each case
to a test in `test-workflow-design-opt-in.sh`. Suppression directives: none.

**Binding enumeration** — the AC12 cases, which the spec lists by name; each
asserts the full P3 output:

| Test | Input | Expected |
| --- | --- | --- |
| T1 | no configuration file | `not_opted_in` |
| T2 | unparseable (unclosed flow sequence) | `invalid`, one `configuration` problem, no file content echoed |
| T3 | no `design` key | `not_opted_in` |
| T4 | `design:` with no value | `invalid`, one `design` problem |
| T5 | missing home | `invalid`, `design.home` absent |
| T6 | unknown home (`studio`) | `invalid`, `design.home` names `"studio"` and the accepted values |
| T7 | missing kind | `invalid`, `design.kind` absent |
| T8 | unknown kind (`mock`) | `invalid`, `design.kind` names the value |
| T9 | wrong-case value (`Knowledge`) | `invalid`, `design.home` |
| T10 | absolute root (`/srv/design`) | `invalid`, `design.root` |
| T11 | root outside the repository (`../design`) | `invalid`, `design.root` |
| T12 | numeric root (`root: 42`) | `invalid`, `design.root` says not a string |
| T13 | list root (`root: [design]`) | `invalid`, `design.root` says a list, content not echoed |
| T14 | valid, no root | `opted_in`, `DESIGN_ROOT=design/`, `DESIGN_ROOT_SOURCE=default`, labels |
| T15 | valid, custom root (`docs/design/`) | `opted_in`, `DESIGN_ROOT=docs/design/`, `configured` |
| T16 | valid plus unknown field | `opted_in`, same as T14 |
| T17 | block only in `.ai-dev-workflow.local.yaml` | `not_opted_in` |

Indicative cases (coverage intent: every P5 row boundary, every lookalike that
must not match, the fallback paths, and the AC13 to AC15 and BR16/BR18
guarantees; an equivalent set may replace them):

| Test | Edge class | Input | Expected |
| --- | --- | --- | --- |
| T-multi | several problems (AC13) | unknown home, missing kind, absolute root | `DESIGN_PROBLEM_COUNT=3`, home, kind, root in that order, each with value-or-absent and accepted values |
| T-null-forms | row 4 variants | `design: null`, `design: {}`, `design: []`, `design: yes` | `invalid`, `design` |
| T-key-case | lookalike key | `Home: knowledge` only | `design.home` absent |
| T-quoted | quoting and comments | `home: "knowledge"`, `kind: 'design-intent'  # note` | `opted_in` |
| T-flow | flow mapping | `design: {home: product, kind: reproduction}` | `opted_in` |
| T-padded | boundary whitespace inside quotes | `home: "knowledge "` | `invalid`, `design.home` |
| T-root-forms | root boundaries | `root: null`, `root: ''`, `root: true`, nested mapping, `root: C:/design`, `root: design/../..`, `root: ..\design` | `invalid`, `design.root` |
| T-root-inside | root normalisation | `root: ./design`, `root: design/../mocks`, `root: .`, `root: '  '` (non-empty per BR6) | `opted_in`, root printed as configured |
| T-quoted-42 | numeric lookalike | `root: "42"` | `opted_in` |
| T-control | output escaping (P3) | roots containing a tab, LF, CR, DEL and a C1 control (double-quoted YAML escapes), and a backslash | one physical line each, escaped as `print_kv_escaped` would (`\t`, `\n`, `\r`, `\x7f`, `\u0085`, `\\`) |
| T-truncate | detail length (P3) | an unknown home of exactly 80 characters, and one of 81; a valid block whose root is 120 characters | the 80-character value is echoed whole; the 81-character value is cut to 80 plus `…`; the 120-character root is printed whole in `DESIGN_ROOT` |
| T-locale | output encoding (P3) | a valid block with a non-ASCII root, run under `LC_ALL=C` | `opted_in`, root printed as UTF-8 |
| T-dup | duplicate key | `home` twice | `invalid`, `configuration` |
| T-toplevel | top level not a mapping | `- a` | `invalid`, `configuration` |
| T-empty | empty and comment-only files | `''`, `# x` | `not_opted_in` |
| T-nested | `design` not at top level | `template:` with a nested `design:` | `not_opted_in` |
| T-commented | commented block | every line of a valid block prefixed `# ` | `not_opted_in` |
| T-dir / T-symlink / T-bytes | row 2 capture failures | directory at the path; dangling symlink; invalid UTF-8 | `invalid`, `configuration` |
| T-unreadable | permission (S3) | mode `000` file | `invalid`, `configuration` |
| T-env | BR18 overrides | `AI_DEV_WORKFLOW_CONFIG_FILE` and `WORKFLOW_LOCAL_REVIEW_OVERRIDE_ROOT` pointing at files with a valid block, repository without one | `not_opted_in` |
| T-local-override | BR18, opposite direction | versioned valid block, local file with a different home | versioned values |
| T-fresh | BR16 | call, edit the file, call again | outcome follows the edit |
| T-unchanged | AC14 | a sorted `find` listing plus `cksum` of every file in the scratch repository, and the set of `__pycache__` entries under the scripts directory, before and after all calls | identical |
| T-fallback-absent / T-fallback-present | S2 | `PATH` without `python3`, no file / with a valid file | `not_opted_in` / `invalid` whose `configuration` problem says the check could not run and the file may be valid (P6) |
| T-badarg | caller error | `workflow_design_opt_in ""`, a non-directory path, and no argument with `workflow_repo_root` stubbed to fail | exit 2, empty stdout |
| T-template | S1, AC11 | this repository's own config | `not_opted_in` |

**Proportionality (Gate B)**: one suite against one helper; the binding rows
are the spec's own list, and the indicative rows each cover a P5 boundary or a
spec guarantee. Scaffold and documentation are checked by smoke steps, not by
a custom matcher.

**AC15 evidence**: AC15 covers every suite that passed before the change,
not only the suites a pull request selects, so the evidence is two full runs
of the existing `workflow-tests.yml`, triggered by `workflow_dispatch` (which
runs `select-test-suites.sh --all`; no workflow file is edited):

1. Baseline: `gh workflow run workflow-tests.yml --ref develop` while
   `develop` is still at the implementation branch's merge-base (or reuse a
   completed full run whose head is that merge-base). Record the run URL and
   its passing suites.
2. After: `gh workflow run workflow-tests.yml --ref <implementation branch>`
   at the final PR head, after the branch's last commit (S9). Every suite
   that passed in the baseline must pass; a suite
   that failed in the baseline is listed with its baseline failure and is not
   attributed to this change.
3. Record both run URLs and the comparison in the implementation PR
   description.

The suites selected for the change set are also run locally during
implementation (Implementation Order step 9), and the L4 numstat check shows
no existing line of `workflow-lib.sh` changed.

**AC16 evidence**: the L7 table, and smoke runbook Step 8 (disposable
consumer).

**Smoke test runbook**: `docs/testing/workflow/2211-mockup-framework-layout.smoke-test.md`

**Regression suite**: none applies; the repository's e2e project is a
placeholder.

---

## Seed Data

None. Every test and smoke step builds fabricated configuration in a
`mktemp -d` directory; no real `.ai-dev-workflow.local.*` file is read or
written.

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/README.md` — L6.
- [ ] `README.md` — L6.
- `AGENTS.md`, `docs/README.md`, `docs/project/*`, `docs/best-practices/*`:
  none. The workflow README index carries the pointer AC1 requires;
  `docs/README.md` links to that index and is not synced to consumers.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| A syntax error in `workflow-lib.sh` breaks every script that sources it | Low | High | `bash -n` and `shellcheck` before commit; the selected suites (AC15) all source the library |
| A resolver refactor renames `capture_config_text` or `validate_selected_yaml` | Low | Medium | the suite covers the resolver file, so such a change runs it; P6 fails closed meanwhile |
| Echoed values leak sensitive text | Low | Low | only the three design fields are echoed, from the versioned file, escaped and truncated (P3); local configuration is never read (P4) |
| Consumers see a broken link to the unsynced scaffold | Medium if linked relatively | Low | P7 absolute upstream link plus code-span path |
| The vault link points at `develop` before the PR merges | High until merge | Low | S6 post-merge check |
| Vault edit swept up with unrelated dirty vault files | Medium | Medium | L8 commits by explicit path and checks `show --stat` |

### Reversal

Every template change in this item is additive and leaves no state behind:
no configuration value, migration, sync-state entry or consumer file depends
on it, and no stage calls `workflow_design_opt_in` until #2209, #2212, #2213 or
#2210 land. Reverting the implementation PR's squash commit on `develop`
therefore restores the previous behaviour. A consumer that synced in between
keeps an unused reference page, helper and suite, which change no behaviour;
the next sync offers their removal or update like any other framework file.

The vault commit is reversed with `git -C /Users/lhpaul/Git/Cerebro/LH revert <vault-sha>`,
under S7, so the vault never points at a reference page that no longer exists
on `develop`. After first consumption of the contract, S8 governs reversal.

---

## Code Samples

```bash
# Illustrative — adapt during implementation. Shape of the helper only.
workflow_design_opt_in() {
  local repo_root config out
  local program='
# inline program: load the resolver by path (sys.argv[1]), read sys.argv[2],
# apply P5 and print the P3 lines
'
  if [ "$#" -gt 0 ]; then
    [ -n "$1" ] && [ -d "$1" ] || return 2
    repo_root="$1"
  else
    repo_root="$(workflow_repo_root)" || return 2
  fi
  config="$repo_root/.ai-dev-workflow.yaml"
  if have_cmd python3 &&
     out="$(python3 -I -B -c "$program" "$(workflow_config_resolver_script)" "$config")" &&
     [ "${out%%=*}" = "DESIGN_OPT_IN" ]; then
    printf '%s\n' "$out"
  elif [ -e "$config" ] || [ -L "$config" ]; then
    printf '%s\n' 'DESIGN_OPT_IN=invalid' 'DESIGN_OPT_IN_LABEL=Invalid configuration' \
      'DESIGN_PROBLEM_COUNT=1' \
      'DESIGN_PROBLEM=configuration: the opt-in check could not run (python3 or the configuration reader failed); the file may be valid'
  else
    printf '%s\n' 'DESIGN_OPT_IN=not_opted_in' 'DESIGN_OPT_IN_LABEL=Not opted in'
  fi
}
```

---

## Implementation Order

Commit after each numbered step that leaves the tree coherent.

1. Re-run V7 and V17 (operational assumption check); stop on a change.
   Take the AC15 baseline full run (Testing Strategy, "AC15 evidence"
   item 1) while `develop` is at the branch's merge-base.
2. L4 helper. Run `bash -n` and `shellcheck` on `workflow-lib.sh`.
3. L5 suite; run it until it passes, then record its `# duration:`.
4. L3 commented block; confirm T-template still passes and that
   uncommenting the example in a scratch copy yields `opted_in` (smoke Step 5).
5. L1 reference page.
6. L2 scaffold.
7. L6 pointers.
8. Lint: `npx markdownlint-cli2` on the new and changed Markdown (including
   the scaffold READMEs, outside CI scope per V14),
   `python3 scripts/lint/markdown-heuristic-lint.py` on the same files, and
   `python3 scripts/lint/workflow-shell-snippet-lint.py --base-ref origin/develop`.
9. Run the selected suites locally; `python3 -B scripts/development-workflow/check-sync-manifest-coverage.py`
   must print `RESULT=clean`.
10. Changelog fragment `changelog.d/2211.added.mockup-framework-layout.md`:

    ```markdown
    - **Mockup framework layout and design opt-in key** (#2211): the template now holds the HTML Mockup Framework contract in `docs/workflow/development-workflow/mockup-framework.md` (design tree, repository types, token rules, README sections, source-of-truth hierarchy), ships an opt-in starter tree under `template/design-scaffold/` that sync never copies, documents an inactive `design:` block in `.ai-dev-workflow.yaml`, and adds `workflow_design_opt_in` to `workflow-lib.sh`, which reports Not opted in, Opted in or Invalid configuration from the versioned configuration only.
    ```

11. L8 vault edit and commit (steps 1 to 4).
12. Open the implementation PR (or update its description) and record the
    vault change there (L8 step 5, AC18).
13. Run the smoke runbook Steps 1 to 6, Part A of Step 7, and Steps 8 and
    9; Step 9 reads the vault commit and the PR description record made in
    steps 11 and 12.
14. With every implementation commit pushed, take the AC15 "after" full run
    at the final PR head, update the PR description's AC15 record with the
    comparison ("AC15 evidence" items 2 and 3; a description edit, not a
    commit, so S9 still holds), then run Part B of smoke Step 7.
