# Smoke Test Runbook: Mockup manifest contract and verify script

**Feature**: Manifest section of the mockup framework reference and the
`mockup-manifest-verify.sh` tool (#2206)
**Spec**: [1_2206-mockup-manifest-contract_specs.md](../../specs/developments/20261126075749_2206-mockup-manifest-contract/1_2206-mockup-manifest-contract_specs.md)
**Plan**: [2_2206-mockup-manifest-contract_implementation-plan.md](../../specs/developments/20261126075749_2206-mockup-manifest-contract/2_2206-mockup-manifest-contract_implementation-plan.md)
**Created in**: Plan Ready stage

---

## Prerequisites

- [ ] A checkout of this repository on the implementation branch, with
  `python3` and Bash available.
- [ ] A scratch directory from `mktemp -d` for every variant. Never edit this
  repository's real `.ai-dev-workflow.yaml` or any `.ai-dev-workflow.local.*`
  file.

No application is started. No design assets exist for this item: #2206 has no
`## Design assets` section, and the development folder has no `assets/`. This
runbook therefore has no design-fidelity step.

---

## Test Data

| Item | Value |
| --- | --- |
| Reference page | `docs/workflow/development-workflow/mockup-framework.md` |
| Tool | `scripts/development-workflow/mockup-manifest-verify.sh` |
| Fixtures | `scripts/development-workflow/tests/fixtures/mockup-manifest-verify/` |
| Suite | `scripts/development-workflow/tests/test-mockup-manifest-verify.sh` |

Below, `FX` stands for the fixtures folder and `TOOL` for the tool path.

---

## Smoke Test Steps

### Step 1: Read the Manifest section

**Maps to**: AC1, AC2

1. Open the reference page and read its Manifest section.
2. Follow its link to the fixtures folder.

**Expected result**:

- The section documents:
  - the data-only file form;
  - the top-level, screen and state field tables, with requirements, values
    and value types;
  - the full set of fields a state must not carry;
  - the slug rule, the navigation shape, viewports and unknown fields;
  - the language rule and the `#screen=<screen_id>&state=<state_id>` link
    format;
  - token mirroring with its stated limitation;
  - the five-item checklist, with a statement that the verify script
    performs it.
- The fixtures link opens the fixture folder.

### Step 2: Forthcoming list

**Maps to**: AC3

1. Read the reference's "Forthcoming" section.

**Expected result**: #2206 is no longer listed; #2207, #2208 and #2214 are.

### Step 3: Verify the valid fixtures

**Maps to**: AC4, AC5, AC7

1. Run
   `bash TOOL manifest FX/design/mockups/intent-app/mockup-manifest.js --repo-root FX`.
2. Run the same for `FX/design/mockups/repro-app/mockup-manifest.js`.

**Expected result**: both print `MANIFEST_RESULT=conforms`,
`MANIFEST_RESULT_LABEL=Conforms`, `PROBLEM_COUNT=0`, and exit 0.

### Step 4: Invalid examples and no execution

**Maps to**: AC6, AC8, AC10

1. Run `manifest` on `FX/invalid-examples/function-wrapper.js` and on
   `object-literal.js`.
2. Run it on `several-problems.js`.
3. In a scratch directory, run it on a copy of `executes-on-load.js`, then
   list the directory.

**Expected result**:

- Steps 1 and 3 give `MANIFEST_RESULT=does_not_conform`, exit 1, with one
  `PROBLEM=BR1 manifest: not readable as data …` line.
- Step 2 lists several `PROBLEM=` lines. Each one has a rule, a place,
  `found …` or `absent`, and `expected …`.
- After step 3 the scratch directory holds only the copied file.

### Step 5: Tree check

**Maps to**: AC11, AC12

1. In this repository, run `bash TOOL tree`.
2. In a scratch Git repository with a valid `design` block (`home: product`,
   `kind: design-intent`), copy `FX/design` to `design/`, then run
   `bash TOOL tree --repo-root <scratch>`.
3. Make one subfolder of `design/mockups/` unreadable (`chmod 000`) and run
   it again. Restore the permissions afterwards.

**Expected result**:

- Step 1 gives `TREE_RESULT=not_opted_in`, exit 0.
- Step 2 gives `TREE_RESULT=conforms`, `MANIFEST_COUNT=2`, and no manifest
  from `shared/`.
- Step 3 gives `TREE_RESULT=does_not_conform`, with an `UNREADABLE_FOLDER=`
  line naming the folder, and both valid manifests still listed.

### Step 6: Inventory and citations

**Maps to**: AC13, AC14

1. Run `bash TOOL inventory FX/design/mockups/intent-app/mockup-manifest.js --repo-root FX`.
2. Run `resolve` on the same manifest with:
   - an existing `--screen`;
   - an existing `--screen` and `--state`;
   - an unknown `--screen`;
   - a `--state` that belongs only to another screen.
3. Run `resolve` on `FX/invalid-examples/several-problems.js`.

**Expected result**:

- Step 1 lists every screen and state id, exactly one
  `…_INITIAL=true` per screen with states, and `#screen=…&state=…` links.
- The four calls in step 2 give `resolves`, `resolves`,
  `does_not_resolve` with `unknown_screen`, and `does_not_resolve` with
  `unknown_state`.
- Step 3 gives `cannot_check` with `manifest_does_not_conform`.

### Step 7: Sync and regression

**Maps to**: AC15, AC17, AC18

1. Run `python3 -B scripts/development-workflow/check-sync-manifest-coverage.py`.
2. Run `bash scripts/development-workflow/tests/test-mockup-manifest-verify.sh`.
3. Copy the new and changed paths into a scratch consumer that has no
   `design` block, following the plan's L6 classification table, then run
   `bash TOOL tree --repo-root <consumer>` there.

**Expected result**:

- Step 1 prints `RESULT=clean`.
- Step 2 passes. Every case also asserts that its directory is unchanged.
- In step 3, no `design/` folder exists in the consumer, its configuration
  is unchanged, and the tree check prints `not_opted_in`.

### Step 8: Vault hand-off text

**Maps to**: AC19

1. Read the implementation PR description.

**Expected result**: it contains the two replacement texts from the plan's L5
section verbatim, and it states that the template owner applies them and that
the PR does not edit the vault.

---

## Assertions Checklist

- [ ] The reference documents the whole contract (Steps 1-2).
- [ ] Valid fixtures conform; invalid ones name every problem (Steps 3-4).
- [ ] Nothing in a manifest is executed (Step 4).
- [ ] The tree check follows the tree table, including unreadable folders
  (Step 5).
- [ ] The inventory and citations follow the citation table (Step 6).
- [ ] Sync is clean and the suite passes (Step 7).
- [ ] The vault text is in the PR description (Step 8).

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Exit 2 with no output | missing `python3`, or a usage error | read stderr; install Python 3.9 or later, or fix the arguments |
| `tree` prints `not_opted_in` in the scratch repository | the `design` block is missing or in a local file | put the block in the scratch repository's versioned `.ai-dev-workflow.yaml` |
| A token reported as not declared although it is in a stylesheet | the stylesheet is linked by an absolute URL, from outside the repository, or by `@import` | link it relatively inside the repository (stated limitation) |

---

## Known Limitations

- Token mirroring reads only plain `:root` rules, linked in-repository
  stylesheets and the root element's `style` attribute (BR10).
- Product-repository delivery of the tool is decided with #2214.
