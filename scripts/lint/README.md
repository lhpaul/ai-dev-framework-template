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
- **SH002** - Command substitution masking in `local` / `declare` / `export`:
  flags shell assignments that can hide a failed command substitution.
- **SH003** - Unguarded `jq -r` assignment: flags control-flow assignments that
  read from `jq -r` without `-e` or an explicit exit-code guard.
- **SH004** - Unanchored branch-prefix grep: flags workflow grep checks that
  can match substrings such as `hotfix/` instead of a true branch prefix.
- **SH005** - Bash 4 associative arrays: flags `local -A` and `declare -A` in
  workflow scripts because the repo supports macOS bash 3.2.

Use explicit control flow instead of blanket suppression. If a best-effort
failure is intentional, keep the suppression local and add a rationale:

```bash
git fetch origin "$base" 2>/dev/null || true # workflow-shell-guard: allow SH001 - best effort cache refresh
```

Rule-specific suppressions use the same shape:

```bash
RESULT=$(jq -r '.state' <<< "$payload") # workflow-shell-guard: allow SH003 - caller checks the exit code elsewhere
```

**Usage:**

```bash
python3 scripts/lint/workflow-shell-guard-lint.py --base-ref origin/develop
```

## workflow-shell-snippet-lint.py

Diff-based guard for executable fenced shell snippets on framework-owned
guidance surfaces. Put one adjacent marker before each changed executable
fence:

```text
<!-- workflow-shell-contract: bash -->
<!-- workflow-shell-contract: bash-zsh -->
```

`bash` snippets visibly launch Bash (and remain Bash 3.2 compatible).
`bash-zsh` snippets must avoid implicit word splitting, `set -- $value`, and
Bash-only syntax. The linter reports WS001 through WS006 for missing contracts
or unsafe boundaries.

```bash
python3 scripts/lint/workflow-shell-snippet-lint.py --base-ref origin/develop
bash scripts/lint/tests/test-workflow-shell-snippet-lint.sh
```

**Exit 0 without an examined count is not evidence.** Every run prints a
summary line — `examined=N files, M fences, K changed-lines (source: ...);
findings=N` — precisely so a silent success cannot be mistaken for a real pass.
If `examined=0`, no WS rule ran and the run proves nothing about WS001–WS006.

The summary is printed before **every** exit, refusals included.

| Exit | Meaning |
| --- | --- |
| `0` | The run examined its scope and found nothing. `examined=0 files` here means the diff was well formed but touched no in-scope guidance file — a legitimate "nothing to check", announced on stderr. |
| `1` | Findings were reported. |
| `2` | The run examined nothing and refuses to be read as a pass. |

The four ways a run can examine nothing are reported distinctly, because they
are different failures:

| Condition | Message |
| --- | --- |
| `git diff` failed | `ERROR: <git stderr>` |
| Input carries no `diff --git` line, no well-formed hunk header, and no `+++` target header (a path list, prose, a stray `@@` line) | `expects a unified diff` |
| Changed lines the parser cannot attribute — a hunk with no `+++ b/<path>` header (a `--no-prefix` diff), or a `+++` header with no hunk behind it | `carries changed lines this parser cannot read` |
| The diff is empty | `the diff under examination is empty` |

`--input` / `--diff-file` takes a **unified diff**, not a path list. A path list
was previously parsed as an empty diff and exited 0 while a real WS002 was still
present (PR #1646); it is now an error. Produce the diff with
`git diff --unified=0 <base>...HEAD` and keep the default `a/` and `b/`
prefixes, or use `--base-ref` and let the script run `git diff` itself.

What separates a legitimate zero from an unreadable input is whether the diff
carries changed lines at all. A **hunk header** means it does: without a
`+++ b/<path>` target header those lines cannot be attributed to a path, so the
input is refused. A record with **no hunk** but a `diff --git` line is a genuine
Git change with no textual content — a mode-only change, a binary file, a pure
rename — so zero examined is the right answer and the run passes. A deletion,
whose target header is `+++ /dev/null`, is likewise a valid diff with a
legitimate zero.

`--base-ref` diffs **committed** history (`<base>...HEAD`), so uncommitted work
is invisible to it: run it after committing, or the empty-diff refusal will
tell you so. Pass `--allow-empty` only where an empty diff is genuinely
expected. `--all` reads no diff and is exempt from the refusal.

**Tests:**

```bash
bash scripts/lint/tests/test-workflow-shell-guard-lint.sh
```
