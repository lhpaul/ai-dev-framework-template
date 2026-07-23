# Smoke Test Runbook: Portable Protocol 02 Parser Guidance

**Feature**: Portable Protocol 02 Parser Guidance
**Spec**:
[1_1310-protocol-02-product-repo-path_specs.md](../../specs/developments/20260723112430_1310-protocol-02-product-repo-path/1_1310-protocol-02-product-repo-path_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] The implementation branch for issue #1310 is checked out.
- [ ] The planned Protocol 02 edit, portability regression script, and
      `[Unreleased]` changelog entry have been implemented.
- [ ] `bash`, `python3`, `rg`, `git`, and `npx` are available.
- [ ] `node_modules` is available or `npx markdownlint-cli2` can resolve the
      configured Markdown linter.
- [ ] The test runner can create and remove a temporary directory.

---

## Test Data

| Item | Value |
| --- | --- |
| Corrected protocol | `docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md` |
| Portability regression | `scripts/development-workflow/tests/test-protocol-02-portable-parser-guidance.sh` |
| Mode-scope regression | `scripts/development-workflow/tests/test-sync-template-mode-scopes.sh` |
| Canonical sync command | `.claude/commands/sync-template.md` |
| Obsolete fixture slug | `20260420120000_201-tech-lead-parser-regex-plan-requirements` |
| Expected release section | `CHANGELOG.md` under `[Unreleased]` |

---

## Smoke Test Steps

### Step 1: Run the Protocol 02 portability regression

**Maps to**: AC1, AC2, AC3, AC4, AC5, AC7

Run:

```bash
bash scripts/development-workflow/tests/test-protocol-02-portable-parser-guidance.sh
```

**Expected result**: The test exits successfully. Output confirms the exact
obsolete historical path is absent from live Protocol 02 guidance, the
self-contained normative topics are present, optional history is non-blocking,
and the generic sync missing-reference gate remains strict.

### Step 2: Simulate a receiving repository without template history

**Maps to**: AC1, AC2, AC3, AC7

Inspect or rerun the temporary fixture scenario from the portability regression:

1. Create a temporary repository directory with no
   `docs/specs/developments/` subtree.
2. Copy the corrected Protocol 02 into its workflow protocol location.
3. Search the copied protocol for the obsolete fixture slug.
4. Read the parser-risk and suppression section from the copied protocol.

**Expected result**: The obsolete slug is absent. The copied protocol itself
states the required edge-case, automated-test, directive-recognition,
placement, and multiple-suppression intent. Missing historical development
folders do not require an exception or operator acknowledgement.

### Step 3: Verify parser and suppression semantics are preserved

**Maps to**: AC1, AC5

Run:

```bash
rg -n "Edge-case enumeration|Unit tests|Which directives are recognized|Where directives can appear|multiple suppressions" \
  docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md
```

**Expected result**: Every required topic is present and remains normative.
The portability edit does not relax parser-risk classification, concrete
edge-case coverage, automated unit-test mapping, or suppression behavior.

### Step 4: Verify genuine missing-reference handling remains strict

**Maps to**: AC3, AC4

Run:

```bash
SYNC_COMMAND=".claude/commands/sync-template.md"
SYNC_BLOCK=$(
  sed -n '/^### .*path verification /,/^### /p' "$SYNC_COMMAND"
)
SYNC_BLOCK_STATUS=$?
if [ "$SYNC_BLOCK_STATUS" -ne 0 ] || [ -z "$SYNC_BLOCK" ]; then
  exit 1
fi
printf '%s\n' "$SYNC_BLOCK"
```

**Expected result**: The command exits successfully. The canonical sync command
still requires every resulting required docs path to resolve and prevents
commit or requires explicit acknowledgement when a genuine missing path
remains. No broad hub-only allowlist or failure suppression is introduced.

### Step 5: Verify repository-role selection is unchanged

**Maps to**: AC3, AC4, AC7

Run:

```bash
bash scripts/development-workflow/tests/test-sync-template-mode-scopes.sh
```

**Expected result**: The existing suite passes. `single_repo` and
`workflow_hub` continue selecting the full workflow docs tree, while
`product_repo` continues applying its existing scoped selection. The
portability correction does not widen sync scope.

### Step 6: Check live-reference residuals

**Maps to**: AC1, AC2, AC3

Run:

```bash
OBSOLETE_SLUG="20260420120000_201-tech-lead-parser-regex-plan-requirements"
set +e
rg -n -F "$OBSOLETE_SLUG" \
  docs/workflow .claude/commands .agents/skills .codex/skills
LIVE_GUIDANCE_STATUS=$?
set -e
case "$LIVE_GUIDANCE_STATUS" in
  0) exit 1 ;;
  1) ;;
  *) exit "$LIVE_GUIDANCE_STATUS" ;;
esac

set +e
rg -n -F "$OBSOLETE_SLUG" . --hidden --glob '!.git/**'
EVIDENCE_SEARCH_STATUS=$?
set -e
if [ "$EVIDENCE_SEARCH_STATUS" -gt 1 ]; then
  exit "$EVIDENCE_SEARCH_STATUS"
fi
```

**Expected result**: The command prints no live guidance occurrence. Any
remaining occurrence elsewhere is limited to approved spec, plan, regression,
smoke, or changelog evidence and is explicitly classified as historical/test
data.

### Step 7: Verify the downstream implementation PR release note

**Maps to**: AC6

Run:

```bash
awk -v expected="**Make Protocol 02 parser guidance portable** (#1310):" '
  /^## \[Unreleased\]/ { in_unreleased = 1; next }
  in_unreleased && /^## \[/ { exit }
  in_unreleased && index($0, expected) { print; matches++ }
  END { exit matches == 1 ? 0 : 1 }
' CHANGELOG.md
```

**Expected result**: Exactly one entry appears under `[Unreleased]` and states
that synced repositories no longer depend on an unavailable historical
development fixture.

### Step 8: Run shell and Markdown quality gates

**Maps to**: AC3, AC4, AC5, AC7

Run:

```bash
shellcheck scripts/development-workflow/tests/test-protocol-02-portable-parser-guidance.sh
python3 scripts/lint/workflow-shell-guard-lint.py --base-ref origin/develop
npx markdownlint-cli2 \
  "docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md" \
  "docs/specs/developments/20260723112430_1310-protocol-02-product-repo-path/*.md" \
  "docs/testing/workflow/1310-protocol-02-product-repo-path.smoke-test.md" \
  "CHANGELOG.md"
```

**Expected result**: ShellCheck, the workflow shell guard, and Markdown lint
all exit successfully.

### Last Step: Validate assertions

- [ ] Protocol 02 contains no required local link to the unavailable historical
      fixture.
- [ ] A receiving repository without historical development folders can apply
      all required parser-risk and suppression guidance locally.
- [ ] Any historical/template context is clearly optional and non-blocking.
- [ ] Post-apply validation does not report the removed fixture dependency.
- [ ] Genuine missing required references continue to block or require explicit
      acknowledgement.
- [ ] Parser-risk classification, edge-case enumeration, automated unit tests,
      directive recognition, placement, and multiple-suppression requirements
      are unchanged.
- [ ] Repository-role sync selection remains unchanged.
- [ ] The template changelog contains the #1310 portability correction.

---

## Seed Data Reference

No persistent seed data is required.

| Entity | Scenario | How to load |
| --- | --- | --- |
| Receiving repository fixture | Corrected protocol with no historical development subtree | Created by `test-protocol-02-portable-parser-guidance.sh` |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Portability test still finds the obsolete slug | Protocol 02 or another live mirror retained the historical path | Remove the live dependency; keep only explicit test/history evidence |
| Required suppression topic assertion fails | The portability rewrite weakened or renamed normative guidance | Restore the required concept in self-contained Protocol 02 prose |
| Mode-scope regression fails | The implementation changed manifest selection unintentionally | Revert the unrelated scope change and keep the correction protocol-local |
| Sync contract assertion fails | Sync validation guidance was weakened or broadly allowlisted | Restore the canonical strict missing-path behavior |
| Markdown lint reports a relative link error | A plan or runbook link uses incorrect directory depth | Correct the relative target and rerun the exact lint command |

---

## Known Limitations

- The temporary fixture validates repository content. The sync contract check
  protects the canonical command text; it does not run a live downstream
  `/sync-template` against a remote project.
- The fix does not distribute all hub-only workflow documentation to every
  `product_repo`; it makes Protocol 02 portable whenever that protocol is
  present.
