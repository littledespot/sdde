# 15. Bootstrap flow

Part of the [proposed design](../design.md#15-bootstrap-flow). This section retains the
baseline's authority and is subject to the accepted amendments in [§32](../design.md#32-accepted-and-deferred-implementation-choices).

Bootstrap has a fixed engine-startup portion and workflow-owned setup:

[View the Bootstrap flow sample](../code.md#bootstrap-flow).

- The composition-root-owned startup graph runs before project workflow selection.
- It validates the seven configured directory roots and the provider-document location, totally
  accounts the workflow root, compiles every discovered definition from registered operation
  contracts, and validates the variable-size workflow registry.
- It acquires no feature transaction lock, is not registered as a project workflow, and cannot
  be changed beneath `paths.workflows`.

- After exact selection, the YAML-named registered invocation operation produces the workflow's
  typed run context.
- Only the selected graph decides whether to invoke registered target-context setup nodes.
- The initial SDD graphs do so after their workflow arguments validate: the SDD setup owns exact
  feature-target resolution and the selected feature's existing published-state validation.
- No project-level transaction storage is required.
- After the exact feature target is known, its remaining nodes parse the exact project
  `toolchain.yaml`, resolve its complete preset inheritance closure from
  `paths.toolchainPreset`, capture semantic Markdown principles while excluding
  `toolchain.yaml`, and compile operational policy.
- An unrelated workflow does not inherit that feature/toolchain setup unless its validated graph
  references the same registered contracts.
- No model or project-changing node runs before the setup required by its compiled graph
  succeeds.
- `paths.templates` is reserved but no initial SDD workflow receives a read capability for it.
- A config, workflow-definition, toolchain-layer, preset, reader, parser, project, or command
  ambiguity is an engine/environment problem and does not consume a repair attempt.

The new engine uses typed filesystem and process adapters. It does not reproduce the predecessor `eval $(get_feature_paths)` pattern (`.specify/scripts/bash/common.sh:71-88`), hard-code `specs/`, or delegate state construction to a shell script.
