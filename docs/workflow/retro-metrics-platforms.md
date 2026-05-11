# Platform Comparison Metrics Log

This file is append-only. One row is appended per compare-mode reviewer loop run.
Do not delete or rewrite existing rows. The "Block Was Real Bug?" column may be
filled in manually after a run when post-hoc analysis determines whether a
platform-exclusive blocking finding corresponded to a real code defect.

## Graduation Criteria

A platform may be considered safe for removal when, across 30 or more consecutive
compare-mode runs covering at least one run each of `fix`, `feature`, and `refactor`
branch types, it has zero platform-exclusive blocking findings (runs where that
platform blocked but at least one other configured platform was clean).

Fewer than 30 runs is always insufficient data for a graduation decision.

## Metrics Table

The table below is populated automatically by `pr-review-loop.sh --compare`. Platform
columns are added dynamically based on the configured platforms at the time of each
run. The header row is written on the first compare-mode run.
