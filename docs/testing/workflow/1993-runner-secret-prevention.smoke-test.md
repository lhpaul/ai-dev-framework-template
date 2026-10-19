# Private runner configuration isolation — Smoke Test

**Issue**: #1993
**Spec**: [Approved behavior](../../specs/developments/20261019133529_1993-runner-secret-prevention/1_1993-runner-secret-prevention_specs.md)

## Safety and Setup

Run every journey in a disposable synthetic repository. Use fabricated values
only. Never copy workstation configuration, source the real local env, inspect
credentials, or launch a real review service. The regression harness creates the
temporary repositories and supplies fake review settings. No browser or design
reference applies.

## Journeys

1. **No inherited private file (AC-1/AC-2)**: Put fake private review settings in
   the synthetic primary checkout. Start Python and Bash helpers in a linked
   checkout lacking local settings. Confirm shared settings apply and an access
   spy records no read or discovery of the primary private file. Repeat with empty
   and product-only local settings, and an escaping symlink.
2. **Explicit source (AC-3)**: Deliberately select the synthetic external root.
   Confirm its validated settings apply. Missing, unreadable and malformed roots
   must report safe errors without selecting another file.
3. **Minimum review staging (AC-6)**: Include fake unrelated sensitive settings
   beside valid reviewer declarations. Run synthetic preflight and inspect only
   its synthetic snapshot. Confirm the reviewer declarations and explicit empty
   lists retain meaning; unrelated fields and fake sensitive values are absent.
   Verify atomic staging and cleanup on simulated failure.
4. **Safe errors (AC-4)**: Pass malformed synthetic config containing an opaque
   fake value that matches no known credential prefix. Check stdout and stderr:
   source/category metadata is present and the value, raw line and parser excerpt
   are absent. Check both legacy and strict/model error paths.
5. **Redaction (AC-5)**: Exercise each redactor class from the plan through the
   resolver/Bash boundary and persistent reviewer/audit renderer. Confirm complete
   fake values are absent, stable markers remain, harmless text remains useful,
   and caller success/failure status survives. Cover multiline and unterminated
   private-key blocks and filter failure without unsafe echo.
6. **Prevention controls (AC-7)**: In a temporary Git repo, prove private workflow,
   env and private-key filenames are ignored while the public examples are
   trackable. Validate the versioned permission rules and portable agent guidance;
   do not claim enforcement by an unavailable runtime or execute Claude.
7. **Detection proof (AC-8)**: Run the documented planted fallback, disclosure and
   missing-ignore mutations against isolated fixtures. Each must fail its intended
   check; the corrected variant must pass. Record fixture location and result.
8. **Consumer guidance (AC-9)**: Confirm the upgrade guide and changelog explain
   explicit selection and minimal local review settings, warn against reintroducing
   fallback during sync, and contain no real local values.

## Expected Evidence

Record the tested revision, synthetic commands, pass/fail outcomes and planted
violation locations. Before readiness, the residual report accounts for all source
selectors and planned diagnostic/publication boundaries. Use the existing workflow
review/CI and merge-session gates; tests never grant merge authority.
