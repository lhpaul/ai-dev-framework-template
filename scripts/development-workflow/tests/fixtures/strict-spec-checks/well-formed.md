# Strict Spec Contract Checks

Closed set of checks applied by the local AI reviewer on **spec-stage** pull
requests only. Each level-3 heading is the check identifier; the parser and
incidence counters read identifiers from this document rather than repeating
them.

Findings produced by these checks are **non-blocking**. They never change a
review's verdict.

### ac_consistency

**Question:** Do any two acceptance criteria contradict each other, or does one
contradict a business rule?

**Finding shape:** two criteria that cannot both hold.

### ac_testability

**Question:** Could a test distinguish this criterion being met from its being
unmet?

**Finding shape:** a criterion whose outcome no observation would differ on.

### gate_matrix

**Question:** Does behavior described as depending on several inputs enumerate
every **reachable** combination of them, under the evaluation order the document
states?

**Finding shape:** a described gate with a reachable combination unmentioned, or
with an evaluation order it never states.

A gate that short-circuits and **states that order** must not produce a finding
for combinations the order makes unreachable. A gate that short-circuits and
does **not** state the order must produce a finding: the unmentioned
combinations are indistinguishable from forgotten ones.

### opt_out_source

**Question:** Does each way of disabling or bypassing behavior name exactly one
source of truth?

**Finding shape:** an opt-out named in two places, or in none.

### trigger_semantics

**Question:** Does each condition that starts behavior say what happens when its
inputs are absent, empty or malformed?

**Finding shape:** a trigger with no stated behavior for a missing input.

### example_contradiction

**Question:** Does each worked example do what the rule beside it requires?

**Finding shape:** an example demonstrating what its rule forbids.

### parser_surface

**Question:** Is each statement about how input is recognised consistent with
the syntax the document requires elsewhere, and with the stated tooling?

**Finding shape:** a matching rule the stated tool cannot express.

### ambiguous_phrase

**Question:** Does any phrase whose meaning is unsettled — *next update*,
*absence of evidence*, *as needed*, *where appropriate* — determine behavior?

**Finding shape:** an unsettled phrase load-bearing in a rule.

The same phrase appearing only in a rationale, aside, or any passage that
determines no behavior is **not** a finding.
