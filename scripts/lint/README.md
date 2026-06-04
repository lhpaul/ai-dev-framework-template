# scripts/lint

Lint helpers for spec, plan, and CHANGELOG markdown documents.

## markdown-heuristic-lint.py

Custom Python 3 heuristic checks that complement `markdownlint-cli2`.

**Checks implemented:**

- **GLOB001** — Suspicious non-recursive glob: detects a non-recursive glob
  pattern (e.g., `*.sh`) inside a fenced code block when surrounding prose uses
  recursive-language cues (e.g., "subdirectories", "recursively"). The cue list
  is declared as `RECURSIVE_CUES` at the top of the script and can be extended
  without changing the detection logic.

- **COUNT001** — Within-document count disagreement: detects a narrative count
  phrase (e.g., "4 acceptance criteria", "three steps") that disagrees with the
  number of list items in the immediately following section (within 30 lines).

Both checks support inline suppression:

```markdown
<!-- markdown-heuristic-disable GLOB001 -->
<!-- markdown-heuristic-disable COUNT001 -->
```

Place the directive on the same line as the finding or on the immediately
preceding line. Suppressions must include a reviewer-visible rationale comment
nearby so the PR diff explains why the rule was suppressed.

**Usage:**

```bash
python3 scripts/lint/markdown-heuristic-lint.py <file> [<file> ...]
```

Exit code `0` means no findings; exit code `1` means one or more findings.

**Local run (all target files):**

```bash
find docs/specs/developments docs/testing/workflow -name "*.md" -print0 \
  | xargs -0 python3 scripts/lint/markdown-heuristic-lint.py CHANGELOG.md
```

## workflow-shell-guard-lint.py

Diff-based guard for newly added lines in `scripts/development-workflow/**/*.sh`.

**Checks implemented:**

- **SH001** - Critical command failure suppression: detects added lines that run
  `gh`, `git`, `curl`, or `haystack` and suppress failures with `|| true`.

Use explicit control flow instead of blanket suppression. If a best-effort
failure is intentional, keep the suppression local and add a rationale:

```bash
git fetch origin "$base" 2>/dev/null || true # workflow-shell-guard: allow SH001 - best effort cache refresh
```

**Usage:**

```bash
python3 scripts/lint/workflow-shell-guard-lint.py --base-ref origin/develop
```

**Tests:**

```bash
bash scripts/lint/tests/test-workflow-shell-guard-lint.sh
```
