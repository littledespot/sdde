# Model prompt and response flow

Shared model-request path, shown with the production Bedrock adapter. Workflow
resources supply task instructions/schema; serialization emits universal JSON
framing once per call.

```mermaid
flowchart TD
    Workflow["Workflow YAML selects<br/>task prompt, result schema and model slot"]
    Config[".sddtoolkit.json<br/>repository model slots and reasoning effort"]
    Policy["Registered workflow policy<br/>total token budget per execution"]
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
    System --> Accounting
    User --> Accounting
    Config --> Request
    Policy --> Accounting
    Request --> LLM["Configured LLM"]
    LLM --> Response["Provider response<br/>final text, stop reason and token usage"]
    Response --> Usage["Account all actual API-reported input and output tokens;<br/>retain usage on failure, stop or cancellation"]
    Usage -->|Overshoot or usage unavailable| Stop
    Usage -->|Accounting permits continuation| Eligible{"Complete final text<br/>from the correct call?"}
    Eligible -->|No| Stop["Failed or cancelled<br/>no candidate accepted"]
    Eligible -->|Yes| Syntax{"Strict JSON decoding<br/>one object, no fences or extra text"}
    Syntax -->|Valid JSON| Shape{"Matches the selected<br/>closed result schema?"}
    Schema -.-> Shape
    Shape -->|Yes| Resolve["Resolve selected evidence in current scope<br/>derive exact source bytes and coordinates"]
    Resolve --> Candidate{"Candidate validators"}
    Candidate -->|Valid| Publish["Continue full workflow validation<br/>before publication;<br/>development harness grades published output"]
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
    Accounting -->|Yes| Request["Prepare and authorize request<br/>serialize and send over HTTPS"]
    Accounting -->|No| Exhausted["Stop with owning limit and count<br/>retain JSON or schema error and all attempts"]
```

[Request guidance](../reference-notes/model-request-guidance.md) details input
projection, source selections, protocol correction, repair and provider modes.
The Specify E2E case currently selects `prompt-only`.

Owners: [response contract](../decisions/0006-minimal-model-response.md),
[workflow request ownership](../decisions/0012-workflow-owned-model-request.md),
[universal framing](../decisions/0014-universal-response-format-guidance.md).
Shape validation yields a candidate; source location and model review do not
prove semantic support or authorize publication.
