### Fixed

- Shard the workflow test harness matrix so full selections run one job per
  balanced shard instead of one job per suite, preserving per-suite failure and
  timeout isolation while reducing GitHub Actions minute-rounding waste.
