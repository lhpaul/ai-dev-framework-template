# Smoke Test Runbook: Mockup framework layout and design opt-in key

**Feature**: Mockup framework reference, opt-in design scaffold, commented
`design` block and the `workflow_design_opt_in` helper (#2211)
**Spec**: [1_2211-mockup-framework-layout_specs.md](../../specs/developments/20261125124423_2211-mockup-framework-layout/1_2211-mockup-framework-layout_specs.md)
**Plan**: [2_2211-mockup-framework-layout_implementation-plan.md](../../specs/developments/20261125124423_2211-mockup-framework-layout/2_2211-mockup-framework-layout_implementation-plan.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

- [ ] A checkout of this repository on the implementation branch, with
  `python3` and Bash available.
- [ ] A scratch directory from `mktemp -d` for every configuration variant.
  Never edit this repository's real `.ai-dev-workflow.yaml` or any
  `.ai-dev-workflow.local.*` file.
- [ ] For Step 9: read access to the vault checkout
  `/Users/lhpaul/Git/Cerebro/LH`.

No application is started; no design assets exist for this item (no
`## Design assets` section in #2211 and no `assets/` folder in the
development folder), so this runbook has no design-fidelity step.

---

## Test Data

| Item | Value |
| --- | --- |
| Reference page | `docs/workflow/development-workflow/mockup-framework.md` |
| Scaffold | `template/design-scaffold/design/` |
| Helper | `workflow_design_opt_in` in `scripts/development-workflow/workflow-lib.sh` |
| Helper suite | `scripts/development-workflow/tests/test-workflow-design-opt-in.sh` |
| Vault file | `/Users/lhpaul/Git/Cerebro/LH/40 - Conocimiento/Estándares/HTML Mockup Framework.md` |

---

## Smoke Test Steps

### Step 1: Reach the reference from the index

**Maps to**: AC1

1. Open `docs/workflow/development-workflow/README.md` and follow the
   mockup framework bullet.
2. Read the design tree section.

**Expected result**: the link opens the reference page; the tree shows
`design/README.md`, `design/tokens.json`, `design/mockups/README.md`,
`design/mockups/shared/` and `design/mockups/<app>/` under the default root
`design/`, and says a configured root relocates the whole tree.

### Step 2: Repository types

**Maps to**: AC2

1. Read the repository types section.

**Expected result**: three types (Monorepo apps, Single app, Knowledge repo)
with mockup locations `design/mockups/<app>/`, `design/mockups/`,
`design/mockups/<app>/` and token links `../../tokens.json`,
`../tokens.json`, `../../tokens.json`; the text "choose one layout per
repository; do not mix them" is present.

### Step 3: Tokens, hierarchy, opt-in block, forthcoming parts

**Maps to**: AC3, AC4, AC5, AC6

1. Read the kinds and tokens, source-of-truth, opting-in and forthcoming
   sections.

**Expected result**:

- Design intent mirrors the token file in the mockup's root style block in
  the same commit; a reproduction harvests the running app's stylesheet and
  does not mirror the token file.
- The hierarchy reads: product specifications, token file and design-system
  screens, product mockup screens, design tool, production code; and it is
  inverted for a reproduction.
- The opt-in section shows the three fields, the accepted values with display
  labels, the default root `design/`, the resolution table, the three
  outcomes, and the rule that stages gate on the block, never on prose.
- #2206, #2207, #2208 and #2214 are named as forthcoming and not described.

### Step 4: Scaffold shape

**Maps to**: AC7, AC8, AC9, AC10

```bash
git ls-files template/design-scaffold
test ! -e design && echo "no live design tree"
python3 -m json.tool template/design-scaffold/design/tokens.json >/dev/null && echo "tokens valid"
git ls-files template/design-scaffold | grep -E '\.(html?|js|mjs|png|jpe?g|svg)$|manifest' || echo "no screens, manifest or viewer code"
```

Then open both scaffold READMEs, and in the reference page find the
scaffold link.

**Expected result**: the listing shows the design README, token file,
mockups README, `mockups/shared/` and one example per-app folder; the three
echo lines print; each README has `## Framework` inside the template-owned
markers followed by `## Project` holding only guidance; the token file (or
the design README's Project section) says the values are examples to
replace; the reference page links to the scaffold with the absolute URL
`https://github.com/lhpaul/ai-dev-framework-template/tree/develop/template/design-scaffold/design`
(no relative link) and names the path `template/design-scaffold/design/`.

### Step 5: Template stays not opted in; the documented example is valid

**Maps to**: AC11

```bash
bash -c 'source scripts/development-workflow/workflow-lib.sh; workflow_design_opt_in'
```

Then copy the commented example from the template-owned header of
`.ai-dev-workflow.yaml` into `<scratch>/.ai-dev-workflow.yaml`, remove the
comment prefix, and run
`bash -c 'source scripts/development-workflow/workflow-lib.sh; workflow_design_opt_in "$1"' _ <scratch>`.

**Expected result**: the first call prints `DESIGN_OPT_IN=not_opted_in`;
the example sits between the `TEMPLATE-OWNED-START` and `END` markers; the
scratch call prints `DESIGN_OPT_IN=opted_in` with the example's home and
kind.

### Step 6: Outcome cases

**Maps to**: AC12, AC13, AC14

1. Run `bash scripts/development-workflow/tests/test-workflow-design-opt-in.sh`.
2. In a scratch repository, write a block with home `studio`, no kind and
   root `/srv/design`, and call the helper on it.

**Expected result**: the suite ends with zero failures; the manual call
prints `DESIGN_OPT_IN=invalid`, `DESIGN_PROBLEM_COUNT=3`, and three
`DESIGN_PROBLEM=` lines for `design.home`, `design.kind` and `design.root`,
each naming the value found or that it is absent, and the accepted values.

### Step 7: Existing suites unchanged

**Maps to**: AC15

**Part A — local, before the final push** (plan Implementation Order step 13):

```bash
SCRATCH="$(mktemp -d)"
git diff --name-only origin/develop...HEAD > "$SCRATCH/changed.txt"
bash scripts/development-workflow/select-test-suites.sh --changed-files "$SCRATCH/changed.txt"
git diff --numstat origin/develop -- scripts/development-workflow/workflow-lib.sh
```

Run every listed suite.

**Part B — full runs, after the final push** (plan Implementation Order
step 14): open the two full `workflow-tests` runs the implementation PR
description records (baseline on `develop` at the merge-base, and after on
the final implementation branch head, both started by `workflow_dispatch`).

**Expected result**: Part A: every selected suite passes and the numstat line
shows 0 deleted lines for `workflow-lib.sh`. Part B: every suite that passed
in the baseline full run also passes in the after full run, the after run's
head equals the PR head, and CI `workflow-tests` is green on the PR.

### Step 8: Sync into a disposable consumer

**Maps to**: AC16

1. Print the classification:
   `python3 -B scripts/development-workflow/select-sync-manifest-entries.py --manifest sync-manifest.yaml --role single_repo`
   and confirm each changed path matches the plan's L7 table (no entry for
   `template/design-scaffold/`).
2. Create a consumer: `git init` a scratch directory, copy
   `.ai-dev-workflow.yaml` from `origin/develop` into it with
   `template.is_template` set to `false`, and copy
   `scripts/development-workflow/workflow-config-resolver.py` from
   `origin/develop` (every role already has it, since it ships with
   `workflow-lib.sh`; plan V7); commit.
3. Apply only what sync would: copy the always-sync changed files (the
   reference page, the workflow README, `workflow-lib.sh`, the new suite)
   into the same paths, and replace only the lines between the consumer's
   `TEMPLATE-OWNED-START` and `END` markers with the branch's header block.
4. In the consumer, run `git diff -- .ai-dev-workflow.yaml`,
   `test ! -e design && echo "no design tree"`, and
   `bash -c 'source "$1/scripts/development-workflow/workflow-lib.sh"; workflow_design_opt_in "$1"' _ <consumer>`.

**Expected result**: the configuration diff touches only comment lines inside
the template-owned header; no `design/` directory exists; the helper prints
`DESIGN_OPT_IN=not_opted_in`.

### Step 9: Vault standard

**Maps to**: AC17, AC18

1. `git -C /Users/lhpaul/Git/Cerebro/LH show --stat <vault-sha>` using the SHA
   recorded in the implementation PR description.
2. Open the vault file.

**Expected result**: the commit lists only the vault file; its header names
the template as canonical and links to the reference page; layout,
repository types, tokens, README sections and the source-of-truth hierarchy
are pointers; rationale and the framework changelog remain, with a new dated
row; manifest, viewer and shell, bootstrap checklist and fidelity gate
sections remain and are marked with their item; the PR description records
the file, a summary, the commit and its push state.

### Step 10: Post-merge link check

**Maps to**: AC17, Use Case 1

1. After the implementation PR merges, open the vault header link.
2. Open the reference page's scaffold link.

**Expected result**: the vault link resolves to the reference page on
`develop`; the scaffold link resolves to `template/design-scaffold/design/`
on `develop`.

---

## Assertions Checklist

- [ ] AC1: reference reachable from the workflow index with the full tree
- [ ] AC2: three repository types, paths, token links and the one-layout rule
- [ ] AC3: token rule for each kind
- [ ] AC4: hierarchy and its inversion
- [ ] AC5: design block, values, labels, default root, table, gate-on-block rule
- [ ] AC6: later parts named as forthcoming only
- [ ] AC7: scaffold present, no live design tree at the root
- [ ] AC8: Framework then Project sections in each scaffold README
- [ ] AC9: valid JSON token file marked as examples
- [ ] AC10: no screens, manifest or viewer code
- [ ] AC11: commented example in the template-owned header; template not opted in
- [ ] AC12: every listed case returns its resolution-table outcome
- [ ] AC13: several problems reported together with field, value and accepted values
- [ ] AC14: repository unchanged by the check
- [ ] AC15: previously passing suites still pass; no existing helper changed
- [ ] AC16: sync into a consumer creates no design tree and changes only comments
- [ ] AC17: vault points to the template and keeps rationale and history
- [ ] AC18: PR description records the vault change

---

## Seed Data Reference

None; every variant is fabricated in a scratch directory.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Helper prints `invalid` with a `configuration` problem for a file that looks valid | tabs for indentation, a duplicate key, or non-UTF-8 bytes | fix the YAML; the strict reader rejects these |
| Helper prints nothing and exits 2 | the repository argument is empty or not a directory | pass an existing directory |
| `check-sync-manifest-coverage.py` reports `UNCOVERED` for a scaffold path | a synced test reads the scaffold | move the check to this runbook (plan P1) |

---

## Known Limitations

- Step 8 simulates sync by hand for the files this item changes; it does not
  run the full template sync.
- Step 10 can only run after merge.
