# Spec fixture: gate_matrix negative (AC-7)

## Decision Matrix
Every reachable combination of stage and checklist is listed. No short-circuit;
both inputs are always evaluated.

| Stage | Checklist | Outcome |
| --- | --- | --- |
| spec | present | apply |
| spec | absent | unavailable |
| plan | present | skip |
| plan | absent | skip |
