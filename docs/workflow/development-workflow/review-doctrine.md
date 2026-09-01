# Review Doctrine

This catalogue lists recurring finding **shapes** worth looking for during
review. It is **not** the set of things worth reporting — withhold no real
finding because it fits no catalogued pattern. When you match a pattern below,
**name it** in your finding so later readers can tell doctrine-driven findings
from the rest.

## Adding patterns

Each entry has four parts in this order: a level-3 heading (pattern name), then
exactly one `**Shape**:`, one `**Example**:` and one `**Detect**:` paragraph.
Remove every trace of the specific incident — no pull request number, no issue
number, no person, no title, no path from the incident. Paths in this guidance
are fine; paths inside entries are not.

Before opening a pull request, confirm the entry reads generally — no person's
name, no document title, no wording that only makes sense to someone who saw
the original incident. See also the Workflow Policy Review Checklist in
`REVIEW.md`.

The catalogue is bounded at 12,000 bytes (`REVIEW_DOCTRINE_MAX_BYTES` in
`scripts/development-workflow/workflow-lib.sh`). When the bound is reached,
**merge or remove a pattern — never raise the bound in the same change that
breaches it.** Raising the bound is a deliberate, separately reviewed change to
the doctrine contract.

Example development-folder paths like `docs/specs/developments/` appear only in
this guidance, never inside pattern entries.

### Criteria/matrix mismatch

**Shape**: A table that enumerates decisions disagrees with the criteria stated
above it, or omits a combination those criteria admit.

**Example**: Acceptance criteria require both "logged in" and "not logged in"
outcomes, but the decision matrix has rows only for the logged-in case.

**Detect**: For each matrix row, can you point to the criterion it implements?
For each criterion combination the prose admits, is there a row?

### Opt-out ambiguity

**Shape**: A way to disable or bypass behavior has its source of truth stated in
more than one place, or in none.

**Example**: One section says "set `FEATURE=0` to disable" while another says
"unset `FEATURE` to disable."

**Detect**: Where is the authoritative opt-out named, and do all other mentions
agree with it?

### Parser-surface conflict

**Shape**: A rule about how input is recognised conflicts with the syntax the
document elsewhere requires, or assumes a capability the stated tooling lacks.

**Example**: A protocol requires comma-separated values but the parser section
documents only space-delimited tokens.

**Detect**: Does the syntax examples use match what the parser rule accepts?
Does the stated tooling support every construct the rule requires?

### Trigger ambiguity

**Shape**: A condition that starts behavior does not say what happens when its
inputs are absent, empty, or malformed.

**Example**: "When the flag is set, run the check" with no row for an unset or
invalid flag value.

**Detect**: For each input the trigger names, is the outcome defined when that
input is missing, empty, or invalid?

### Example contradicting rule

**Shape**: A worked example demonstrates something the rule beside it forbids,
or omits a step the rule requires.

**Example**: The rule says "always emit a reason" but the example output omits
the reason field entirely.

**Detect**: Does the example satisfy every requirement stated in the adjacent
rule, with no extra steps the rule forbids?
