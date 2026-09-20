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
- Latest native validation error in model-visible guidance: decoder reason/position
  and object/key context, or schema reason and JSON Pointer. A terminal/log-only
  diagnostic does not meet this requirement.
- For schema rejection: the candidate JSON Pointer and parent/value scope, an
  exact locator in the single complete schema, and derived immediate fields, child-object required names and
  discriminator values. Alternatives and bounds remain in that schema.

The protocol prompt requires the complete corrected response, preserving unaffected
entries and business meaning. The diagnostic locates the defect; it does not narrow
the response schema. For an atomic repair, that schema is already the selected
replacement, not the whole candidate. Schema and domain validation still apply;
syntax correction cannot recover omitted requirements. No candidate examples or
accumulated correction prompts are added.

In [R45](../../fixes/FIX_001.md#47-brief-schema-exhaustion-despite-child-object-guidance),
both corrections already included `unknown_property` at `/provenance`, required
child `value`/`provenance` fields and the rejected response. The first correction
therefore differed from initial generation; the second correction repeated the
first because the latest error and rejected response were unchanged. Use captured
request/response bytes to establish repetition, rather than temperature alone.

The user-requested [explicit-error guidance](../contracts/22-repair.md#2262-explicit-error-guidance)
is implemented through the same `build-model-protocol-retry` action. The error has
a plain-language explanation; the existing structured outline supplies allowed
fields and child requirements. Together they convey the following for R45
(illustrative wording, not an additional prompt):

```text
The previous response failed schema validation.
Error at /provenance: this property is not allowed on the root object.
Allowed root fields: kind, title, description, primary_goal.
Each title, description and primary_goal object requires value and provenance.
Return the complete corrected response matching the supplied schema.
Correct the reported errors; preserve unaffected entries and meaning.
```

The field names above come from R45's selected schema, not hardcoded prompt rules.
Keep the typed error and schema locator alongside the explanation. Decoder errors
instead explain their parser reason/location; missing answers explicitly request
the absent final response without attaching a body or reasoning.

Confirmed recurrence adds one sentence: “The previous correction still failed this
validation.” The handoff retains the preceding typed rejection with its prepared
correction, verifies the next response's exact association and compares diagnostic
identity before passing the fact to the builder. This adds no allowance, temperature change or
semantic reassessment. Native defects and operational failures retain their owners.

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

## Configured smaller outputs — implemented boundary

[ADR 0016](../decisions/0016-configured-json-response-composition.md) separates
cohesive response parts while retaining relevant input evidence. Each call receives
its configured task and exact derived part schema; correction requests that complete
part. Replace combined-output instructions at each part's initial/correction call
site; a narrowed schema must not accompany a prompt requesting sibling fields.
Native assembly receives admitted values and a compiled structural mapping,
with **no LLM prompt or call**. Existing full validation, native repair and total-token
accounting remain. Extraction separates content from dependent token classifications;
global reconciliation separates dispositions, signals and conflicts. Arrays and
optional containers remain whole. These paths are implemented; the retained runs
do not establish a measured reliability improvement or a completed, scored baseline.

## Proposed conformance improvements — 20 September 2026

The table distinguishes implemented guidance from remaining assessments; linked
contracts own each boundary. [Chunk 18's current follow-up](../../fixes/IMP_001.md#r45-follow-up--brief-conformance-after-child-object-guidance)
owns sequencing and approval decisions. R38 repeated incorrect nested wrappers
despite the correct schema; R39 corrected its JSON and then reached a separate
semantic-review problem. Measure structural compliance and semantic quality separately.

| Improvement to assess | Existing owner and boundary |
| --- | --- |
| Assignment-specific instructions | Request/assignment guidance supplies only relevant generation rules, shared JSON framing and necessary evidence. Remove sibling-unit instructions consistently from initial and correction inputs; do not create parallel prompts for every failure. |
| Precise nested correction guidance | The feasibility review selects [one nonrecursive child-object required-field annotation](../contracts/22-repair.md#2261-child-object-requirements), approved on 20 September 2026. Reuse the shared projection and protocol builder with the same selected schema; no branch selection, evidence relocation or candidate synthesis. |
| Explicit error explanations | [§22.6.2](../contracts/22-repair.md#2262-explicit-error-guidance) is implemented through typed diagnostics and schema projection, with repetition wording only from confirmed prior-correction evidence. [R45 delivery](../../fixes/IMP_001.md#r45-delivery--explicit-correction-errors) records offline verification; live effectiveness remains unproven. |
| Model and response-mode comparison | Reuse existing provider binding, schema projection and request capture. Explicitly compare the configured baseline with native mode or another registered, authorized model; change one factor at a time. No automatic fallback, hidden model escalation or new retry owner. |
| Further response decomposition | Reuse ADR 0016 for measured object-shape difficulties. Array-item decomposition remains deferred until finite assignments, stable identities, unique ownership, coverage/order and dependency renewal have accepted authority. Do not add arbitrary splitting, flattening or another assembler. |
| Native derivation of mechanical fields | Reuse existing native construction where accepted inputs determine the value uniquely. Required evidence selections, relationships and business meaning remain explicit candidate data. Changing a wire shape requires consistent schema, decoding, repair, provenance and persisted-validation changes; a formatter cannot infer missing support. |
| Measured model reliability | Reuse the existing harness and captured requests under [§28.8](../contracts/28-testing.md#288-model-conformance-comparisons). Scripted acceptance/rejection tests establish engine enforcement; controlled live comparisons establish model behavior. |

Start with assignment guidance and the focused nested-shape assessment, then compare
model/mode choices. Further decomposition or native derivation needs evidence of a
remaining problem. Successful parts retain their dependencies and provenance;
shared retries, full validation and global token accounting remain unchanged.
Unresolved JSON/schema rejection ends in error without specification publication,
including when clarification forms are open.

## Nested-correction feasibility

**Feasible within existing owners; model benefit remains unproven.** The latest
[R40 evidence](../../fixes/FIX_001.md#42-brief-wrapper-recurrence-and-correction-feasibility)
repeats R38's misplaced root provenance. The validator reports that first unknown
property before visiting children. Its expected node already identifies the brief
branch; the outline reduces each child object to its type. The complete schema is
present, so the opportunity is visibility of the required nesting, not recovery of
lost schema information or proof that the prompt caused the model failure.

| Boundary | Existing responsibility and proposed effect |
| --- | --- |
| Schema compilation/selection | The canonical compiled schema owns fields and requiredness. Named results, configured parts and narrowed native repairs keep their exact binding. No schema or composition format changes. |
| Schema validation | `model_payload_schema` retains its first diagnostic and selected expected node. No extra candidate traversal, defect collection or inferred union selection is needed. |
| Shape projection | `model_schema_projection` adds required names to immediate object-valued field descriptors under the approved §22.6.1 rule. It reads schema data only. |
| Correction/preparation | `model_protocol_retry` uses the projection; `model_request_preparation` copies rendered guidance from scratch into request-owned memory. Original assignment/input/schema and latest rejected response remain associated. |
| Provider/logging | Existing serialization sends the guidance and single complete acceptance schema; native mode retains its existing derived grammar. Existing request capture records the changed bytes without a new log or debugger contract. |
| Admission/continuation | The existing runner accounts each call, applies the same assignment allowance and revalidates the full response. Native merge/full validation and deterministic composition preserve authorized scope, sibling data, dependencies and provenance. |

For example, the derived descriptor for `title` is now:

```json
{"type":"object","required":["value","provenance"]}
```

This is explanatory output derived from the configured schema, not a hard-coded
brief rule or a candidate template. It does not say which claims support a field
or authorize copying the rejected root provenance into every child. Deeper defects
remain governed by the full schema and subsequent diagnostics; this amendment does
not recursively expand objects or array items. Repeated failure still exhausts.

The [implementation and offline verification record](../../fixes/IMP_001.md#focused-226-decision--child-object-requirements)
cover unrelated shapes, optional fields, exact selected-schema ownership, cleanup,
recovery and exhaustion. Request-size evidence measures overhead, not reliability;
approved controlled calls are still needed to measure model outcomes under §28.8.

## Provider mode and implementation evidence

- In `native-schema` mode, the shared serializer projects Bedrock-supported
  `outputConfig` constraints from the compiled schema.
- The complete schema remains in system guidance and engine validation.
- Tagged `oneOf` becomes disjoint `anyOf`; unsupported bounds stay engine-enforced.
- Explicit token counting uses the same text input as inference.
- The Specify E2E case uses `prompt-only`: its configured model failed native
  tagged-schema live checks. This records the existing case selection, not a
  waiver of validation or new E2E evidence.

AWS documents [structured-output support for gpt-oss-20b](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-openai-gpt-oss-20b.html)
and [schema-constrained Converse output](https://docs.aws.amazon.com/bedrock/latest/userguide/structured-output.html)
(checked 20 September 2026). Availability does not overturn the
[retained native-mode failures](../../fixes/FIX_001.md#47-native-mode-and-retry-counts-are-not-demonstrated-solutions)
or prove improvement for the configured provider/model/schema combination. A
comparison must record the actual mode and full engine-validation results.

| Responsibility | Source |
| --- | --- |
| Workflow selection | [spec.workflow.yaml](../workflows/spec.workflow.yaml) |
| Request preparation | [model_request_workflow.zig](../../src/application/model_request_workflow.zig) |
| Shared framing | [model_controls.zig](../../src/domain/model_controls.zig) |
| Bedrock serialization | [bedrock_request.zig](../../src/adapters/provider/bedrock_request.zig) |
| Protocol retry | [model_protocol_retry.zig](../../src/domain/model_protocol_retry.zig) |
| Strict decoding | [model_envelope.zig](../../src/domain/model_envelope.zig) |
| Schema validation | [model_payload_schema.zig](../../src/domain/model_payload_schema.zig) |
