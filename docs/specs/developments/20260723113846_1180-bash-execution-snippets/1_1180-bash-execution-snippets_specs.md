# Explicit Bash Execution for Workflow-Owned Snippets - Spec

---

## Overview

Workflow authors and operators need repository-owned shell guidance to behave
consistently when commands are launched from environments whose default shell
is not Bash. Today, snippets can silently do the wrong amount of work when they
depend on Bash-specific splitting behavior but are interpreted by zsh.

This feature makes each workflow-owned shell execution boundary explicit:
Bash-dependent commands clearly require Bash, while genuinely portable snippets
behave consistently under both Bash and zsh. It also adds focused regression
coverage so new unsafe implicit-splitting examples are caught before release.

## Brief Objective List

Derived from issue #1180:

1. Limit the requirement to repository-owned workflow snippets, generated
   commands, and framework documentation that agents or operators execute.
2. Make Bash a visible requirement at every execution boundary that depends on
   Bash behavior.
3. Ensure snippets advertised for both Bash and zsh do not depend on implicit
   word splitting or shell-specific positional-argument splitting.
4. Add focused lint or regression coverage for newly introduced
   workflow-owned snippets that rely on unsafe implicit splitting.
5. Preserve compatibility with Bash 3.2 for shipped workflow scripts.

## Use Cases

### Use Case 1: Operator runs a Bash-dependent workflow command from zsh

**Actor**: Workflow operator or AI agent.
**Preconditions**: The operator is using an environment where zsh is the
default shell and encounters a workflow-owned command that depends on Bash
behavior.

**Steps**:

1. The operator reads or receives the workflow command.
2. The execution boundary visibly identifies Bash as required.
3. The command is launched through Bash rather than being interpreted by the
   default shell.
4. The workflow completes every intended iteration and argument extraction.

**Postconditions**: The command produces the same intended workflow outcome
regardless of the operator's default interactive shell.

**Information shown**:

- The shell required to execute the command.
- An actionable failure or validation message when the requirement is not met.

**Actions available**:

- Run the command using the stated shell.
- Correct the snippet when validation identifies an ambiguous execution
  boundary.

**Considerations**:

- The workflow must not treat a successful process exit as proof that all
  intended iterations ran.
- Commands copied from prompts or documentation need the same clarity as
  commands stored in executable script files.

### Use Case 2: Workflow author publishes a cross-shell snippet

**Actor**: Template maintainer or workflow author.
**Preconditions**: The author is adding or changing a workflow-owned snippet
that is intended to work in both Bash and zsh.

**Steps**:

1. The author identifies the snippet as portable across Bash and zsh.
2. The author avoids behavior whose meaning depends on implicit word splitting
   or shell-specific positional-argument expansion.
3. The author verifies the snippet in the supported shell environments.
4. The workflow accepts the snippet when it produces the same logical result
   in both environments.

**Postconditions**: Operators can execute the snippet in either supported shell
without silent changes to iteration count or argument boundaries.

**Information shown**:

- Which shells the snippet supports.
- Which snippet caused a portability validation failure, when applicable.
- Why the detected construct is unsafe and what kind of correction is needed.

**Actions available**:

- Rewrite the snippet using portable behavior.
- Declare and enforce Bash at the execution boundary when portability is not
  required.

**Considerations**:

- A portability failure should identify the relevant snippet or source
  location without requiring the author to inspect every workflow document.
- The accepted correction must continue to support environments limited to
  Bash 3.2.

### Use Case 3: Maintainer verifies the workflow surface before release

**Actor**: Template maintainer or reviewer.
**Preconditions**: A change adds or updates workflow-owned shell commands,
generated commands, or documentation snippets.

**Steps**:

1. The maintainer runs the focused validation or regression suite.
2. The suite exercises representative Bash-required and cross-shell snippets.
3. The suite rejects newly introduced unsafe implicit-splitting behavior.
4. The maintainer reviews evidence that accepted snippets retain Bash 3.2
   compatibility.

**Postconditions**: The changed workflow surface has repeatable evidence that
its shell contract is explicit and its supported behavior is preserved.

**Information shown**:

- Which validation cases passed or failed.
- The source location and reason for each failure.
- The supported-shell expectation for the affected snippet.

**Actions available**:

- Accept a change whose checks pass.
- Request a shell-boundary or portability correction.
- Extend focused coverage when a new unsafe pattern is discovered.

**Considerations**:

- Validation should remain focused on workflow-owned executable guidance, not
  arbitrary downstream consumer scripts.
- Existing valid Bash 3.2-compatible scripts must not be forced to adopt
  features from newer Bash versions.

## Business Rules

- Every workflow-owned shell snippet must either state and enforce a required
  shell or behave consistently across every shell it claims to support.
- A Bash-dependent snippet must invoke Bash explicitly at the point where an
  agent or operator executes it; surrounding prose alone is insufficient when
  the executable boundary remains ambiguous.
- A snippet advertised for both Bash and zsh must not depend on unquoted
  expansion producing the same word or positional-argument splitting in both
  shells.
- Validation must cover repository-owned workflow snippets, generated commands,
  and framework documentation intended for execution.
- The feature must not impose shell-portability requirements on arbitrary
  downstream application scripts that are outside the framework-owned workflow
  surface.
- Validation failures must identify the affected source location and provide an
  actionable reason.
- Shipped workflow scripts must remain executable on Bash 3.2.
- A zero process exit code alone is not sufficient regression evidence for
  iteration-sensitive snippets; verification must confirm the intended items
  or argument groups were processed.

## Operational Visibility

- **Validation output**: Failures name the affected workflow-owned snippet or
  source location, its expected shell contract, and the unsafe behavior found.
- **Review evidence**: The implementation PR records focused regression results
  for Bash-required and cross-shell cases.
- **Operator guidance**: Executable examples clearly show which shell launches
  them so macOS zsh users do not have to infer the contract.

## Acceptance Criteria

- [ ] A workflow-owned snippet that depends on Bash behavior visibly invokes or
      otherwise enforces Bash at its execution boundary.
- [ ] Running a Bash-dependent workflow example from a zsh-default environment
      processes the same intended items and argument groups as running it from
      a Bash-default environment.
- [ ] A workflow-owned snippet advertised for both Bash and zsh produces the
      same logical iteration and argument-boundary results in both shells.
- [ ] Focused validation rejects a newly introduced workflow-owned snippet that
      relies on unsafe implicit word splitting without an explicit Bash
      execution boundary.
- [ ] A validation failure identifies the affected source location and explains
      whether the author should enforce Bash or make the snippet portable.
- [ ] Validation includes representative coverage for both loop iteration and
      positional-argument extraction behavior.
- [ ] Existing shipped workflow scripts continue to pass under Bash 3.2.
- [ ] Workflow documentation states that the requirement applies to
      repository-owned workflow snippets, generated commands, and executable
      framework guidance, not arbitrary downstream scripts.
- [ ] Verification confirms intended processing results rather than relying
      only on a zero exit status.

## Coverage Matrix

| Brief objective | Coverage |
| --- | --- |
| 1. Limit scope to workflow-owned executable guidance | Use Cases 1-3, Business Rules, AC4, AC8 |
| 2. Make Bash requirements explicit at execution boundaries | Use Case 1, Business Rules, AC1, AC2, AC5 |
| 3. Keep cross-shell snippets free of unsafe implicit splitting | Use Case 2, Business Rules, AC3, AC5, AC6 |
| 4. Add focused lint or regression coverage | Use Case 3, Operational Visibility, AC4-AC6, AC9 |
| 5. Preserve Bash 3.2 compatibility | Use Cases 2-3, Business Rules, AC7 |

## Out of Scope (MVP)

- Requiring arbitrary downstream consumer scripts to support both Bash and zsh.
  **Deferral Note**: issue #1180 explicitly limits this improvement to
  framework-owned workflow execution surfaces; no human confirmation is
  requested.
- Selecting the exact lint implementation, pattern-matching strategy, or test
  harness. **Deferral Note**: the spec defines the required behavior and
  evidence; the implementation plan will choose the technical mechanism, so no
  human confirmation is requested.
- Guaranteeing portability across shells other than Bash and zsh.
  **Deferral Note**: the reported failure and refined acceptance criteria target
  the macOS zsh/Bash boundary; broader shell support can be evaluated
  separately, and no human confirmation is requested.
- Replacing Bash-specific workflow scripts with a different scripting
  language. **Deferral Note**: the goal is an explicit execution contract and
  safe portable snippets, not a framework-wide language migration; no human
  confirmation is requested.
