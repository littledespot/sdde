# ADR 0010: The supplied directory identifies the feature

- **Status:** Accepted
- **Date:** 2026-09-05
- **Decision authority:** Explicit user direction
- **Supersedes:** ADR 0008's reference-derived naming and the feature-ownership
  registry/inventory gates in Design Sections 7.3, 13.2, 17, 24 and 25.

## Decision

- The workflow invocation supplies a feature directory relative to `paths.specs` from
  `.sddtoolkit.json`.
- The engine resolves that configured root plus the supplied relative directory; the
  resolved directory identifies the feature.
- No name is derived from references or model output, and no ownership registry is
  required.

For Specify, the CLI contract is:

```text
sdde <workflow-id> --feature <feature-directory> --reference <relative-selector>
```

- The workflow ID comes from the selected definition under ADR 0003; it is not a fixed
  CLI verb.
- `--feature` is relative to the configured `paths.specs`, not the project root.
- For example, `--feature hello-world` selects `<paths.specs>/hello-world/`, and Specify
  produces `<paths.specs>/hello-world/spec.md`.
- The caller does not repeat the specs root.
- The engine must read that root from `.sddtoolkit.json`; never hard-code `specs/`,
  infer an output root, or strip a presumed root prefix.

- `--reference` independently selects the source directory beneath `paths.references`.
- The API's `featureDirectory` has the same `paths.specs`-relative meaning;
  `referenceSelector` is relative to `paths.references`.
- Both are required.
- Other workflows use their registered invocation contracts; the generic engine does not
  impose these arguments on unrelated definitions.

- Normalize and validate the supplied path with the shared path policy, enforce
  containment, `paths.specsArchive` exclusion and no-follow checks, and reject invalid
  or ambiguous filesystem aliases.
- Do not slugify, transliterate, truncate, suffix or rename it.
- Where existing contracts use `featureId`, it is only the lossless
  `paths.specs`-relative directory key, not a separately allocated identity or
  authority.

- The same directory is the same feature, even when its reference input changes.
- Load and validate only the selected feature's state needed by the workflow;
  directory/file existence alone proves neither valid state nor stage completion.
- Reference changes still undergo validation and downstream invalidation.
- No registry membership or separate overwrite approval is required to replace the
  selected workflow's known outputs.

Reruns follow [ADR 0009's shared replacement rule](0009-atomic-workflow-execution.md#rerun-replacement-rule-accepted-2026-09-07):

- Replace registered outputs and unresolved forms at their existing paths; retain
  clarification IDs and applicable validated answers.
- Preserve user-closed files byte-for-byte, including stale or invalid submissions;
  recheck protection before writing.
- Keep unrelated files outside the write set.
- Follow ADR 0009 for publication and fresh reruns; add no recovery mechanism.

## Implementation status

- Implemented: the two-field invocation and read-only feature/reference preflight,
  shared path validation, config-root-relative selection, archive/alias rejection, and
  directory-key consumers.
- The derived-name operation and naming parameters are removed.
- Tests cover standard/custom specs roots, independent reference changes and unchanged
  existing files.
- Generation, registered-output replacement and write-time protection are now connected
  through the shared writer.
- Authenticated answer application and broader Specify acceptance remain open; [F0100
  §3.12](../features/F0100-SpecWorkflow.md#312-clarification-refresh-and-registered-publication)
  tracks the current boundary.
