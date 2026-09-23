Declare a profile per `docs/workflow/development-workflow/integrations/cursor-dispatch-profiles.md`: `cursor-native-handoff`, `cursor-parent-orchestrated`, or `cursor-inline-fallback`.

Named stop conditions: `dispatch_profile_declaration_missing`, `dispatch_handoff_unavailable`, and the reused `missing_required_secret_or_permission`.

Affected work item: the branch, pull request, or development-folder path.

Human unblocking action: not resumed or corrected in place; start a fresh invocation supplying a valid profile, a named accountable role, a posture valid for the checkpoint, and, when rejected for a fact mismatch, the profile the known facts assign.

Move to an environment where initial handoff is confirmed available and re-run, or explicitly accept the read-only result; confirm the specific stage role the action needed is reachable.

The unblocking action: grant the identified credential and re-run the same delegated action, or reassign to the same stage role or explicitly accept the action does not proceed; the absorbing context never performs it inline.

A harness or local-path denial is not a named stop condition; it is only observably similar to `SUBAGENT_PERMISSION_DENIAL`, and is Out of Scope, tracked as #1746.

An invalid profile, an invalid accountable role, and an invalid posture are each a missing declaration.

This requirement applies only in a Cursor environment; other runners are unchanged.

A coarse-fact mismatch, when more permissive than the assigned outcome, is a missing declaration.

