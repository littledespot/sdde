# Model prompt and response flow

All workflows use the shared response-format contract. This shows its production
Bedrock request path. The Specify E2E case currently selects `prompt-only`.
Workflow resources supply task instructions and the schema; the engine supplies
the universal JSON framing instruction once when serializing each call.

```mermaid
flowchart TD
    Workflow["Workflow YAML selects<br/>task prompt, result schema and model slot"]
    Config[".sddtoolkit.json<br/>model, reasoning effort and total token budget"]
    Prompt["Task prompt<br/>what to produce and how to use the evidence"]
    Schema["Compiled result schema<br/>fields, types, required values and allowed variants"]
    Input["Engine-prepared input<br/>current unit, source lines, citations and permitted IDs"]
    Format["Shared engine response contract<br/>one JSON object matching the schema<br/>no fences or surrounding text"]

    Workflow --> Prompt
    Workflow --> Schema
    Workflow --> Input
    Prompt --> System["Bedrock system content<br/>task instructions, JSON framing and result schema"]
    Schema --> System
    Schema --> Grammar["Registered provider projection<br/>closed structure and tagged alternatives"]
    Grammar -->|Native mode only| Request
    Format --> System
    Input --> User["Bedrock user content<br/>input data and evidence"]
    System --> Request["Prepare and authorize request<br/>serialize and send over HTTPS"]
    User --> Request
    Config --> Request
    Request --> LLM["Configured LLM"]
    LLM --> Response["Provider response<br/>final text, stop reason and token usage"]
    Response --> Eligible{"Complete final text<br/>from the correct call?"}
    Eligible -->|No| Stop["Failed or cancelled<br/>no candidate accepted"]
    Eligible -->|Yes| Syntax{"Strict JSON decoding<br/>one object, no fences or extra text"}
    Syntax -->|Valid JSON| Shape{"Matches the selected<br/>closed result schema?"}
    Schema -.-> Shape
    Shape -->|Yes| Resolve["Resolve selected evidence in current scope<br/>derive exact source bytes and coordinates"]
    Resolve --> Candidate{"Candidate validators"}
    Candidate -->|Valid| Publish["Continue full workflow validation<br/>before publication and quality grading"]
    Candidate -->|Repairable diagnostic| Authorize["Native authorization selects one unit<br/>retains owner, revision and old value"]
    Authorize --> Repair["Same model-request path<br/>selected replacement schema, evidence and diagnostic"]
    Repair --> Merge["Verify request association and old value<br/>merge only authorized replacement"]
    Merge --> Resolve
    Candidate -->|Unrepairable or exhausted| Stop
    Syntax -->|Invalid JSON| Retry{"Workflow selects<br/>protocol correction?"}
    Shape -->|Schema rejection| Retry
    Retry -->|No| Stop
    Retry -->|Yes| Correction["Original prompt, input and schema<br/>plus correction guidance and latest rejection<br/>No accumulated correction history"]
    Correction --> Accounting{"Existing attempt-accounting limit<br/>and global token budget allow a call?"}
    Accounting -->|Yes| Request
    Accounting -->|No| Exhausted["Stop with owning limit and count<br/>retain JSON or schema error and all attempts"]
```

Inputs and responses share the `kind` wire codec. Evidence projections remove
internal validation wrappers; preserved-token content references IDs whose exact
values and citations are retained in `preserved_tokens`. Reconciliation,
generation, review and repair reuse this representation.

Extraction returns source-line selections `{first: {ordinal}, last: {ordinal}}`
with inclusive endpoints. Lines retain original endings; separate selections
represent discontiguous support. Exact tokens retain extractor-owned finer spans.
The model supplies neither quote bytes nor coordinates. Canonical citations are
assigned after validation and rechecked against captured sources on load.

Invalid selections produce typed diagnostics and use the existing replacement
authorization. Each diagnostic retains the originating request/attempt, including
after request release; repairing one citation leaves sibling attribution intact.
Selecting an existing passage proves source location, not semantic support.

The LLM receives the following response-shape guidance:

| When | Guidance actually sent |
| --- | --- |
| Every call | “Return exactly one JSON object matching the supplied schema. No Markdown fences or surrounding text.” This shared engine-owned instruction is emitted once by serialization for every workflow and both response modes. |
| First call | The selected task prompt, input and complete compiled JSON result schema. The schema alone defines allowed properties, required fields, types, bounds and variants. |
| JSON or schema retry | The original task content plus the selected protocol prompt, the exact rejected response as untrusted evidence, the decoder position and object/key context or schema JSON Pointer, and shape examples generated from the same schema. Syntax examples expose nested array items; schema errors show the expected shape's alternatives. The protocol prompt prohibits reconsidering business meaning. Serialization emits the same universal framing instruction once; it does not accumulate in retained retry content. |
| Atomic repair | The shared replacement prompt plus the validator diagnostic, selected unit, old value and scoped evidence. Only a replacement matching the selected schema is accepted; target and revision remain engine-owned. |
| After the response | The engine independently requires one complete JSON object and rejects Markdown fences, duplicate keys, trailing text and schema violations. Passing these checks supplies candidate data, not proof of business quality or permission to publish. |

The framing instruction describes the existing JSON boundary. It introduces
no schema, business rules or workflow authority. Workflow templates and the
evaluator no longer supply independent copies. A model can still disregard the
instruction; validation remains mandatory and rejected bytes remain evidence.

For `native-schema` requests, the shared serializer derives Bedrock-supported
constraints for `outputConfig` from the compiled schema. The complete schema
remains in system guidance and engine validation. Tagged `oneOf` becomes disjoint
`anyOf`; unsupported bounds remain engine-enforced. Specify retains
`prompt-only`: the configured model failed the native tagged-schema live checks. Explicit token counting uses the same text input as inference.

Implementation references: [workflow selection](../workflows/spec.workflow.yaml),
[request preparation](../../src/application/model_request_workflow.zig),
[shared framing](../../src/domain/model_controls.zig),
[Bedrock serialization](../../src/adapters/provider/bedrock_request.zig),
[protocol retry](../../src/domain/model_protocol_retry.zig),
[strict decoder](../../src/domain/model_envelope.zig) and
[schema validation](../../src/domain/model_payload_schema.zig).
The response contract is defined by [ADR 0006](../decisions/0006-minimal-model-response.md);
task prompt ownership is defined by [ADR 0012](../decisions/0012-workflow-owned-model-request.md)
and universal framing by [ADR 0014](../decisions/0014-universal-response-format-guidance.md).
