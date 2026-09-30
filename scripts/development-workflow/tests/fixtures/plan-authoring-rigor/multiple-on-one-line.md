# Multiple rule mentions on one line fixture

- Checklist: Rule 1 and Rule 2 must both be reviewed on this line.

This fixture proves line-level `grep` may match both rule names on one
checklist line, while heading-level checks (which require `### Rule N` at the
start of a line) remain authoritative for the canonical file and are not
confused by this inline prose line.
