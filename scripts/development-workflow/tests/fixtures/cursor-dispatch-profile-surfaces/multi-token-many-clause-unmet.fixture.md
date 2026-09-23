Declare a profile per `docs/workflow/development-workflow/integrations/cursor-dispatch-profiles.md`: `cursor-native-handoff`, `cursor-parent-orchestrated`, or `cursor-inline-fallback`.

Evaluation order: initial handoff is evaluated first; onward-handoff capability is evaluated only once initial handoff is confirmed. A profile decision never evaluates onward-handoff capability before initial handoff is confirmed.

Once initial handoff is confirmed, onward-handoff capability that cannot be confirmed is treated as unavailable, and the run declares `cursor-parent-orchestrated` as the conservative default.

Initial handoff availability that itself cannot be confirmed is treated the same as no handoff of any kind: the run declares `cursor-inline-fallback` and stays read-only. A later confirmation never upgrades a run in place.

Named stop conditions: `dispatch_profile_declaration_missing`, `dispatch_handoff_unavailable`, and the reused `missing_required_secret_or_permission`.

Affected work item: the branch, pull request, or development-folder path.

Human unblocking action: not resumed or corrected in place; start a fresh invocation supplying a valid profile, a named accountable role, a posture valid for the checkpoint, and, when rejected for a fact mismatch, the profile the known facts assign.

Move to an environment where initial handoff is confirmed available and re-run, or explicitly accept the read-only result; confirm the specific stage role the action needed is reachable.

The unblocking action: grant the identified credential and re-run the same delegated action, or reassign to the same stage role or explicitly accept the action does not proceed; the absorbing context never performs it inline.

A harness or local-path denial is not a named stop condition; it is only observably similar to `SUBAGENT_PERMISSION_DENIAL`, and is Out of Scope, tracked as #1746.

A coarse-fact mismatch, whether more permissive or less permissive than the assigned outcome, is a missing declaration.

This coarse check does not govern the mid-run recovery transitions.

A declaration states personally accountable (absorbed), handed off intact, or observing. Observing is valid only at a read-only checkpoint; the required posture follows the current checkpoint.

This requirement applies only in a Cursor environment; other runners are unchanged.



Evaluation order: initial handoff is evaluated first; onward-handoff capability is evaluated only once initial handoff is confirmed. A profile decision never evaluates onward-handoff capability before initial handoff is confirmed.

Evaluation order: initial handoff is evaluated first; onward-handoff capability is evaluated only once initial handoff is confirmed. A profile decision never evaluates onward-handoff capability before initial handoff is confirmed.

