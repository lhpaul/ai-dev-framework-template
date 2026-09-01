# Strict Plan Contract Checks

Closed set of checks applied by the local AI reviewer on **plan-stage** pull
requests that change at least one implementation-plan document. Each level-3
heading is the check identifier; the parser and incidence counters read
identifiers from this document rather than repeating them.

Findings produced by these checks are **non-blocking**. They never change a
review's verdict.

### source_declaration

Source: not required

**Question:** Does the plan name its source of truth — the approved spec it
implements, or the tracker brief for a Refactor item — and, when it names a
spec, is that spec present in the same development directory?

**Finding shape:** a plan naming no source, or naming a spec that is not there.

### unspecified_step

Source: required

**Question:** Does every step trace to an acceptance criterion or use case in
the source, or, tracing to neither, declare itself an addition and say why it
is needed?

**Finding shape:** a step nothing in the source asks for, presented as though it
did.

### spec_traceability

Source: required

**Question:** Does every acceptance criterion in the source have at least one
step that would satisfy it, or an explicit statement that it is handled
elsewhere?

**Finding shape:** an acceptance criterion no step addresses.

### ac_test_coverage

Source: required

**Question:** Does every acceptance criterion have at least one named test,
scenario or proof that would **fail** if the criterion were unmet?

**Finding shape:** a criterion covered by a test that passes whether or not it
holds, or by none.

### phase_ordering

Source: not required

**Question:** Does every step that consumes something another step produces
come after that step, in the order the plan states?

**Finding shape:** a step using a file, function or field a later step creates.

### dependency_state

Source: not required

**Question:** Does every dependency on another item state that item's current
state — merged, implemented, open — and what this plan does if that state does
not hold when implementation starts?

**Finding shape:** a dependency named without its state, or with no stated
consequence.

### reversal_risk

Source: not required

**Question:** Does every step that changes persisted data, a published contract
or a deployed surface state how the change is undone, or state that it cannot be
undone?

**Finding shape:** a migration or contract change with no stated reversal and no
statement that none exists.
