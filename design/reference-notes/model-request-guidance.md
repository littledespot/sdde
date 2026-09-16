# Model request and response guidance

Companion to the [request-flow diagram](../diagrams/17-model-prompt-response-flow.md).
This summarizes the existing contracts in
[ADR 0006](../decisions/0006-minimal-model-response.md),
[ADR 0012](../decisions/0012-workflow-owned-model-request.md) and
[ADR 0014](../decisions/0014-universal-response-format-guidance.md).

## Input and evidence representation

- Inputs and responses share the `kind` wire codec.
- Evidence projections remove internal validation wrappers.
- Content references preserved-token IDs; `preserved_tokens` retains exact values
  and citations across reconciliation, generation, review and repair.
- Extraction selects source lines as `{first: {ordinal}, last: {ordinal}}`, with
  inclusive endpoints and original line endings. Separate selections represent
  discontiguous support; exact tokens retain extractor-owned finer spans.
- Models supply neither quote bytes nor coordinates. The engine assigns citations
  after validation and rechecks them against captured sources on load.
- Invalid selections retain typed diagnostics and existing replacement authority.
  Diagnostics preserve originating request/attempt even after request release;
  repairing one citation preserves sibling attribution.
- Source selection proves location, not semantic support.

## Guidance by call type

**Every call** receives one shared engine instruction, emitted once by serialization
for every workflow and both response modes:

> Return exactly one JSON object matching the supplied schema. No Markdown fences or surrounding text.

- Workflow resources supply task instructions and the complete compiled result schema.
- The schema defines allowed properties, required fields, types, bounds and variants.
- Universal framing adds no schema, business rules or workflow authority. Templates
  and the evaluator do not supply independent copies.

**Protocol correction** receives:

- Original task content, selected protocol prompt and complete original schema.
- Exact rejected response as untrusted evidence.
- Decoder position and object/key context, or the schema JSON Pointer.
- For schema rejection: the exact expected schema node, its JSON Pointer and
  parent/value scope, preserving alternatives and bounds.

The protocol prompt prohibits reconsidering business meaning. No candidate
examples are generated. Retained retry content accumulates no framing copies;
serialization emits the shared instruction once per call.

**Atomic repair** receives:

- Shared replacement prompt and validator diagnostic.
- Selected unit, `current_value` for replacements, scoped evidence and selected schema.

When native claim selection fixes the content kind, statement/signal repairs receive
only that payload schema. Native decoding restores the retained kind; the model does
not repeat it. Target/revision ownership, sibling preservation and full validation
remain with the existing repair owners.

**Support review** returns one `decision` with evidence and brief detail. Native
policy supplies fixed applicability; `not_applicable` is a separate permitted
decision only when applicability still needs review. Initial and missing-finding
requests select the same closed shapes. Detail/evidence repairs preserve decisions;
admission and persisted validation share native assembly. Source review assesses
meaning sufficient to derive content, without requiring prewritten spec fields.
Packets replace native ledger tuples with short semantic tasks. The shared review
evidence owner supplies claim minimums, eligible/exact sets and current candidate
provenance to both admission and guidance. Corrections retain the precise failing
rule once, preserving the decision; insertion retains the available choices.
Absent presentation fields are omitted without removing source/extraction evidence.

**After every response**, the engine independently requires one complete JSON object.
It rejects fences, duplicate keys, trailing text and schema violations. Rejected
bytes remain evidence. Valid shape yields candidate data, not business-quality
proof or publication authority.

## Provider mode and implementation evidence

- In `native-schema` mode, the shared serializer projects Bedrock-supported
  `outputConfig` constraints from the compiled schema.
- The complete schema remains in system guidance and engine validation.
- Tagged `oneOf` becomes disjoint `anyOf`; unsupported bounds stay engine-enforced.
- Explicit token counting uses the same text input as inference.
- The Specify E2E case uses `prompt-only`: its configured model failed native
  tagged-schema live checks. This records the existing case selection, not a
  waiver of validation or new E2E evidence.

| Responsibility | Source |
| --- | --- |
| Workflow selection | [spec.workflow.yaml](../workflows/spec.workflow.yaml) |
| Request preparation | [model_request_workflow.zig](../../src/application/model_request_workflow.zig) |
| Shared framing | [model_controls.zig](../../src/domain/model_controls.zig) |
| Bedrock serialization | [bedrock_request.zig](../../src/adapters/provider/bedrock_request.zig) |
| Protocol retry | [model_protocol_retry.zig](../../src/domain/model_protocol_retry.zig) |
| Strict decoding | [model_envelope.zig](../../src/domain/model_envelope.zig) |
| Schema validation | [model_payload_schema.zig](../../src/domain/model_payload_schema.zig) |
