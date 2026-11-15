# 8. Diagnostics and evidence

Part of the [proposed design](../design.md#8-diagnostics-and-evidence), as amended by the
[accepted ADRs](../design.md#32-accepted-and-deferred-implementation-choices).

Every deterministic failure is represented consistently:

[View the Diagnostic contract sample](../code.md#diagnostic-contract).

Representative codes include:

- startup's closed public errors, such as `ENGINE_CONFIG_READ_ERROR`,
  `ENGINE_CONFIG_PARSE_ERROR`, `LLM_PROVIDER_MODEL_BINDING_INVALID`,
  `WORKFLOW_DEFINITION_SCHEMA_INVALID`, `WORKFLOW_GRAPH_COMPILE_INVALID` and
  `BOOTSTRAP_ROOT_RESOLUTION_ERROR`;
- retry and repair: `RETRY_LIMIT_EXHAUSTED`, `REPAIR_RECURRING`;
- runner authority: the closed reasons of
  [§6](06-pipeline-nodes.md#runner-rejection-reasons), upper-cased in events, such as
  `REGISTRY_DRIFT` and `STEP_EXECUTION_CEILING`;
- model response: `MISSING_FINAL_TEXT`;
- model-exchange capture: `MODEL_CAPTURE_PERSISTENCE_FAILURE` and the other
  `MODEL_CAPTURE_*` failures;
- feature logging: `LOG_LOCK_TIMEOUT`, `LOG_SINK_FAILURE`, `LOG_SEGMENT_LIMIT_EXHAUSTED`.

A runner rejection names its tag and, for `authority`, one closed reason, which is its
diagnostic on every surface and so never reduces to `failed`. When a later failure
replaces an earlier one, the run keeps the earlier rejection beside the terminal one
([§27](27-observability.md#complete-execution-evidence)).

Diagnostics are sorted deterministically by stage, artifact, location, validator priority, and code. Human-facing messages are rendered from codes and fields; repair logic does not parse prose.

Evidence is separate from diagnostics. It records facts such as a decoded source location, a successfully parsed AST, a passing command, or a successfully published output set. A checklist or task status is derived from evidence and cannot be set by the LLM.

Source-omission authorization retains its typed rejection alongside the existing
review findings and origins. `unlocalized_omission` means the review establishes no
defective upstream producer, so no upstream repair target can be authorized;
`invalid_repair_authority` identifies other rejected authority preconditions.
Reports explain why no repair call occurred; the runner records the same cause.
These diagnostics neither revise semantic verdicts nor grant repair authority.
