# Outcome label casing fixture (wrong case)

| Rule | Outcome |
| --- | --- |
| Rule 1 | satisfied |
| Rule 2 | not applicable |
| Rule 3 | unsatisfied |

This fixture uses the code-value casing (`satisfied`, `not applicable`,
`unsatisfied`) instead of the display labels' correct case, and must not
satisfy a case-sensitive display-label check.
