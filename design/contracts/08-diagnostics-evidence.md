# 8. Diagnostics and evidence

Part of the [proposed design](../design.md#8-diagnostics-and-evidence). This section retains the
baseline's authority and is subject to the accepted amendments in [§32](../design.md#32-accepted-and-deferred-implementation-choices).

Every deterministic failure is represented consistently:

[View the Diagnostic contract sample](../code.md#diagnostic-contract).

Representative codes include:

- `CFG_SCHEMA_INVALID`
- `PRESET_PLACEHOLDER_UNRESOLVED`
- `STAGE_PREDECESSOR_INVALID`
- `REF_PATH_ESCAPE`
- `REF_DECODER_UNAVAILABLE`
- `REF_CITATION_NOT_FOUND`
- `SPEC_UNRESOLVED_CLARIFICATION`
- `SPEC_TECHNICAL_LEAK`
- `ARTIFACT_PATH_INVALID`
- `PATH_ENVIRONMENT_AMBIGUOUS`
- `PATH_KIND_AMBIGUOUS`
- `PATH_ROOT_FORBIDDEN`
- `PATH_EXTENSION_INVALID`
- `PATH_FILENAME_PATTERN_INVALID`
- `TEST_PLACEMENT_INVALID`
- `PLAN_REQUIREMENT_UNCOVERED`
- `TASK_ID_REFERENCE_UNKNOWN`
- `TASK_DEPENDENCY_CYCLE`
- `TASK_PARALLEL_WRITE_CONFLICT`
- `PATCH_OUTSIDE_TASK_SCOPE`
- `PATCH_APPLY_FAILED`
- `SOURCE_SYNTAX_INVALID`
- `IMPORT_TARGET_MISSING`
- `COMMAND_FAILED`
- `TASK_EVIDENCE_INCOMPLETE`
- `REPAIR_SCOPE_VIOLATION`
- `REPAIR_ATTEMPTS_EXHAUSTED`

Diagnostics are sorted deterministically by stage, artifact, location, validator priority, and code. Human-facing messages are rendered from codes and fields; repair logic does not parse prose.

Evidence is separate from diagnostics. It records facts such as a decoded source location, a successfully parsed AST, a passing command, or a successfully published output set. A checklist or task status is derived from evidence and cannot be set by the LLM.
