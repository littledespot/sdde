# 13.6 Project path and static-validation actions

Part of [design §13](../../design.md#13-action-catalogue). Action names define responsibility
boundaries under [§6](../06-pipeline-nodes.md). Results remain execution-local until
whole-workflow publication; [§25](../25-publication.md) and the clarification exception apply.

## `CheckSourcePreservationPolicyAction` (`check-source-preservation-policy`)

- **Owner:** [`src/actions/validation/check_source_preservation_policy.zig`](../../../src/actions/validation/check_source_preservation_policy.zig)
- **Reads:** `citable_reference_inputs` · **Writes:** none · **Side effect:** `none`
- **Does:** Select the optional source-preservation branch from configuration
  (`validation.sourcePreservationCheck`,
  [ADR 0021](../../decisions/0021-optional-source-preservation-review.md)): `ok` when enabled,
  `more` when not.
- **Rejects:** none.

## `BuildFileRegistryStateAction`

Proposed, no code: assemble one complete versioned plan file registry from ordered validated
file records ([§18](../18-plan.md)).

## `ValidateExpectedTargetStateAction`

Proposed, no code: validate a file operation's current presence, regular-file type and
descriptor revision before it applies, without trusting the plan baseline
([§20](../20-implement.md)).

Proposed, no code: the project-path work Plan and Implement need. Bounded project discovery
and inventory accounting; path intents, path-candidate registries and candidate selection
(a model selects IDs, never paths); lexical safety, containment, root access, ownership, kind,
include/exclude, basename, extension and portability rules; the file registry and its
runtime file-state transitions; and static-reference extraction, resolution and
content-reference coverage. [§11](../11-path-validation.md) owns the path rules,
[§18](../18-plan.md) the plan registries and [§19](../19-tasks.md) and
[§20](../20-implement.md) the runtime file state.
