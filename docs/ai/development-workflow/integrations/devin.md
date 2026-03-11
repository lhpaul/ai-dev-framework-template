# Integration: Devin (Planned, Not Yet Supported)

This repository reserves `devin` as a future automated PR review platform identifier.

Current status:
- Planned
- Not implemented in `scripts/development-workflow/pr-review-loop.sh`
- Reported as `skipped` with reason `unsupported-platform` when configured

---

## Why This Is Not Implemented Yet

The shared review loop only supports platforms with a deterministic adapter contract. For Devin, this repository does not yet define all of the following:

- Bot or app identity on the PR
- Re-review trigger mechanism after a push
- Reliable review completion signal
- API query for new inline comments or blocking review summaries
- Filtering rules that separate Devin findings from human activity

---

## Adapter Contract Required

To implement Devin support, add a repo-documented contract that specifies:

1. `bot_login`
2. Re-review trigger command or API action
3. Completion polling query
4. Inline comment fetch query
5. Blocking review summary fetch query, if separate from inline comments

Once those are documented, the `pr-review-loop.sh` adapter can be added without changing the aggregate multi-platform behavior.
