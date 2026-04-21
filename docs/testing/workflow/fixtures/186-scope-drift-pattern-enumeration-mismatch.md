# Fixture: Pattern Enumeration Mismatch

This fixture simulates a stale spec excerpt where intent is "all matching files" but the explicit list is incomplete.

## Stale Spec Excerpt

Guidance must be added to all files matching pattern:

`docs/ai/development-workflow/protocols/*-protocol.md`

Current (stale) enumeration in spec text:

- `docs/ai/development-workflow/protocols/01-generate-spec-protocol.md`
- `docs/ai/development-workflow/protocols/02-generate-implementation-plan-protocol.md`
- `docs/ai/development-workflow/protocols/03-implement-development-protocol.md`

## Verification Intent

A plan writer should run a live query (for example `rg --files docs/ai/development-workflow/protocols`) and use current repository results for counts/paths rather than copying the stale list above.
