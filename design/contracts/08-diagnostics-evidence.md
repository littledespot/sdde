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

The run report and the CLI carry the last model call's typed provider failure as
presentation data beside the outcome tag (approved by the user on 20 November 2026): the
closed cause, retry class and delivery, and the transport phase and cause or content
diagnostic when the failure has one
([F0006 §8](../features/F0006-LLMProviderInterface.md)). The runner takes it from the call's
validated result, where a rejected body's content diagnostic is formed, and from the
authorization result of a call that was never sent, such as one with no key. A call's
authorization replaces an earlier call's detail, so it names the last call. It adds no tag,
code or branch and is never a runner rejection; a provider stop and a runner rejection, such
as retry exhaustion, show none. The CLI prints it after an `invalid`, `blocked`, `failed` or
`cancelled` outcome as
`provider_failure: <cause>; delivery=<d>; retry=<r>[; transport=<phase>/<cause>][; content=<c>]`;
only these enum names are printed, never a key, header, body, URL or provider text.

Diagnostics are sorted deterministically by stage, artifact, location, validator priority, and code. Human-facing messages are rendered from codes and fields; repair logic does not parse prose.

Evidence is separate from diagnostics. It records facts such as a decoded source location, a successfully parsed AST, a passing command, or a successfully published output set. A checklist or task status is derived from evidence and cannot be set by the LLM.

Source-omission authorization retains its typed rejection alongside the existing
review findings and origins. `unlocalized_omission` means the review establishes no
defective upstream producer, so no upstream repair target can be authorized;
`invalid_repair_authority` identifies other rejected authority preconditions.
Reports explain why no repair call occurred; the runner records the same cause.
These diagnostics neither revise semantic verdicts nor grant repair authority.
